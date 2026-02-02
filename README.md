# Ansible Playbook

Provisions OpenClaw with development tools and configurations.

## Quick Start

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Edit inventory with your target host
vim bender

# Run (prompts for sudo password)
ansible-playbook playbook.yml -K

# SSH into the machine
ssh openclaw@[tailnet]

# Run the onboarding script
openclaw onboard --install-daemon

# Run the doctor
openclaw doctor

# Open the dashboard
openclaw dashboard
```

## Files

```
ansible/
├── ansible.cfg              # Defaults (inventory, become)
├── bender   # Inventory
├── playbook.yml             # Main playbook
├── group_vars/all.yml       # Variables
└── requirements.yml         # Required collections
```

## Inventory Setup

Edit `bender` with your target machine:

```ini
[openclaws]
ubuntu-openclaw ansible_host=192.168.1.100 ansible_user=bender
```

## Customization

Edit `group_vars/all.yml` to modify:

- `base_packages` / `third_party_packages` — APT packages
- `ruby_build_packages` — Ruby build dependencies
- `docker_ce_packages` — Docker package set
- `apt_repos` — Third-party repositories
- `brew_packages` — Homebrew packages
- `brew_prefix` — Homebrew install prefix
- `mise_tools` — Language runtimes
- `ssh_public_key` — Authorized SSH key
- `target_user` — Target username
