---
name: snarkos-stress-testing
version: 2.0.0
description: Expert knowledge of the snarkos-stress-testing project — infrastructure provisioning, test orchestration, Ansible configuration, log analysis, and Talisker automation for SnarkOS (Aleo blockchain) stress testing on GCP and AWS.
category: tools
tags:
  - snarkos
  - aleo
  - stress-testing
  - terraform
  - ansible
  - gcp
  - aws
  - talisker
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---

# SnarkOS Stress Testing Expert

Expert knowledge of the `snarkos-stress-testing` repository — the full lifecycle framework for provisioning, configuring, running, and analyzing stress tests on SnarkOS (Aleo blockchain) node networks.

**📚 See [docs/](./docs/) for comprehensive engineer-focused documentation:**
- [docs/README.md](./docs/README.md) — Start here
- [docs/DEPLOYMENT_PATTERNS.md](./docs/DEPLOYMENT_PATTERNS.md) — 10 high-level patterns
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) — Detailed reference
- [docs/COMMON_WORKFLOWS.md](./docs/COMMON_WORKFLOWS.md) — Step-by-step procedures
- [docs/QUICK_REFERENCE.md](./docs/QUICK_REFERENCE.md) — 1-page cheat sheet

---

## Project Structure

```
snarkos-stress-testing/
├── packer/                          # Base image builder (Packer + Ansible)
├── scripts/                         # Operational utilities (S3, Slack, Talisker control)
├── log_analysis_scripts/            # Post-run log analysis (Python + Rust)
├── stress-testing-manager/          # STM automation control machine
│   └── infrastructure/              # Terraform + Ansible for STM EC2
├── single-machine-with-ssh-forwarding/  # Dev utility machine (AWS)
└── test_suites/
    ├── snarkos-p2p-tests/         # P2P network suite — GCP, validators/clients/provers
    └── snarkos-cdn-tests/          # CDN / ledger / sync suite — AWS, single machine
```

---

## Architecture

Four-layer system:

```
Talisker daemon (STM EC2, t3a.large)
  └─ watches GitHub for new SnarkOS releases
  └─ triggers test suites via JSON-RPC on :3030
      ├─ test_suites/snarkos-p2p-tests/scripts/full_run.sh  (GCP)
      │     └─ delegates over SSH to stress-testing-manager
      │     └─ enqueues pipeline via pueue: provision → setup → tests → destroy
      └─ test_suites/snarkos-cdn-tests/run_*.sh               (AWS)
            ├─ Terraform  →  provision cloud infra
            └─ Ansible    →  configure nodes + run tests
                               └─ Packer-built base images (Ubuntu 22.04)
```

---

## Test Suite: snarkos-p2p-tests (GCP)

**P2P network suite.** Provisions a full SnarkOS devnet on GCP Compute Engine so nodes can interact over P2P.

### Terraform (`test_suites/snarkos-p2p-tests/terraform/`)

| Resource | File | Description |
|---|---|---|
| `google_compute_instance.snarkos_validator` | `main.tf` | Validator nodes (count-based, round-robin zones) |
| `google_compute_instance.snarkos_client` | `main.tf` | Client nodes (count-based) |
| `google_compute_instance.snarkos_prover` | `main.tf` | Prover nodes (count-based) |
| `google_compute_instance.prometheus_server` | `main.tf` | Prometheus metrics server |
| `google_compute_instance.snarkos_builder` | `main.tf` | Optional ephemeral builder (count = `add_builder`) |
| `google_compute_instance.tx_runner` | `tx_runner.tf` | Transaction runner node |
| `module.network` | `main.tf` | VPC/subnet module (source: `./modules/gcp-snarkos-network`, conditional on `create_network`) |
| `module.fwrule` | `main.tf` | Firewall rules module (source: `./modules/firewall_rule`) |
| `module.stress_base_ami` | `main.tf` | GCP image lookup (Ubuntu 22.04 LTS) |
| `module.tx-cannon` | `main.tf` | Optional TX cannon instances |
| `google_compute_http_health_check` | `main.tf` | Health check for LB (port 3030) |
| `google_compute_target_pool` | `main.tf` | Target pool for validators |
| `google_compute_forwarding_rule.snarkos_lb` | `main.tf` | External TCP LB on port 3030 |
| `google_service_account.snarkos_sa` | `iam.tf` | GCP service account for all instances |

**Network tags on instances:**
- `module.fwrule.network_tag` — firewall tag (applied to all instances)

**Labels on instances:**
- `role` — `snarkos-validator`, `snarkos-client`, `snarkos-prover`, `prometheus-server`, `builder`
- `owner` — sanitized owner name
- `devnet` — sanitized devnet name

**Key variables** (`variables.tf`):
- `gcp_project`, `gcp_region` — GCP targeting
- `owner`, `devnet_name` — naming prefix for all resources
- `validator_instance_count`, `client_instance_count`, `prover_instance_count`
- `validator_instance_type`, `client_instance_type`, `prover_instance_type`, `tx_runner_instance_type`
- `validator_disk_size`, `client_disk_size`, `prover_disk_size`, `prometheus_disk_size`
- `create_network` (bool), `vpc` (map of region → {cidr, zones})
- `release_bucket`, `compiler_cache_bucket`, `create_compiler_cache_bucket`
- `add_builder` (bool), `builder_instance_type`
- `add_tx_cannons` (bool), `tx_cannon_instance_count`, `tx_cannon_instance_type`
- `admin_users` — list of emails granted read-only compute/logging access

**tfvars profiles:**
- `light.tfvars` — 5 validators, 0 clients, 1 prover
- `heavy.tfvars` — 40 validators (c3d-standard-60), 0 clients, 0 provers
- `prerelease.tfvars` — 40 validators, 0 clients, 1 prover (devnet_name: `prerelease-devnet`)

**Module: `modules/firewall_rule/firewall_rule.tf`**
- Manages GCP firewall rules for snarkOS ports, metrics, SSH
- Outputs `network_tag` used by all compute instances

**Module: `modules/gcp-snarkos-network/`**
- Creates VPC + regional subnets from `var.vpc` map
- Conditional: `count = var.create_network ? 1 : 0`

**Module: `modules/tx-cannon/`**
- Conditional (`count = var.add_tx_cannons ? 1 : 0`)
- Runs tx-cannon Docker container from ECR

### Ansible (`test_suites/snarkos-p2p-tests/playbooks/`)

**Main entry points:**
- `setup.yml` — full network setup (install snarkOS, configure systemd, keys, logging)
- `build_binary.yml` — build snarkOS on ephemeral builder instance
- `run_test.yml` — dispatch named test from `tests/`
- `run_utility.yml` — dispatch named utility from `utils/`

**Supporting playbooks:**
- `ips.yml` — collect + store node IPs
- `is_synced.yml` — check block height sync
- `restart_snarkos.yml` — rolling restart
- `stop_and_clean_snarkos.yml` — stop + wipe state
- `wait_network_advance.yml` — block until height advances
- `fetch_and_zip_snarkos_logs.yml` — collect + upload logs to S3
- `set_validator_facts.yml`, `set_client_facts.yml`, `set_prover_facts.yml` — role-specific facts

**Ansible roles** (`playbooks/roles/`):
- `choose_bootstrap_client` — select bootstrap client node
- `node_exporter_setup` — install Prometheus node exporter
- `process_exporter_setup` — install Prometheus process exporter
- `prometheus_setup_with_clients` — configure Prometheus with client targets
- `setup_tx_runner` — configure transaction runner
- `snarkos_build_from_git` — build snarkOS from git source
- `snarkos_build_locally` — local snarkOS build
- `snarkos_install_binary` — install pre-built binary
- `snarkos_install_s3` — install from S3 release bucket
- `snarkos_service` — configure snarkOS systemd service
- `snarkos_upload_local` — upload local binary to nodes

**Ansible host groups** (from GCP dynamic inventory via labels):
- `gcp_role_snarkos_validator` — validators
- `gcp_role_snarkos_client` — clients
- `gcp_role_snarkos_prover` — provers
- `gcp_role_prometheus_server` — prometheus server
- Intersection groups: `devnet_<devnet_name>` ∩ `owner_<owner>` for scoping

**Inventory files:**
- `inventory/dynamic_inventory.gcp.yaml` — GCP Compute Engine (keyed_groups from labels)
- `inventory/dynamic_inventory.aws_ec2.yml` — AWS EC2 (tag-based groups)
- `inventory/localhost.ini` — local connection

**Tests** (`tests/`): auto-discovered by scanning `tests/*/`
- `load_saved_transactions/` — submit pre-generated transactions (Rust tx_submitter)
- `malicious_certificates/` — malicious certificate injection
- `malicious_flood/` — flood attack simulation
- `malicious_peer_response/` — malicious peer response handling
- `malicious_resend_confirmed/` — resend confirmed transactions
- `malicious_round_attack/` — round-based attack
- `prerelease_1_halt_byzantine_majority/` — halt with byzantine majority
- `prerelease_2_reset_client_ledgers/` — reset client ledgers
- `prerelease_3_reset_validator_ledgers/` — reset validator ledgers
- `swap_ledgers/` — hot-swap ledger snapshots
- `unbond_validators/` — unbond validators from consensus

**Utilities** (`utils/`): auto-discovered by scanning `utils/*/`
- `analyze_logs/` — Python log analysis with landing stats
- `check_network_is_advancing/` — verify block height progression
- `download_flamegraph/` — download perf flamegraph SVG
- `download_logs_clients/` — download client logs
- `download_logs_provers/` — download prover logs
- `download_logs_tx_runner/` — download TX runner logs
- `download_logs_validators/` — download validator logs
- `download_prometheus_snapshot/` — download Prometheus data
- `pregenerate_transactions/` — pre-generate TX batches (deployment + execution)
- `reset_all/` — reset all nodes (stop + wipe state)
- `reset_clients/` — reset client nodes only
- `stop_all/` — stop all snarkOS services

### Master runner: `scripts/full_run.sh`
- Decomposes into `scripts/bin/*.sh` entrypoints (provision, setup, run-test, destroy)
- Enqueues pipeline via **pueue** (parallel jobs with dependency DAG)
- Delegates over SSH to stress-testing-manager when `stress-testing-manager-ip.txt` exists
- Slack notifications per job (begin/end with exit code)
- Reads vars from `playbooks/vars.yml` (generated by STM)

---

## Test Suite: snarkos-cdn-tests (AWS)

**CDN / ledger / sync suite.** Single-machine AWS EC2 client for loading a ledger or syncing from snapshots.

### Terraform (`test_suites/snarkos-cdn-tests/terraform/`)
- AWS provider, S3 backend
- `aws_instance` for sync clients
- `aws_instance.prometheus_server` — Prometheus metrics collection
- `modules/stress_base_ami/` — latest `stress-test-base-*` AMI lookup
- `modules/security_group/` — AWS security group (SSH, snarkOS ports)
- IAM: admin user, EC2 role, S3 policy, instance profile

### Key scripts:
- `run_client_sync_test.sh` — full orchestration
- `run_load_ledger_test.sh` — ledger load benchmark
- `check_sync.sh` — poll + persist sync state to JSON
- `watch_load_ledger_stats.sh` — SSH poll for benchmark results

### Snapshot URL files (per network):
- `playbooks/snapshot_urls_mainnet.txt`
- `playbooks/snapshot_urls_testnet.txt`
- `playbooks/snapshot_urls_canary.txt`

---

## Stress Testing Manager (STM)

**Central automation machine.** EC2 t3a.large, 100GB.

### Infrastructure (`stress-testing-manager/infrastructure/`)
- `tf_stack.sh` — master control: `provision | setup | destroy`
- `main.tf` — EC2 instance
- `ec2_profile.tf` — IAM role + PowerUserAccess
- `network.tf` — security groups (SSH:22, API:3030, ICMP)

### Ansible (`stress-testing-manager/infrastructure/ansible/`)
- `setup.yml` — clones repos, installs Rust, compiles Talisker, starts systemd service
- Templates: `talisker.service`, `ansible_vars.yml.j2`, `aws.config`

### Talisker
- Daemon watching GitHub for new SnarkOS tags/branches
- Triggers test suites automatically on release
- JSON-RPC API on port 3030
- Controlled via `scripts/talisker_control.sh`

---

## Base Image (Packer)

**Template:** `packer/stress-test-base.pkr.hcl` (GCP only; no AWS/ARM variants)

**Output image:** family `stress-test-base` in project `protocol-development-sandbox`,
built on Ubuntu 22.04 (`ubuntu-2204-lts`), 50 GB `pd-ssd`, `c3d-standard-8` builder in
`us-central1-b`. Terraform's `data.google_compute_image.stress_base` (in
`modules/stress_base_ami/`) picks the latest image in the family automatically.

Installed by `packer/playbooks/dependencies.yml`:
- GitHub CLI (`gh`)
- Docker (`docker.io`) + Docker Compose v2.24.6
- Prometheus Node Exporter + Process Exporter (via shared roles in
  `test_suites/snarkos-p2p-tests/playbooks/roles/`)
- Google Cloud Ops Agent (with default `packer/playbooks/files/ops_agent_config.yaml`;
  runtime labels re-rendered by the `google_ops_agent_setup` Ansible role at setup time)
- Google Cloud CLI (`gcloud`)
- Python 3 + pip3
- `libclang-dev`, `zip`, `unzip`, `acl`
- Purges `unattended-upgrades` (blocks apt during provisioning)

**Not baked in:** snarkOS itself — compiled separately, cached in GCS
(`provable-binaries-releases`), and installed at runtime by `setup.yml` →
`snarkos_install_s3` role.

**Build:** see [Common Workflows → Build the Packer base image](#build-the-packer-base-image),
or run `.agents/skills/snarkos-stress-testing/resources/build-packer-image.sh` from the
repo root.

---

## Shared S3 Buckets

| Bucket | Purpose |
|---|---|
| `provable-binaries-releases` | SnarkOS binaries built by Talisker |
| `provable-logs-results` | Test logs + results uploaded post-run |
| `aleo-snapshots` | Ledger checkpoints for sync tests |
| `snarkos-compiler-cache` | sccache build cache (GCS/S3) |
| `ephnet-terraform-state-bucket-eq` | Terraform remote state |

---

## Log Analysis (`log_analysis_scripts/`)

**Python scripts** (run locally post-test):
1. `analysis_01_prepare_logfile.py` — preprocess raw snarkOS logs
2. `analysis_02_sync_profiling.py` — sync speed visualization
3. `analysis_02_val_consensus_profiling.py` — consensus round/block time plots
4. `analysis_02_val_tx_propagation_analysis.py` — TX propagation stats
5. `analysis_02_peermessage_profiling.py` — peer message timing
6. `analysis_02_transmission_consensus_queues.py` — mempool/queue analysis
7. `analysis_flamegraph_svg.py` — flamegraph SVG parser

**Rust timing analyzer** (`log_analysis_scripts/timing_analysis/`):
- CLI tool (clap), reads JSON → SVG charts (plotters)
- Entry: `src/main.rs`, data: `src/data.rs`, viz: `src/visualization.rs`

---

## Operational Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `talisker_control.sh` | JSON-RPC CLI for Talisker |
| `notify_slack.sh` | Slack notifications (threads, colors, mentions) |
| `store_latest_snapshot.py` | Stream HTTP snapshot → S3 multipart |
| `checkpoint_uploader.sh` | Periodically zip + upload ledger checkpoints |
| `cleanup_old_releases.sh` | Delete S3 objects older than 20 days |
| `list_running_ec2s.sh` | List running EC2s across US regions |
| `fetch_git_authors.sh` | Authors between two branches/tags |
| `generate_snapshots.sh` | Trigger snarkOS DB backup at block milestones |
| `attach_aleo_snapshots_role.sh` | Attach IAM role to EC2 for S3 access |

---

## Common Workflows

### Add a new compute instance type
1. Add resource in `test_suites/snarkos-p2p-tests/terraform/main.tf`
2. Add network tags: `[module.fwrule.network_tag]`
3. Add labels: `role` (e.g. `snarkos-<role>`), `owner`, `devnet`
4. Add service account, boot disk, OS login metadata (follow existing pattern)
5. Add variable for count/type/disk_size in `variables.tf`
6. Update Ansible inventory keyed_groups if needed

### Add a new test
1. Create `test_suites/snarkos-p2p-tests/tests/<test-name>/run_test.yml`
2. Add optional `pre-test.sh` / `check.sh` / `post-test.sh` hooks
3. Tests are auto-discovered from `tests/*/` — no registration needed

### Add a new utility
1. Create `test_suites/snarkos-p2p-tests/utils/<util-name>/run_utility.yml`
2. Add optional `pre-utility.sh` / `check.sh` / `post-utility.sh` hooks
3. Utilities are auto-discovered from `utils/*/` — no registration needed

### Rename a Terraform module
- Update module block name + source path in `main.tf`
- Update all `module.<name>.*` references across all `.tf` files
- Rename the directory under `modules/`
- Rename the `.tf` file inside the module directory

### Build the Packer base image

Rebuilds the `stress-test-base` GCP image family (~14 minutes). The Terraform data
source picks the latest image in the family automatically — no `image_family` /
`image_project` change needed after a rebuild.

**Turnkey (recommended)** — script handles preflight, subnet workaround, log capture,
and post-build image verification:

```bash
.agents/skills/snarkos-stress-testing/resources/build-packer-image.sh
```

**Manual:**

```bash
cd packer
packer init stress-test-base.pkr.hcl
packer build \
  -var 'subnetwork=subnet-03-us-central1' \
  stress-test-base.pkr.hcl
```

The `subnetwork` var is **required** — `vpc-protocol-development-sandbox` runs in
custom-mode subnet mode, so packer must specify a subnet. The template default is
empty and would fail at instance creation with:

```
Error 400: Invalid value for field 'resource.networkInterfaces[0].subnetwork': ''.
Network interface must specify a subnet if the network resource is in custom subnet mode.
```

**Prerequisites:**
- `brew install hashicorp/tap/packer`
- `pip install ansible` (packer uses the Ansible provisioner)
- `gcloud auth application-default login` (application default credentials — the
  googlecompute plugin uses ADC, not the gcloud user login)

**Env-var overrides** (both the script and the manual form) — see
`resources/build-packer-image.sh` header for the full list: `NETWORK`, `SUBNETWORK`,
`GCP_PROJECT`, `GCP_ZONE`, `PACKER_LOG_DIR`.

**Verify the new image after build:**

```bash
gcloud compute images describe-from-family stress-test-base \
  --project=protocol-development-sandbox \
  --format='value(name,creationTimestamp)'
```

### Provision + run a test manually
```bash
cd test_suites/snarkos-p2p-tests

# Full pipeline (provision + setup + test + destroy via pueue)
scripts/full_run.sh --mode=light --tests=swap_ledgers

# Individual steps
scripts/bin/provision.sh --mode=light
scripts/bin/setup.sh
scripts/bin/run-test.sh --test=swap_ledgers
scripts/bin/destroy.sh
```

### Control Talisker remotely
```bash
scripts/talisker_control.sh status
scripts/talisker_control.sh trigger --branch main
scripts/talisker_control.sh stop
```

---

## Key Conventions

- **Naming:** all GCP resources prefixed `${var.owner}-${var.devnet_name}-<role>`
- **Labels** on every instance: `role` (e.g. `snarkos-validator`), `owner` (sanitized), `devnet` (sanitized)
- **Network tags:** `module.fwrule.network_tag` only (no separate role tags)
- **Zone distribution:** `local.zones[count.index % length(local.zones)]` for round-robin
- **OS Login:** `metadata = { enable-oslogin = "TRUE" }` on all GCP instances
- **Service account:** all GCP instances use `google_service_account.snarkos_sa` with `cloud-platform` scope
- **Firewall module:** `module "fwrule"` with source `./modules/firewall_rule`
- **Network module:** `module "network"` with source `./modules/gcp-snarkos-network` (conditional on `create_network`)
- **Dynamic inventory:** GCP uses `inventory/dynamic_inventory.gcp.yaml` (`.yaml` extension); AWS uses `inventory/dynamic_inventory.aws_ec2.yml`
- **Ansible targeting:** `devnet_<name>:&owner_<owner>` intersection groups for scoping
- **vars.yml:** generated by STM Ansible from `ansible_vars.yml.j2`; consumed by all playbooks
- **Test/utility discovery:** auto-discovered by scanning `tests/*/` and `utils/*/` directories

---

## Technology Stack

| Layer | Tools |
|---|---|
| IaC | Terraform (GCP `hashicorp/google` ≥7.32.0, AWS) |
| Config Mgmt | Ansible (`amazon.aws`, `ansible.posix`, `community.general`) |
| Image Build | HashiCorp Packer (amazon-ebs, Ansible provisioner) |
| Cloud — GCP | Compute Engine, Cloud LB, Firewall, IAM, OS Login, GCS |
| Cloud — AWS | EC2, ELB, S3, IAM, CloudWatch Logs |
| Monitoring | Grafana Cloud, Prometheus, Node/Process Exporter, Elastic stack |
| Languages | Bash, Python 3.12+, Rust (2021) |
| Blockchain | SnarkOS (Aleo node), snarkVM, tx-cannon (Docker/ECR), Talisker |
| CI | GitHub Actions (ansible-lint + shellcheck) |
| Pre-commit | ansible-lint, shellcheck |
