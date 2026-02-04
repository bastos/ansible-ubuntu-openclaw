# Repository Guidelines

## Project Structure & Module Organization
This repository is a single Ansible playbook that provisions OpenClaw. Key paths:

- `playbook.yml` holds the task list in execution order.
- `group_vars/all.yml` defines variables and package lists.
- `bender` is the default inventory file (set in `ansible.cfg`).
- `requirements.yml` lists required Ansible collections.
- `ansible.cfg` configures inventory and privilege escalation defaults.

Keep playbook changes focused on `playbook.yml` and adjust user-specific values in `group_vars/all.yml`.

## Build, Test, and Development Commands
Run commands from the repository root:

- `ansible-galaxy collection install -r requirements.yml` installs required collections.
- `ansible-playbook playbook.yml -K` runs the full openclaw provisioning (prompts for sudo).
- `ansible-playbook playbook.yml -K --check --diff` performs a dry-run and shows planned changes.

## Coding Style & Naming Conventions
- YAML uses 2-space indentation and aligned lists, matching existing files.
- Prefer fully qualified module names (`ansible.builtin.*`, `community.general.*`).
- Variables use `snake_case` and are defined in `group_vars/all.yml`.
- Inventory groups are plural nouns (e.g., `[openclaws]`).

## Testing Guidelines
There are no automated tests. Validate changes by running the playbook against a disposable VM, then re-run to confirm idempotency (no unexpected changes on the second pass). Use `--check --diff` for quick validation before applying changes.

## Commit & Pull Request Guidelines
This repo has no commit history yet, so no established convention exists. Use concise, imperative summaries (e.g., `add mise tooling`, `update base packages`).

PRs should include:

- A short summary of behavior changes.
- Any updates to `group_vars/all.yml` or inventory expectations.
- Notes about required host OS versions or dependencies.

### Commit Format

Use Conventional Commits:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types are as follows: feat, fix, refactor, test, docs, chore, style

**Examples:**
```
feat(tvod): add Roku refund support
fix(auth): handle expired tokens correctly
refactor(payments): convert to service pattern
```

## Security & Configuration Tips
- Update `ssh_public_key` and `target_user` in `group_vars/all.yml` before running.
- `ansible.cfg` disables host key checking for bootstrap convenience; consider enabling it for production and preloading `~/.ssh/known_hosts`.
