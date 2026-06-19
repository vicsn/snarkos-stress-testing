# Aleo SnarkOS Stress Testing Manager

EC2 host for running snarkos-stress-testing workloads via **pueue**.

## Creating the Stress Testing Manager

### Base AMI

Built from `packer/` (Ubuntu 22, Rust, AWS CLI, git, Ansible, Terraform). Prebuilt in AWS sandbox `us-east-1` (`099720109477`). To build elsewhere, set `AWS_REGION`, run `packer init` / `packer build`, then add your account to `infrastructure/base_ami.tf`.

### SSH keys

Add your public key to `keys.pub` at the repo root. Terraform uses the auto-created `devnet-key` at the repo root; Ansible adds every key from `keys.pub` during setup.

### Provision and setup

From `infrastructure/`:

```bash
./tf_stack.sh plan
./tf_stack.sh provision --auto-approve
./tf_stack.sh setup
```

`provision` runs Terraform only. `setup` runs `ansible/setup.yml` against the instance IP (full install).

Setup rsyncs your **local** snarkos-stress-testing checkout to `/home/ubuntu/snarkos-stress-testing` (including uncommitted changes), then installs the build toolchain (Rust, sccache), **pueue/pueued** (systemd), and AWS config.

On the manager, check the daemon with `systemctl status pueued` (the CLI command is `pueue`).

Pass Terraform/Ansible options via `TF_VAR_*`, `-var`, or `-var-file` (no separate env-default/env-staging files). Useful flags: `--pueue-version`.

`setup` / `update --update-target stress-testing` push the repo from the machine running `tf_stack.sh` (requires `rsync` locally).

#### Staging

Parallel stack in workspace `staging`:

```bash
./tf_stack.sh provision --staging --auto-approve
./tf_stack.sh setup --staging
```

## Updating

Partial updates reuse `setup.yml` subsets via `update` (no Terraform apply):

```bash
./tf_stack.sh update                              # repo + pueue (default)
./tf_stack.sh update --update-target stress-testing
./tf_stack.sh update --update-target pueue --pueue-version 4.0.1
```

Full re-setup: `./tf_stack.sh setup`.

## Destroying

```bash
./tf_stack.sh destroy --force --auto-approve          # default workspace
./tf_stack.sh destroy --staging --auto-approve
```

## Running tests

See [single-region-tests/README.md](../test_suites/single-region-tests/README.md).

From your laptop, `./scripts/full_run.sh` in that test suite delegates to this manager by default (creating `stress-testing-manager-ip.txt` via `./tf_stack.sh ip` on the first run if needed). Provision and run `setup` here before delegating.

To print the manager IP (also used to populate that file):

```bash
./tf_stack.sh ip
```