# Ansible Playbook

Provisions Ubuntu workstations with development tools and configurations.

## Quick Start

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Edit inventory with your target host
vim bastos-ubuntu-workstation

# Run (prompts for sudo password)
ansible-playbook playbook.yml -K
```

## Files

```
ansible/
├── ansible.cfg              # Defaults (inventory, become)
├── bastos-ubuntu-workstation # Inventory
├── playbook.yml             # Main playbook
├── group_vars/all.yml       # Variables
└── requirements.yml         # Required collections
```

## Inventory Setup

Edit `bastos-ubuntu-workstation` with your target machine:

```ini
[workstations]
ubuntu-workstation ansible_host=192.168.1.100 ansible_user=bastos
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
