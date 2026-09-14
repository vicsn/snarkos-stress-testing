# snarkos-p2p-tests

P2P network suite: provisions validators, clients, and provers that interact over P2P.

## Prerequisites

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
    - `brew tap hashicorp/tap`
    - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - `brew install ansible`
- [Install sccache](https://github.com/mozilla/sccache)
    - `brew install sccache`
- [Install gcloud CLI](https://cloud.google.com/sdk/docs/install)
    - `brew install --cask google-cloud-sdk`
- Make sure you have access to github.com/ProvableHQ/snarkos-staging
- You can build binaries with github actions or use the local cross-compilation method and use GCS for release distribution. To use the local build method, run these steps first on Mac:
    - `brew tap SergioBenitez/osxct`
    - `brew install x86_64-unknown-linux-gnu`
    - `brew install openssl@3` (this should create a folder `/opt/homebrew/Cellar/openssl@3/3.4.0`. In case newer versions are released, update the version in the file `playbooks/roles/snarkos_build_locally/defaults/main.yml` and try it out.)
    - `rustup target add x86_64-unknown-linux-gnu`
- [Install pre-commit](https://pre-commit.com/#installation). It can be installed with `pip install pre-commit`.
    - Run `cd test_suites/snarkos-p2p-tests && pre-commit install`. Now you have an Ansible lint commit hook.
- [Install pueue](https://github.com/Nukesor/pueue) and start the daemon before running jobs:
    - `cargo install pueue` (or `brew install pueue` if available)
    - `pueued -d` (runs in the background; use `pueue status` to confirm)
    - Set `pause_on_failure: true` in the pueue daemon config so a failing job pauses the group instead of continuing.

## Networking

This suite reuses both the stress-testing-manager's VPC **and its subnet** via `terraform_remote_state`. SRT does not create any network resources — no VPC, no subnet — it consumes STM's `vpc_id`, `subnet_self_links`, and `subnet_cidrs` outputs directly.

`var.vpc` now only supplies **zone lists for instance round-robin placement**. The region key must match a region where STM has provisioned a subnet; a mismatch fails at plan time with a map-lookup error on `subnet_self_links[region]`.

```hcl
vpc = {
  "us-central1" = {
    zones = ["us-central1-b", "us-central1-c", "us-central1-f"]
  }
}
```

The STM lookup follows the current SRT workspace. To target a non-default STM workspace (e.g. `staging`), select the matching SRT workspace before apply:

```bash
terraform workspace select staging
```

If the workspace does not exist locally, create it:

```bash
terraform workspace new staging
```

**Precondition:** The GCS backend must be enabled in `terraform/provider.tf` and `terraform init` run before applying. The STM must be provisioned in the matching workspace, and its `vpc_id`, `subnet_self_links`, and `subnet_cidrs` outputs must be available.

**Migration note:** Prior versions of SRT created a separate `10.40.0.0/16` subnet inside the STM VPC. If you have an existing SRT deployment, run `terraform destroy` under the old configuration **before** applying this change — otherwise `terraform apply` will force-replace every instance to move it onto the STM subnet.

## Configuration

- Copy `playbooks/vars.example.yml` to `playbooks/vars.yml` and fill in the required fields.
- Add your SSH public key + source IP to `stress-testing-manager/infrastructure/external_ssh_users.auto.tfvars` and run `stress-testing-manager/infrastructure/tf_stack.sh provision`. Terraform regenerates the repo-root `keys.pub` file that Ansible installs on every managed host via the shared `shared_ssh_keys` role. The ephemeral `devnet-key` (repo root, auto-created on provision) is used by Terraform/Ansible alongside those keys.

### SSH access to SRT instances

SRT-managed GCE instances (validators, clients, provers, tx_runner, prometheus,
tx-cannon, builder) do NOT use OS Login. Instead, `local.ssh_metadata` in
`terraform/locals.tf` injects the shared `devnet-key.pub` (repo root, generated
by `scripts/ensure_devnet_key.sh` if absent) via GCE `ssh-keys` metadata for
the `ubuntu` account.

Optional: set `TF_VAR_ssh_public_key` (or `var.ssh_public_key` in tfvars) to
layer an additional personal key alongside devnet-key.pub. `scripts/lib/common.sh`
auto-populates this from `~/.ssh/google_compute_engine.pub`, `~/.ssh/id_ed25519.pub`,
or `~/.ssh/id_rsa.pub` (in that order). Leave it empty to skip — devnet-key.pub
alone still authorizes access.

Ansible connects as `ansible_user=ubuntu` with
`ansible_ssh_private_key_file=/home/ubuntu/snarkos-stress-testing/devnet-key`
(absolute path resolved on the STM or builder host that runs `ansible-playbook`).

**Local runs (`STM_LOCAL=1`) require an override:** the absolute path does
not exist on macOS. Pass `--extra-vars ansible_ssh_private_key_file=<repo>/devnet-key`
(or symlink at that path) when invoking Ansible from the laptop.

### Ansible inventory

The dynamic inventory (`inventory/dynamic_inventory.gcp.yaml`) uses
`google.cloud.gcp_compute` to discover GCE instances. It uses the instance's
**private IP** for both the Ansible hostname (`hostnames: [private_ip]`) and the
SSH target (`ansible_host: networkInterfaces[0].networkIP`).

Because the inventory targets private IPs, Ansible must run from a host inside
the shared VPC (the stress-testing-manager, the ephemeral builder, or a VM in
the same subnet). Laptop runs (`STM_LOCAL=1`) cannot reach the private IPs
directly — use the default manager delegation instead, or SSH-tunnel from the STM.

GCE labels create dynamic groups. Example filters and groups:

- `devnet_snarkos_p2p_tests` — all SRT hosts (validators, clients, provers, tx_runner, tx-cannon)
- `devnet_stress_testing_manager` — the STM host
- `role_snarkos_validator`, `role_snarkos_client`, `role_snarkos_prover`
- `role_snarkos_builder`, `role_tx_runner`, `role_tx_cannon`
- `owner_<owner>` — grouped by `owner` label

See the [Troubleshooting](#troubleshooting) section below for inventory inspection commands.

### GCP Project

Default project: `protocol-development-sandbox` (set in `terraform/default.auto.tfvars` and `terraform/variables.tf`).

Override at plan/apply time:
```bash
terraform plan -var="gcp_project=my-other-project" -var-file=light.tfvars
```

### Authentication

```bash
# 1. Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# 2. Set default project
gcloud config set project protocol-development-sandbox
```

### Remote State (optional)

State is local by default. To enable shared GCS remote state:

```bash
# 1. Bootstrap the state bucket + service account (one-time)
cd terraform_init
terraform init && terraform apply

# 2. Uncomment the GCS backend in terraform/provider.tf:
#   backend "gcs" {
#     bucket = "tfstate-snarkos-stress-testing"
#     prefix = "snarkos-p2p-tests"
#   }

# 3. Migrate existing local state
cd ../terraform
terraform init -migrate-state
```

Resources created by `terraform_init/`:

| Resource | Name |
|----------|------|
| GCS bucket | `tfstate-snarkos-stress-testing` |
| Service account | `snarkos-stress-testing@protocol-development-sandbox.iam.gserviceaccount.com` |

See [`terraform_init/README.md`](./terraform_init/README.md) for details.

## Running your devnet
#### TODO: define why one might change the value of DEVNET_NAME
#### TODO: define when a custom value would be used

Every run needs a **`RUN_ID`**: it ties together GCS log prefixes, Slack threads, and pueue job snapshots. Export it once at the start of a session and reuse it for every job in that run:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
```

The devnet name can be set via the `DEVNET_NAME` env variable (for example `DEVNET_NAME="my_net" export RUN_ID=...` before enqueuing).
By default for local test runs it is `snarkos-p2p-tests` and for automatic pre-release tests it is `prerelease-devnet`.
Alternatively the TF var `devnet_name` can be edited to change it too.

Every phase entrypoint (`full_run.sh` and each `scripts/bin/*.sh` except the read-only `fetch-job-log.sh`) runs the same preamble: parse args, **delegate to the Stress Testing Manager** (`lib/stm.sh`), then **self-enqueue in pueue** (`lib/pueue.sh`), then do the work. Whatever you type on your laptop is what runs on the manager. `PUEUE_DISABLED=1` runs jobs inline instead of queueing them, which also makes a delegated command block until the remote job is done.


### Full run

`full_run.sh` wires `provision → setup → {N test jobs} → destroy`:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
./scripts/full_run.sh --mode=light --tests=prerelease
pueue status
```

Use `--tests=prerelease` or `--tests=t1,t2` to narrow the test list. A failed provision cancels the rest of the chain.

#### Stress Testing Manager delegation

Everything runs on the shared [Stress Testing Manager](../../stress-testing-manager/README.md), because the Ansible inventory targets private IPs inside the shared VPC. `lib/stm.sh` implements this once and every entrypoint calls it — there is no separate "delegated" command to remember.

The manager is resolved from the repo-root file `stress-testing-manager-ip.txt` (gitignored, written by the STM `terraform apply`). If it is missing, delegation fails and tells you to run `stress-testing-manager/infrastructure/tf_stack.sh provision` (`tf_stack.sh ip` prints the same IP). The manager must be provisioned and set up first (`tf_stack.sh provision` + `setup`; see the manager README). To point at a different manager, replace the file contents.

Delegation is skipped in exactly two cases: this host **is** the manager (GCE metadata `role=stress-testing-manager`), or `STM_LOCAL=1` is set.

Forwarded into the remote command when set: `RUN_ID`, Slack/pueue settings, `DEVNET_NAME`, `OWNER`, and the bucket/region vars. You can `export SLACK_TOKEN` and `SLACK_CHANNEL_ID` locally to override what the manager resolves for itself; `NOTIFY_SLACK_DISABLED=1` turns notifications off.

To run on your own machine instead (needs pueue or `PUEUE_DISABLED=1`, plus VPC access for Ansible):

```bash
STM_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=prerelease
```

### Individual jobs

Once `RUN_ID` is exported, pueue snapshots it at enqueue time — every job in the run shares the same GCS prefix. Invoke a bin script directly; it delegates, then enqueues itself:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
./scripts/bin/provision.sh --mode=light
./scripts/bin/setup.sh
./scripts/bin/run-test.sh --test=prerelease_foo
./scripts/bin/run-utility.sh --utility=analyze_logs
./scripts/bin/destroy.sh
./scripts/lib/stm.sh pueue status
```

Run inline (no pueue): `PUEUE_DISABLED=1 ./scripts/bin/run-test.sh --test=foo`. Inline is what you want when driving the phases yourself, since each command then returns only once the remote job has finished.

This is also how you re-run one test against a devnet you keep alive: `provision.sh` and `setup.sh` once, then `run-test.sh` as many times as you like, then `destroy.sh`. Use `run-utility.sh --utility=reset_all` between iterations for a clean ledger. `full_run.sh` always ends with `destroy`, so it cannot hold a devnet open.

#### Inspecting a run

`lib/stm.sh` doubles as the one-off escape hatch — run it directly for a command on the manager, or a shell there:

```bash
./scripts/lib/stm.sh pueue status
./scripts/lib/stm.sh                 # interactive shell in this suite's directory
```

For a job's output, `fetch-job-log.sh` pulls it into a temp file on your machine and prints the path, which beats scrolling a long log over SSH:

```bash
./scripts/bin/fetch-job-log.sh --job=7        # task id from `pueue status`
less "$(./scripts/bin/fetch-job-log.sh --job=7)"
```

### Slack notifications

Optional, best-effort job status. Credentials are resolved automatically when possible:

| Source | Used when |
|--------|-----------|
| `SLACK_TOKEN` / `SLACK_CHANNEL_ID` already exported | Always (highest priority) |
| `~/.config/snarkos-stress-testing/slack_env.sh` | Manager after `tf_stack.sh setup` with `vars.yml` |
| `test_suites/snarkos-p2p-tests/playbooks/vars.yml` | Laptop delegation (`full_run.sh`) and local runs |

Pueue snapshots them into each task at enqueue time. Disable with `NOTIFY_SLACK_DISABLED=1`. Notifications never fail a job.


## SnarkOS - artifact and build sources
* refer to `./playbooks/roles/check_and_setup_snarkos/tasks/main.yml`

  > - local pre-built version
  >     set_fact: use_local_pre_build
  >       {{
  >         (snarkos_pre_build_location is defined and
  >           snarkos_pre_build_location | length > 0)
  >       }}
  > - GCS pre-built version
  >     set_fact: use_s3_pre_build
  >       {{
  >         (snarkos_pre_build_location is undefined) and
  >         (gcs_bucket is defined and gcs_bucket | length > 0) and
  >         (use_snarkos_pre_build_gcs is defined and use_snarkos_pre_build_gcs|bool)
  >       }}
  > - local build
  >     set_fact: use_local_build
  >       {{
  >         (snarkos_pre_build_location is undefined) and
  >         (use_snarkos_pre_build_gcs is undefined or not use_snarkos_pre_build_gcs|bool) and
  >         (snarkos_repo is defined and snarkos_repo | length > 0) and
  >         (snarkos_git_commit_local_build is defined and snarkos_git_commit_local_build | length > 0)
  >       }}
  > - GitHub build
  >     set_fact: use_github_build
  >       {{
  >         (snarkos_pre_build_location is undefined) and
  >         (use_snarkos_pre_build_gcs is undefined or not use_snarkos_pre_build_gcs|bool) and
  >         (snarkos_binary_tag is defined and snarkos_binary_tag | length > 0)
  >       }}
  > - remote build
  >     set_fact: use_remote_build
  >       {{
  >         (snarkos_pre_build_location is undefined) and
  >         (use_snarkos_pre_build_gcs is undefined or not use_snarkos_pre_build_gcs|bool) and
  >         (snarkos_git_hash is defined and snarkos_git_hash | length > 0) and
  >         (snarkos_repo is defined and snarkos_repo | length > 0)
  >       }}

## Monitoring

- [Grafana](https://aleostresstest.grafana.net/d/snarkos-p2p-tests/snarkos-p2p-tests?from=now-3h&to=now&refresh=) can be used with `devnet_name=snarkos-p2p-tests`. If you change your `devnet_name`, you'll need to customize and import `grafana.json` to a new dashboard.
- Access nodes via `gcloud compute ssh`:
```bash
gcloud compute ssh <owner>-<devnet_name>-validator-0 --zone=us-central1-a
```
- Stream logs with lnav:
```bash
gcloud compute ssh <instance> --zone=us-central1-a -- \
  "tail -f /tmp/snarkos.log" | lnav
```
- Google Cloud Ops Agent collects metrics and logs to Cloud Monitoring/Logging.

## Running multiple devnets in parallel

Should be possible by changing the `devnet_name` in `playbooks/vars.yml`. Note that you will hit the quota limits pretty soon. See for upgrading [these scripts](https://github.com/ProvableHQ/infrastructure/tree/main/misc-scripts).

## Changing the region

Should be possible, but there may be stuff you need to update:
- Default region is `us-central1`
- Set region/zones in `inventory/dynamic_inventory.gcp.yaml` and `terraform/provider.tf`
    - Zones can be left unset in `dynamic_inventory.gcp.yaml` to scan all zones but will be significantly slower
- Pushing a base image to the new region using [packer](../../special_devnets/packer/)
- Creating a new Grafana instance

And there may also be stuff you want to keep the same, e.g. the Terraform GCS state bucket.

## Usage of keymaterial

The transaction cannons use hardcoded private keys, made possible by snarkos
nodes using the fixed `DEVELOPMENT_MODE_RNG_SEED`.

## Log files and analysis

With local runs the log files are downloaded in `log_files`.
With remote runs the log files are zipped and uploaded to GCS (in slack the location is pointed out).

Ensure the same `RUN_ID` from the test run is still exported before enqueuing log jobs.

Log files from automated runs are uploaded to the GCS results bucket (the Slack notification includes the path).
You can download and unzip the log files from an auto-run in `log_files` too to use the utilities on them.

The log files are gzipped, so this action will make them in plain text format:

```
gunzip log_files/*.log.gz
```

For getting the errors out of them this can be done:

```
grep -Hn ERROR log_files/* > tmp.errors.txt
```

Run the stat analyser on downloaded logs (reuse the run's `RUN_ID`):

```bash
./scripts/bin/run-utility.sh --utility=analyze_logs
```

Stats are written to `log_files/landing_stats.json`.

Download individual log sets:

```bash
./scripts/bin/run-utility.sh --utility=download_logs_clients
./scripts/bin/run-utility.sh --utility=download_logs_provers
./scripts/bin/run-utility.sh --utility=download_logs_tx_runner
./scripts/bin/run-utility.sh --utility=download_logs_validators
```

Download all logs, analyze, and upload to GCS:

```bash
./scripts/bin/collect-logs.sh
```

## Destroying the stress testing infrastructure locally

With `full_run.sh`, cleanup is handled on the manager via the normal `destroy` job at the end of the pipeline.

When you drive the phases yourself (or run with `STM_LOCAL=1`), destroy manually when ready (with the run's `RUN_ID` still exported):

```bash
./scripts/bin/destroy.sh
```

## Troubleshooting

### `Error acquiring the state lock`

A run killed mid-apply leaves the GCS backend locked. Release it with:

```bash
./scripts/lib/unlock-state.sh
```

It resolves the lock object's generation number (the value the GCS backend
wants — the `ID:` UUID in terraform's error is rejected with `Lock ID should be
numerical value`), shows who holds the lock and how long they have held it, and
refuses while terraform is still running. It delegates to the manager like
every other entrypoint, so it uses the terraform working directory that is
already initialised against this backend; `STM_LOCAL=1` runs it locally when
SSH is down. Add `--force` for non-interactive use.

A local run may hit `Backend configuration changed` if your checkout's
`terraform/.terraform/` was last initialised against a different backend. Fix
it with `terraform -chdir=terraform init -reconfigure` (use `-migrate-state`
instead only if you have local state worth moving).

### Ansible inventory

The dynamic inventory uses private IPs. Run inventory commands from the
stress-testing-manager (or another host inside the shared VPC), not your laptop.

Open a shell on the manager:

```bash
./scripts/lib/stm.sh
```

Move to the playbooks directory (where `ansible.cfg` points at the GCP inventory):

```bash
cd playbooks
```

List hosts by devnet:

```bash
ansible-inventory --graph devnet_snarkos_p2p_tests
ansible-inventory --graph devnet_stress_testing_manager
```

List hosts by role:

```bash
ansible-inventory --graph role_snarkos_prover
ansible-inventory --graph role_snarkos_builder
ansible-inventory --graph role_tx_runner
```

Test connectivity to every SRT host:

```bash
ansible -m ping devnet_snarkos_p2p_tests
```

If a host is missing from the graph, verify:

- The instance status is `RUNNING`. The inventory filter drops other states.
- The instance has the correct `devnet` and `role` labels applied by Terraform.
- Your gcloud application-default credentials can list instances in `protocol-development-sandbox`.
- The Ansible collection `google.cloud >= 1.13.0` is installed.

If ping fails but the host appears in the graph, verify:

- The SSH key `/home/ubuntu/snarkos-stress-testing/devnet-key` exists on the host that runs Ansible.
- Firewall rules allow SSH from the source subnet on port 22.
- The target instance is in the same VPC (`stress-testing-manager-vpc`) as the source host.
