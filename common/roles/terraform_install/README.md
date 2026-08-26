# terraform_install

Installs the Terraform CLI on Ubuntu via HashiCorp's official APT repository
(`apt.releases.hashicorp.com`).

## What this role does

1. Fetches HashiCorp's ASCII GPG key from `https://apt.releases.hashicorp.com/gpg`,
   dearmors it, and installs it at
   `/usr/share/keyrings/hashicorp-archive-keyring.gpg` (idempotent — the shell task
   has a `creates:` guard, so a second run skips the re-fetch).
2. Adds the HashiCorp APT repository at
   `/etc/apt/sources.list.d/hashicorp.list`, using the `signed-by=`
   sources.list attribute (not the deprecated `apt-key add`).
3. Installs the `terraform` package. Honours an optional `terraform_version`
   pin.

## Requirements

- Ubuntu (any codename resolved by `ansible_distribution_release` — tested on
  jammy 22.04).
- Invoking play must run `gather_facts: true` so
  `ansible_distribution_release` is populated.
- Sudo / root privilege (all tasks run as root — `become: true` on the play).
- Host binaries `wget` and `gpg` (from the `gnupg` apt package) must be present
  before this role runs. When invoked from
  `stress-testing-manager/infrastructure/ansible/setup.yml`, the play's
  earlier apt-install task (gated by the same `setup_full` variable) already
  installs both — see setup.yml lines 108 (`gnupg`) and 123 (`wget`). Callers
  outside that context must guarantee these binaries themselves.

## Role variables

Defined in `defaults/main.yml`:

| Variable | Default | Description |
|---|---|---|
| `terraform_version` | `""` (latest) | APT version string when pinning is desired (e.g. `1.9.5-1`). Discover values with `apt-cache madison terraform`. |

## Example usage

```yaml
- name: Install Terraform CLI
  ansible.builtin.include_role:
    name: terraform_install

# With version pinning:
- name: Install Terraform 1.9.5
  ansible.builtin.include_role:
    name: terraform_install
  vars:
    terraform_version: "1.9.5-1"

# On an ARM host:
- name: Install Terraform CLI on ARM
  ansible.builtin.include_role:
    name: terraform_install
```

## Where this role is invoked

- `stress-testing-manager/infrastructure/ansible/setup.yml` — under the
  `setup_full` target gate, alongside Rust and sccache bootstrap.

## References

- HashiCorp Terraform install (Linux): <https://developer.hashicorp.com/terraform/install#linux>
