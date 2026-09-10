# Architecture Reference

Detailed breakdown of infrastructure layers, modules, and components.

---

## Quick Facts

| Metric | Value |
|--------|-------|
| **Architecture** | Three-tier (test suites → STM automation → operational utilities) |
| **Primary Language** | HCL (Terraform) + YAML (Ansible) + Bash |
| **Test Scenarios** | 12 (ledger ops, malicious behavior, prerelease scenarios) |
| **Terraform Modules** | 3 shared (stress_base_ami, security_group, tx-cannon) |
| **Ansible Roles** | 14 (snarkos_* operations + component_setup tools) |
| **Shell Scripts** | 8 executables + 3 libraries + full_run.sh orchestrator |
| **Analysis Tools** | 7 Python + 1 Rust-based timing analyzer |

---

## Three-Tier Architecture

### Tier 1: Test Suites (`test_suites/`)

**Location:** `test_suites/snarkos-p2p-tests/` (P2P network) + `test_suites/snarkos-cdn-tests/` (CDN / ledger / sync)

**Components:**
- **Terraform** (624 lines total) — Infrastructure provisioning
- **Ansible** (20 playbooks + 14 roles) — Node setup + SnarkOS binary deployment
- **Tests** (12 scenarios) — Pluggable test definitions with optional pre/post hooks
- **Utilities** (14 helpers) — TX generation, state reset, log collection
- **Scripts** (8 bin + 3 libs) — CLI orchestration + pueue job queue integration

**Lifecycle:**
1. Provision infrastructure via Terraform
2. Configure nodes via Ansible setup.yml
3. Run tests via pueue job queue
4. Collect logs + analyze results

---

### Tier 2: Stress-Testing-Manager (STM) (`stress-testing-manager/`)

**Purpose:** Central automation daemon (long-running, independent lifecycle)

**Components:**
- **Separate EC2 instance** (t3a.large, 100GB EBS)
- **Terraform** — STM infrastructure (distinct state from test suites)
- **Ansible** — Talisker daemon + Pueue job queue
- **Packer** — Separate base image for STM
- **Talisker daemon** — Webhook listener, job enqueuer, result collector

**Lifecycle:**
1. Provisioned once, run for months
2. Polls GitHub for new SnarkOS releases
3. Enqueues test suite runs via pueue
4. Collects results + notifies Slack

---

### Tier 3: Operations & Analysis

**Root-level utilities:**
- `scripts/talisker_control.sh` — STM daemon control (status/trigger/stop)
- `scripts/` — Snapshot management, EC2 listing, Slack notifications
- `log_analysis_scripts/` — Post-run analysis tools (Python + Rust)
- `docs/` — Engineering documentation (5 files, 2,282 lines)

---

## Directory Structure

For complete file tree, see [`DIRECTORY_MAP.txt`](../DIRECTORY_MAP.txt) (278 lines, 16KB).

Quick reference:

```
snarkos-stress-testing/
├── docs/                               # Engineering documentation
│   ├── README.md                       # Entry point
│   ├── QUICK_REFERENCE.md              # 1-page cheat sheet
│   ├── DEPLOYMENT_PATTERNS.md          # 10 design patterns
│   ├── ARCHITECTURE.md                 # This file
│   └── COMMON_WORKFLOWS.md             # Step-by-step procedures
│
├── test_suites/                        # Two independent test suites
│   ├── snarkos-p2p-tests/            # GCP P2P network suite
│   │   ├── terraform/                  # Main validator/client network
│   │   ├── terraform_tx_cannon/        # Separate TX runner stack
│   │   ├── playbooks/                  # Ansible orchestration (20 files)
│   │   ├── tests/                      # 12 pluggable test definitions
│   │   ├── utils/                      # 14 utility helpers (pre/post hooks)
│   │   └── scripts/                    # CLI orchestration (8 bin + 3 libs)
│   │
│   └── snarkos-cdn-tests/             # AWS CDN / ledger / sync suite
│       ├── terraform/                  # EC2 instances, ELB
│       ├── playbooks/                  # Ansible orchestration
│       └── scripts/                    # Sync benchmarking
│
├── stress-testing-manager/             # Central automation (long-running)
│   ├── infrastructure/                 # Terraform + Ansible for STM
│   └── packer/                         # Separate base image
│
├── packer/                             # Test suite base image builder
│   ├── stress-test-base.json.pkr.hcl   # x86_64 AMI
│   └── stress-test-base-arm.json.pkr.hcl # ARM64 AMI
│
├── scripts/                            # Root-level operational utilities
│   └── talisker_control.sh             # STM daemon control
│
├── log_analysis_scripts/               # Post-run analysis tools
│   ├── analysis_*.py                   # 7 Python scripts
│   └── timing_analysis/                # Rust CLI tool
│
└── common/                             # Shared resources
    └── roles/shared_ssh_keys/          # Referenced by both test suites
```

---

## GCP snarkos-p2p-tests (P2P Network Suite)

### Dual Terraform Stacks (Non-Obvious Pattern)

Test suite has **two separate Terraform roots** for different infrastructure:

#### Stack 1: Main Network (`terraform/`)

```hcl
# 624 lines total: main.tf, variables.tf, outputs.tf, 3 iam*.tf files

resource "google_compute_instance" "snarkos_validator" {
  count = var.validator_instance_count  # e.g., 3-10 validators
  name = "${var.owner}-${var.devnet_name}-validator-${count.index}"
  zone = local.zones[count.index % length(local.zones)]
  machine_type = var.validator_instance_type  # e.g., n2-highmem-8
  
  # Network tags: [module.fwrule.network_tag, "validator"]
  # Labels: {role: validator, owner: sanitized, devnet: sanitized}
  # Service account: google_service_account.snarkos_sa
}

# Similar for clients, provers, TX runner
```

**Modules:**
- `modules/stress_base_ami/` — Ubuntu 22.04 LTS image lookup (`data.google_compute_image`)
- `modules/gcp-snarkos-network/` — VPC + subnets + optional Ops Agent SA
- `modules/firewall_rule/` — GCP firewall rules (SSH, HTTPS, SnarkOS ports 3030/4130-4230/9090/9100, egress)
- `modules/tx-cannon/` — Optional TX cannon fleet (conditional, see below)

**Variable profiles:**
- `light.tfvars` — Small network (5 val, 0 client, 0 prover, 1 TX runner)
- `heavy.tfvars` — Large network (10 val, 20 client, 10 prover, 1 TX runner)
- `prerelease.tfvars` — Pre-release validation config

#### TX Cannon Module (`modules/tx-cannon/`)

Optional fleet of GCE instances for high-volume transaction generation. Provisioned only when `add_tx_cannons = true`.

```hcl
module "tx-cannon" {
  source = "./modules/tx-cannon"
  count  = var.add_tx_cannons ? 1 : 0
  # ...
}
```

**Infrastructure:** Creates its own `google_service_account` (`txcannon-sa`) with read-only GCS access to `provable-binaries-releases` bucket. Instances are spread across zones via round-robin.

**Data flow:** TX cannon nodes are provisioned infrastructure only — they pull the snarkOS binary from GCS and run tx-cannon containers. No component writes data to GCS specifically for tx-cannon consumption. TX cannon generates and sends transactions directly to validators via HTTP.

**Not to be confused with:**
- `pregenerate_transactions` utility — generates TX files and uploads to `provable-pregenerated-transactions` GCS bucket
- `load_saved_transactions` test — downloads pre-generated TXs from that bucket and replays them
- `terraform_tx_cannon/` — legacy AWS stack (deprecated, superseded by this module)

#### Legacy: `terraform_tx_cannon/` (Deprecated)

Stale AWS-based TX cannon stack. Superseded by `modules/tx-cannon/` (GCP). Pending deletion.

---

### Ansible Structure

#### Three-Playbook Hierarchy (Non-Obvious Pattern)

1. **`setup.yml`** — Initial node setup (run once per provision)
   - Download SnarkOS binary from S3
   - Generate validator keypairs
   - Configure systemd service
   - Start monitoring agents (Filebeat, Grafana Agent, Prometheus exporters)
   - **Cost:** ~10 min per node

2. **`run_test.yml`** — Execute named test (run per test, 100+ times)
   - Include test playbook from `tests/{test_name}/run_test.yml`
   - Pass variables: SELECTED (test name), VARS_FILE (config profile)
   - **Cost:** ~2-30 min per test

3. **`run_utility.yml`** — Execute utility with pre/post hooks
   - Include `utils/{utility_name}/pre-utility.sh` (setup)
   - Include `utils/{utility_name}/run_utility.yml` (main)
   - Include `utils/{utility_name}/post-utility.sh` (cleanup)

**Why separate?** Separates rare setup cost from frequent test execution. Enables fast re-runs without reprovisioning.

#### Test Definition Structure (Non-Obvious Pattern)

Each test is **extensible**, supporting 1-4 files:

```
tests/swap_ledgers/
├── run_test.yml              # REQUIRED: main test logic
├── swap.yml                  # OPTIONAL: included subtask
├── check.sh                  # OPTIONAL: post-test validation
└── restart.yml               # OPTIONAL: recovery script
```

Test execution flow:
```yaml
# playbooks/run_test.yml
- name: Run selected test
  include_tasks: "tests/{{ SELECTED }}/run_test.yml"
  vars:
    test_vars: "{{ lookup('file', VARS_FILE) | from_yaml }}"
```

**Benefits:**
- Simple tests (1 playbook) vs complex tests (4 files)
- Optional pre/post hooks for setup/cleanup
- Extensible without modifying core playbooks

---

### Ansible Roles (14 Total)

**SnarkOS Operations (8 roles):**
- `snarkos_build_from_git/` — Build SnarkOS from source (slow, for dev)
- `snarkos_build_locally/` — Local binary build
- `snarkos_install_binary/` — Pre-built binary install (fast, for tests)
- `snarkos_install_s3/` — Install from S3 versioned binary
- `snarkos_upload_local/` — Upload local binary to S3
- `snarkos_service/` — Configure systemd service
- `setup_tx_runner/` — Setup transaction runner
- `choose_bootstrap_client/` — Select bootstrap client for new validators

**Monitoring Setup (6 roles):**
- `prometheus_setup_with_clients/` — Prometheus scraping config
- `node_exporter_setup/` — System metrics collection
- `process_exporter_setup/` — Process-level metrics
- `metricbeat_setup/` — Elasticsearch metrics
- `filebeat_setup/` — Log collection + shipping
- `logstash_setup/` — Log processing + enrichment

---

### Dynamic Inventory

Generated at runtime by the `google.cloud.gcp_compute` inventory plugin. The
plugin queries the GCE API for instances in `protocol-development-sandbox`,
filters by status and `devnet` label, and builds host groups from GCE labels.

**File:** `test_suites/snarkos-p2p-tests/inventory/dynamic_inventory.gcp.yaml`

**Hostname source:** `private_ip` (`networkInterfaces[0].networkIP`). The
plugin assigns the private IP to both the Ansible hostname (`hostnames:
[private_ip]`) and the SSH target (`ansible_host`). Ansible must therefore run
from a host inside the shared VPC (STM, ephemeral builder, or another VM in
the same subnet).

**Filters:**

```yaml
filters:
  - status = RUNNING
  - labels.devnet = "snarkos-p2p-tests"
      OR labels.devnet = "stress-testing-manager"
      OR labels.devnet = "snarkos-cdn-tests"
```

**Keyed groups** (built from GCE labels):

| Group prefix | Source label | Example group |
|---|---|---|
| `devnet_` | `labels.devnet` | `devnet_snarkos_p2p_tests` |
| `owner_` | `labels.owner` | `owner_mikenichols` |
| `role_` | `labels.role` | `role_snarkos_validator`, `role_snarkos_prover`, `role_snarkos_builder`, `role_tx_runner`, `role_tx_cannon` |
| `gcp_` | `zone`, `machineType` | `gcp_us_central1_b`, `gcp_n2_standard_4` |

**Inspect the inventory** (run from the STM):

```bash
cd ~/snarkos-stress-testing/test_suites/snarkos-p2p-tests/playbooks
ansible-inventory --graph devnet_snarkos_p2p_tests
ansible-inventory --graph role_snarkos_validator
ansible -m ping devnet_snarkos_p2p_tests
```

---

## Pueue Job Queue Integration (Non-Obvious Pattern)

Atomizes test execution for parallelism + failure isolation.

### How It Works

**Script layer:**
```bash
# scripts/bin/run-test.sh
# 1. Validate test name exists
# 2. Atomically enqueue as "run-test:{test_name}" in pueue
# 3. Return immediately (job runs in background)
./scripts/lib/pueue.sh dispatch "run-test:${test_name}"
```

**Library:**
```bash
# scripts/lib/pueue.sh
pueue_dispatch_self() {
  local job_name=$1
  pueue add --label "${job_name}" "${@:2}"
}
```

**Full orchestrator:**
```bash
# scripts/full_run.sh (interactive mode)
# 1. Prompts for test selection
# 2. Calls ./scripts/bin/run-test.sh (enqueues via pueue)
# 3. Pueue manages job queue + parallelism
# 4. Streams logs from pueue worker
# 5. Collects results
```

### Benefits

- **Parallelism:** Multiple tests run simultaneously
- **Isolation:** One test failure doesn't block others
- **Job tracking:** Pueue maintains central queue + logs
- **Easy integration:** STM daemon can enqueue tests via Pueue API

---

## 12 Test Scenarios

Organized into 3 categories:

### Ledger Operations (2)
- `swap_ledgers/` — Swap ledger between validators 1 at a time
- `load_saved_transactions/` — Replay pre-saved transaction batch

### Malicious Behavior (6)
- `malicious_certificates/` — Invalid certificate handling
- `malicious_flood/` — Network flooding attack
- `malicious_peer_response/` — Malformed peer responses
- `malicious_resend_confirmed/` — Replay confirmed transactions
- `malicious_round_attack/` — Byzantine round attack
- `unbond_validators/` — Unbond/rebond stress test

### Prerelease Scenarios (3)
- `prerelease_1_halt_byzantine_majority/` — Majority halt recovery
- `prerelease_2_reset_client_ledgers/` — Client ledger resets
- `prerelease_3_reset_validator_ledgers/` — Validator ledger resets

---

## Utilities (14 Total)

Pre/post hook pattern (pre-utility.sh → run_utility.yml → post-utility.sh):

**TX Generation:**
- `pregenerate_transactions/` — Generate batches for load testing

**State Management:**
- `reset_all/` — Complete network reset
- `reset_clients/` — Reset client ledgers only

**Log Collection:**
- `download_logs_validators/` — Validator logs
- `download_logs_clients/` — Client logs
- `download_logs_tx_runner/` — TX runner logs
- `download_logs_provers/` — Prover logs
- `analyze_logs/` — Post-run analysis

**Validation:**
- `check_network_is_advancing/` — Verify network progress

**Metrics:**
- `download_prometheus_snapshot/` — Capture metrics snapshot

**Cleanup:**
- `stop_all/` — Stop all nodes
- `download_flamegraph/` — Collect flame graphs

---

## Stress-Testing-Manager (STM)

### Infrastructure (`stress-testing-manager/infrastructure/`)

**Provisioning:**
```bash
./tf_stack.sh provision  # Terraform apply
./tf_stack.sh setup      # Ansible setup
./tf_stack.sh destroy    # Terraform destroy
```

**EC2 Configuration:**
- **Type:** t3a.large (2 vCPU, 8GB RAM, burstable)
- **Storage:** 100GB EBS gp3
- **IAM role:** PowerUserAccess (broad permissions)
- **Security:** SSH (22), Talisker API (3030), ICMP (ping)

### Talisker Daemon

**What it does:**
1. Polls GitHub for new SnarkOS releases (tags + branches)
2. On new release, triggers test suite via Pueue
3. Monitors job queue
4. Collects results + metrics
5. Notifies Slack on completion

**JSON-RPC API (port 3030):**

```bash
# Status
scripts/talisker_control.sh status

# Trigger by branch
scripts/talisker_control.sh trigger --branch main

# Trigger by tag
scripts/talisker_control.sh trigger --tag v0.13.5

# Stop daemon
scripts/talisker_control.sh stop
```

---

## Packer (Base Image Builder)

### Test Suite Images

**`packer/stress-test-base.json.pkr.hcl` (x86_64):**
- Builds on Ubuntu 22.04 LTS
- Installs Docker, Rust, Cargo, build tools
- Installs monitoring agents (Filebeat, Metricbeat, node_exporter)
- Installs AWS CLI + Python dependencies

**`packer/stress-test-base-arm.json.pkr.hcl` (ARM64):**
- Same packages, targets Graviton processors (t4g.* instances)

### STM Image

**`stress-testing-manager/packer/image.json.pkr.hcl`:**
- Builds STM base image
- Installs Rust, sccache, git
- Installs Talisker daemon dependencies

---

## Log Analysis Stack

### Python Scripts (Pre-processing)

| Script | Input | Output |
|--------|-------|--------|
| `analysis_01_prepare_logfile.py` | Raw systemd logs | Normalized JSON lines |
| `analysis_02_sync_profiling.py` | JSON logs | Block height vs time CSV |
| `analysis_02_val_consensus_profiling.py` | JSON logs | Consensus round timings CSV |
| `analysis_02_val_tx_propagation_analysis.py` | JSON logs | TX latency scatter plot |
| `analysis_02_peermessage_profiling.py` | JSON logs | Peer message timeline |
| `analysis_02_transmission_consensus_queues.py` | JSON logs | Queue depth line plot |
| `analysis_flamegraph_svg.py` | Flamegraph SVG | Annotated PNG |

### Rust Timing Analyzer

**`timing_analysis/` (Rust CLI):**
```bash
cd log_analysis_scripts/timing_analysis/
cargo run --release -- --input logs.json --output stats.json
```

- Parses JSON logs
- Groups by event type
- Calculates percentiles (p50, p99, p999)
- Generates visualization charts

---

## Variable Binding (Complex)

### Terraform

**Profiles (stored in test_suites/snarkos-p2p-tests/terraform/):**
```hcl
# light.tfvars
validator_instance_count = 3
client_instance_count = 3
prover_instance_count = 1
instance_type = "n2-standard-4"

# heavy.tfvars
validator_instance_count = 10
client_instance_count = 20
prover_instance_count = 10
instance_type = "n2-highmem-8"
```

**Usage:**
```bash
terraform apply -var-file=light.tfvars
terraform apply -var-file=heavy.tfvars
```

### Ansible

**Template:**
```yaml
# playbooks/vars.example.yml
snarkos_version: v0.13.5
git_branch: main
log_level: INFO
prover_enabled: true
```

**Injection:**
```bash
# set_secrets.sh (injected at runtime)
source playbooks/vars.example.yml
ansible-playbook playbooks/setup.yml -e "snarkos_version=${snarkos_version}"
```

**Precedence:**
1. CLI arguments (highest)
2. Playbook variables
3. Role defaults (lowest)

### Test Runtime

**Environment variables:**
```bash
SELECTED="swap_ledgers"              # Test name
VARS_FILE="terraform/light.tfvars"   # Config profile
VARS_OVERRIDES="custom_var=value"    # Additional
```

---

## Shared Infrastructure

### S3 Buckets

| Bucket | Lifecycle | Content |
|--------|-----------|---------|
| `provable-binaries-releases` | 20 days | SnarkOS binaries by version |
| `provable-logs-results` | 90 days | Test logs, results, analysis |
| `aleo-snapshots` | Indefinite | Ledger checkpoints |
| `snarkos-compiler-cache` | 30 days | Rust sccache data |

### IAM Roles

**GCP Service Account:**
- `roles/compute.instanceAdmin`
- `roles/storage.objectViewer`
- `roles/storage.objectCreator`
- `roles/logging.admin`

**AWS IAM Role:**
- `PowerUserAccess` (broad)
- Custom S3 bucket access policies

---

## Summary Table

| Component | Layer | Purpose | Technology |
|-----------|-------|---------|-----------|
| Packer | Image | Build base OS + tools | HashiCorp Packer, Ansible |
| Terraform (main) | IaC | Validators + clients + provers | Terraform HCL, Google Cloud |
| Terraform (TX) | IaC | TX runner infrastructure | Terraform HCL, Google Cloud |
| Ansible | Config | Install + configure SnarkOS | Ansible YAML, 14 roles |
| Tests | Orchestration | Pluggable test scenarios (12 total) | Bash, Ansible, optional pre/post |
| Utilities | Helpers | TX gen, log collection (14 total) | Bash, Ansible, pre/post hooks |
| Scripts | Orchestration | CLI atomization + pueue dispatch | Bash, Pueue job queue |
| Talisker | Automation | Watch releases, enqueue tests | Rust, JSON-RPC |
| Log Analysis | Post-processing | Parse + visualize results | Python (7 scripts), Rust |
| S3 | Storage | Archive logs, binaries, caches | AWS S3 |
| Grafana | Monitoring | Real-time metrics, logs, traces | Grafana, Filebeat |

---

## Key Architectural Patterns

1. **Dual Terraform Stacks** — Separate lifecycle for validators vs TX runners
2. **Three-Playbook Hierarchy** — setup (rare) → run_test (frequent) → run_utility (helpers)
3. **Test Definition Extensibility** — run_test.yml (required) + optional subtasks
4. **Pueue Job Queue** — Atomizes tests, enables parallelism, isolates failures
5. **STM Isolation** — Long-running daemon with separate infrastructure + lifecycle
6. **Variable Precedence** — Terraform tfvars + Ansible vars + set_secrets.sh (dynamic)
7. **Utils with Pre/Post Hooks** — Setup → run_utility.yml → cleanup pattern
8. **Role Naming** — snarkos_* (operations) vs {component}_setup (third-party)

---

## Next Steps

- See [`COMMON_WORKFLOWS.md`](./COMMON_WORKFLOWS.md) for hands-on procedures
- See [`QUICK_REFERENCE.md`](./QUICK_REFERENCE.md) for command cheat sheet
- See [`STRUCTURE_SUMMARY.md`](../STRUCTURE_SUMMARY.md) for complete directory map

