#!/usr/bin/env bash
set -euo pipefail

OP_TS_ITEM_ID="rawvqo5ow2jdbi5u2bjbhshkgu"
OP_RDP_ITEM_ID="l77hcnkfqwyrm4qlyfauqliyuy"
# Optional overrides; leave empty to use op defaults.
OP_ACCOUNT="${OP_ACCOUNT:-}"
OP_VAULT="${OP_VAULT:-}"

usage() {
  cat <<'USAGE'
Usage: ./run.sh [options] [-- <ansible-playbook-args>]

Options:
  --ts-auth-key <key>     Tailscale auth key (overrides 1Password lookup)
  --rdp-password <pass>   RDP password (optional; sets RDP_PASSWORD env var)
  --check                 Run ansible-playbook in check mode
  --verbose               Run ansible-playbook with -vv
  -h, --help              Show this help

Notes:
  - If --ts-auth-key is not provided, the script reads it from 1Password item
    ID rawvqo5ow2jdbi5u2bjbhshkgu using the `op` CLI.
  - If --rdp-password is not provided, the script reads it from 1Password item
    ID l77hcnkfqwyrm4qlyfauqliyuy using the `op` CLI.
  - The same 1Password item is used to set ANSIBLE_BECOME_PASS so sudo does
    not prompt (only falls back to -K if no password is available).
  - This script exports TAILSCALE_AUTHKEY and RDP_PASSWORD for playbook.yml.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_op_jq() {
  command -v op >/dev/null 2>&1 || die "op CLI not found; install 1password-cli or pass the value explicitly"
  command -v jq >/dev/null 2>&1 || die "jq not found; install jq or pass the value explicitly"
}

fetch_item_json() {
  local item_id="$1"
  local item_json
  local op_args=(item get "$item_id" --format json)
  if [[ -n "$OP_ACCOUNT" ]]; then
    op_args+=(--account "$OP_ACCOUNT")
  fi
  if [[ -n "$OP_VAULT" ]]; then
    op_args+=(--vault "$OP_VAULT")
  fi
  if ! item_json="$(op "${op_args[@]}" 2>/dev/null)"; then
    die "failed to read 1Password item $item_id; run 'op signin' or pass the value explicitly"
  fi
  printf '%s' "$item_json"
}

rdp_password=""
ts_auth_key=""
become_password=""
system_rdp_user="${SYSTEM_RDP_USER:-bastos}"
system_rdp_password="${SYSTEM_RDP_PASSWORD:-}"
extra_args=()
check_mode=false
verbose=false

extract_password() {
  jq -r '
    (.fields // []) as $fields
    | (
        ($fields
          | map(select(.label | test("rdp|remote|desktop|password"; "i")))
          | map(select((.type == "CONCEALED") or (.purpose == "PASSWORD")))
          | .[0].value
        )
        // ($fields | map(select(.purpose == "PASSWORD")) | .[0].value)
        // ($fields | map(select(.type == "CONCEALED")) | .[0].value)
      ) // empty
  '
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rdp-password)
      [[ $# -ge 2 ]] || die "--rdp-password requires a value"
      rdp_password="$2"
      shift 2
      ;;
    --rdp-password=*)
      rdp_password="${1#*=}"
      shift
      ;;
    --ts-auth-key)
      [[ $# -ge 2 ]] || die "--ts-auth-key requires a value"
      ts_auth_key="$2"
      shift 2
      ;;
    --ts-auth-key=*)
      ts_auth_key="${1#*=}"
      shift
      ;;
    --check)
      check_mode=true
      shift
      ;;
    --verbose)
      verbose=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$ts_auth_key" ]]; then
  require_op_jq
  ts_auth_key="$(fetch_item_json "$OP_TS_ITEM_ID" | jq -r '
    (.fields // []) as $fields
    | (
        ($fields
          | map(select(.label | test("tailscale|auth|key"; "i")))
          | map(select((.type == "CONCEALED") or (.purpose == "PASSWORD")))
          | .[0].value
        )
        // ($fields | map(select(.purpose == "PASSWORD")) | .[0].value)
        // ($fields | map(select(.type == "CONCEALED")) | .[0].value)
      ) // empty
  ')"

  [[ -n "$ts_auth_key" ]] || die "could not find a Tailscale auth key in 1Password item $OP_TS_ITEM_ID; pass --ts-auth-key"
fi

# Allow environment to provide RDP_PASSWORD if not passed explicitly.
if [[ -z "$rdp_password" && -n "${RDP_PASSWORD:-}" ]]; then
  rdp_password="$RDP_PASSWORD"
fi

# Allow environment to provide sudo/become password.
if [[ -z "$become_password" && -n "${ANSIBLE_BECOME_PASS:-}" ]]; then
  become_password="$ANSIBLE_BECOME_PASS"
fi

item_json=""
if [[ -z "$rdp_password" || -z "$become_password" ]]; then
  require_op_jq
  item_json="$(fetch_item_json "$OP_RDP_ITEM_ID")"
fi

if [[ -z "$rdp_password" ]]; then
  rdp_password="$(printf '%s' "$item_json" | extract_password)"
  [[ -n "$rdp_password" ]] || die "could not find an RDP password in 1Password item $OP_RDP_ITEM_ID; pass --rdp-password"
fi

if [[ -z "$become_password" ]]; then
  become_password="$(printf '%s' "$item_json" | extract_password)"
  [[ -n "$become_password" ]] || die "could not find a sudo password in 1Password item $OP_RDP_ITEM_ID; set ANSIBLE_BECOME_PASS"
fi

if [[ -z "$system_rdp_password" ]]; then
  system_rdp_password="$rdp_password"
fi

env_vars=("TAILSCALE_AUTHKEY=$ts_auth_key")
if [[ -n "$rdp_password" ]]; then
  env_vars+=("RDP_PASSWORD=$rdp_password")
fi
if [[ -n "$become_password" ]]; then
  env_vars+=("ANSIBLE_BECOME_PASS=$become_password")
fi
if [[ -n "$system_rdp_user" ]]; then
  env_vars+=("SYSTEM_RDP_USER=$system_rdp_user")
fi
if [[ -n "$system_rdp_password" ]]; then
  env_vars+=("SYSTEM_RDP_PASSWORD=$system_rdp_password")
fi

ansible_args=(playbook.yml)
if [[ -z "$become_password" ]]; then
  ansible_args+=(-K)
fi
if [[ "$check_mode" == "true" ]]; then
  ansible_args+=(--check)
fi
if [[ "$verbose" == "true" ]]; then
  ansible_args+=(-vv)
fi
ansible_args+=("${extra_args[@]}")

env "${env_vars[@]}" ansible-playbook "${ansible_args[@]}"
