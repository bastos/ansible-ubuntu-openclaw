#!/usr/bin/env bash
set -euo pipefail

OP_TS_ITEM_ID="rawvqo5ow2jdbi5u2bjbhshkgu"
OP_BECOME_ITEM_ID="l77hcnkfqwyrm4qlyfauqliyuy"
OP_SERVICE_ACCCOUNT_ITEM_ID="mz2pv43wg5qdl2qmkdghkuz7w4"
OP_OPENROUTER_ITEM_ID="n5pdttlocvil3ns5hortf5rweq"
# Optional overrides; leave empty to use op defaults.
OP_ACCOUNT="${OP_ACCOUNT:-}"
OP_VAULT="${OP_VAULT:-}"
force_env=false
force_1p=false
source_mode="auto"
print_env=false

usage() {
  cat <<'USAGE'
Usage: ./run.sh [options] [-- <ansible-playbook-args>]

Options:
  --ts-auth-key <key>     Tailscale auth key (overrides 1Password lookup)
  --op-service-account-token <token>
                           1Password service account token (overrides 1Password lookup)
                           Alias: --op-service-acccount-token
  --openrouter-api-key <key>
                           OpenRouter API key (overrides 1Password lookup)
  --force-env             Force secrets from environment variables
  --force-1p              Force secrets from 1Password (ignores args/env)
  --dry-run, --print-env  Resolve secrets and print exports/command only
  --check                 Run ansible-playbook in check mode
  --verbose               Run ansible-playbook with -vv
  -h, --help              Show this help

Notes:
  - Default precedence: argument > environment > 1Password.
  - Env vars used: TAILSCALE_AUTHKEY, OP_SERVICE_ACCOUNT_TOKEN,
    OPENROUTER_API_KEY, ANSIBLE_BECOME_PASS.
  - Use --force-env to require env vars and skip 1Password.
  - Use --force-1p to read all secrets from 1Password, ignoring args/env.
  - Use --dry-run/--print-env to show what would run without executing.
  - Tailscale auth key: 1Password item ID rawvqo5ow2jdbi5u2bjbhshkgu.
  - OP service account token: 1Password item ID mz2pv43wg5qdl2qmkdghkuz7w4.
  - OpenRouter API key: 1Password item ID n5pdttlocvil3ns5hortf5rweq.
  - Sudo password: 1Password item ID l77hcnkfqwyrm4qlyfauqliyuy.
  - This script exports TAILSCALE_AUTHKEY, OP_SERVICE_ACCOUNT_TOKEN,
    OPENROUTER_API_KEY, and, when available, ANSIBLE_BECOME_PASS for playbook.yml.
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

declare -A op_item_cache=()

fetch_item_json_cached() {
  local item_id="$1"
  if [[ -z "${op_item_cache[$item_id]:-}" ]]; then
    op_item_cache["$item_id"]="$(fetch_item_json "$item_id")"
  fi
  printf '%s' "${op_item_cache[$item_id]}"
}

ts_auth_key=""
OP_SERVICE_ACCOUNT_TOKEN=""
OPENROUTER_API_KEY=""
become_password=""
extra_args=()
check_mode=false
verbose=false

extract_concealed_field() {
  local label_regex="$1"
  jq -r --arg re "$label_regex" '
    (.fields // []) as $fields
    | (
        ($fields
          | map(select(.label | test($re; "i")))
          | map(select((.type == "CONCEALED") or (.purpose == "PASSWORD")))
          | .[0].value
        )
        // ($fields | map(select(.purpose == "PASSWORD")) | .[0].value)
        // ($fields | map(select(.type == "CONCEALED")) | .[0].value)
      ) // empty
  '
}

resolve_single_secret() {
  local label="$1"
  local arg_value="$2"
  local env_name="$3"
  local item_id="$4"
  local label_regex="$5"
  local missing_hint="$6"
  local value=""

  case "$source_mode" in
    env)
      value="${!env_name:-}"
      [[ -n "$value" ]] || die "missing $label in environment ($env_name); remove --force-env or set $env_name"
      ;;
    1p)
      require_op_jq
      value="$(fetch_item_json_cached "$item_id" | extract_concealed_field "$label_regex")"
      [[ -n "$value" ]] || die "could not find $label in 1Password item $item_id"
      ;;
    auto)
      if [[ -n "$arg_value" ]]; then
        value="$arg_value"
      elif [[ -n "${!env_name:-}" ]]; then
        value="${!env_name}"
      else
        require_op_jq
        value="$(fetch_item_json_cached "$item_id" | extract_concealed_field "$label_regex")"
        if [[ -z "$value" ]]; then
          if [[ -n "$missing_hint" ]]; then
            die "could not find $label in 1Password item $item_id; $missing_hint"
          else
            die "could not find $label in 1Password item $item_id; set $env_name"
          fi
        fi
      fi
      ;;
    *)
      die "unknown source mode: $source_mode"
      ;;
  esac

  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ts-auth-key)
      [[ $# -ge 2 ]] || die "--ts-auth-key requires a value"
      ts_auth_key="$2"
      shift 2
      ;;
    --ts-auth-key=*)
      ts_auth_key="${1#*=}"
      shift
      ;;
    --op-service-account-token|--op-service-acccount-token)
      [[ $# -ge 2 ]] || die "--op-service-account-token requires a value"
      OP_SERVICE_ACCOUNT_TOKEN="$2"
      shift 2
      ;;
    --op-service-account-token=*|--op-service-acccount-token=*)
      OP_SERVICE_ACCOUNT_TOKEN="${1#*=}"
      shift
      ;;
    --openrouter-api-key)
      [[ $# -ge 2 ]] || die "--openrouter-api-key requires a value"
      OPENROUTER_API_KEY="$2"
      shift 2
      ;;
    --openrouter-api-key=*)
      OPENROUTER_API_KEY="${1#*=}"
      shift
      ;;
    --force-env)
      force_env=true
      shift
      ;;
    --force-1p)
      force_1p=true
      shift
      ;;
    --dry-run|--print-env)
      print_env=true
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

if [[ "$force_env" == "true" && "$force_1p" == "true" ]]; then
  die "cannot combine --force-env and --force-1p"
fi

if [[ "$force_env" == "true" ]]; then
  source_mode="env"
elif [[ "$force_1p" == "true" ]]; then
  source_mode="1p"
fi

ts_auth_key="$(resolve_single_secret \
  "Tailscale auth key" \
  "$ts_auth_key" \
  "TAILSCALE_AUTHKEY" \
  "$OP_TS_ITEM_ID" \
  "tailscale|auth|key" \
  "pass --ts-auth-key or set TAILSCALE_AUTHKEY")"

OP_SERVICE_ACCOUNT_TOKEN="$(resolve_single_secret \
  "OP service account token" \
  "$OP_SERVICE_ACCOUNT_TOKEN" \
  "OP_SERVICE_ACCOUNT_TOKEN" \
  "$OP_SERVICE_ACCCOUNT_ITEM_ID" \
  "service|account|token" \
  "pass --op-service-account-token or set OP_SERVICE_ACCOUNT_TOKEN")"

OPENROUTER_API_KEY="$(resolve_single_secret \
  "OpenRouter API key" \
  "$OPENROUTER_API_KEY" \
  "OPENROUTER_API_KEY" \
  "$OP_OPENROUTER_ITEM_ID" \
  "openrouter|api|key|token" \
  "pass --openrouter-api-key or set OPENROUTER_API_KEY")"

become_password="$(resolve_single_secret \
  "sudo password" \
  "" \
  "ANSIBLE_BECOME_PASS" \
  "$OP_BECOME_ITEM_ID" \
  "sudo|become|password|pass" \
  "set ANSIBLE_BECOME_PASS")"

env_vars=("TAILSCALE_AUTHKEY=$ts_auth_key")
if [[ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]]; then
  env_vars+=("OP_SERVICE_ACCOUNT_TOKEN=$OP_SERVICE_ACCOUNT_TOKEN")
fi
if [[ -n "$OPENROUTER_API_KEY" ]]; then
  env_vars+=("OPENROUTER_API_KEY=$OPENROUTER_API_KEY")
fi
if [[ -n "$become_password" ]]; then
  env_vars+=("ANSIBLE_BECOME_PASS=$become_password")
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

if [[ "$print_env" == "true" ]]; then
  for pair in "${env_vars[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    printf 'export %s=%q\n' "$key" "$value"
  done
  printf 'ansible-playbook'
  for arg in "${ansible_args[@]}"; do
    printf ' %q' "$arg"
  done
  printf '\n'
  exit 0
fi

env "${env_vars[@]}" ansible-playbook "${ansible_args[@]}"
