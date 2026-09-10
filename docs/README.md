# SnarkOS Stress Testing Documentation

Comprehensive guides for the snarkos-stress-testing framework.

---

## Documentation Index

| Document | Purpose | Audience |
|---|---|---|
| **[DEPLOYMENT_PATTERNS.md](./DEPLOYMENT_PATTERNS.md)** | High-level overview of how the framework is organized | Everyone — start here |
| **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Detailed reference of infrastructure layers, modules, and components | Engineers, DevOps, maintainers |
| **[COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md)** | Step-by-step procedures for frequent tasks (provision, run tests, SSH, etc.) | Operators, test runners |

---

## Quick Start

### I want to run a stress test

1. Read: [DEPLOYMENT_PATTERNS.md](./DEPLOYMENT_PATTERNS.md) — sections 1-3 (2 min)
2. Follow: [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md) → "Provision & Run a GCP Test" (15 min)

### I want to understand the architecture

1. Read: [DEPLOYMENT_PATTERNS.md](./DEPLOYMENT_PATTERNS.md) (5 min)
2. Read: [ARCHITECTURE.md](./ARCHITECTURE.md) (15 min)
3. Reference: [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md) as needed

### I want to add/modify infrastructure

1. Read: [ARCHITECTURE.md](./ARCHITECTURE.md) → "GCP snarkos-p2p-tests" (10 min)
2. Follow: [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md) → "Modify Terraform Configuration" (10 min)

### I want to create a new test

1. Follow: [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md) → "Add a New Test" (15 min)

### Something went wrong

1. Follow remediation steps
1. Reference: [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md) → "Troubleshooting" section

---

## Key Concepts

### Four Layers of Deployment

```
Layer 1: Packer        → Build base OS image + tools
Layer 2: Terraform     → Provision cloud resources (compute, network)
Layer 3: Ansible       → Configure SnarkOS + monitoring
Layer 4: Test Suite    → Execute tests + collect results
```

### Two-Tier Cloud Strategy

- **GCP:** P2P network suite (`snarkos-p2p-tests`) — validators, clients, provers interacting over P2P
- **AWS:** CDN/ledger suite (`snarkos-cdn-tests`) — single machine, load a ledger or sync

### Central Automation

- **Talisker:** Daemon on STM (Stress Testing Manager) that watches GitHub for new SnarkOS releases and automatically triggers test suites

### Dynamic Naming Convention

All resources follow the pattern: `${owner}-${devnet_name}-<role>`

Example: `mike-testnet-v123-validator-0`

- `owner` = who runs the test (user)
- `devnet_name` = network identifier (e.g., testnet-v123)
- `role` = node type (validator, client, prover, tx-runner, etc.)

---

## Technology Stack

| Layer | Tools |
|---|---|
| IaC | Terraform (GCP ≥7.32.0, AWS) |
| Config Mgmt | Ansible |
| Image Build | HashiCorp Packer |
| Cloud — GCP | Compute Engine, Firewall, Cloud LB, IAM |
| Cloud — AWS | EC2, ELB, S3, IAM |
| Monitoring | Grafana Cloud, Prometheus, Filebeat, Grafana Agent |
| Languages | Bash, Python 3.12+, Rust 2021 |
| Blockchain | SnarkOS (Aleo node), snarkVM, tx-cannon (Docker/ECR) |

---

## File Organization

```
snarkos-stress-testing/
├── docs/                   # Documentation (THIS FOLDER)
│   ├── README.md          # Start here
│   ├── DEPLOYMENT_PATTERNS.md
│   ├── ARCHITECTURE.md
│   ├── COMMON_WORKFLOWS.md
│
├── packer/                # Base image builder
├── scripts/               # Operational utilities
├── log_analysis_scripts/  # Post-run analysis
├── stress-testing-manager/# Central automation (STM)
└── test_suites/           # Test suite implementations
    ├── snarkos-p2p-tests/ (GCP P2P network)
    └── snarkos-cdn-tests/  (AWS CDN / ledger / sync)
```

---

## GCP Access

Access to the `protocol-development-sandbox` GCP project is granted through membership in the Google Group `gcp-service-protocol-development@provable.com`. This project hosts all GCP stress test resources.

### How users become members of the group

Group membership is managed in the Google Workspace Admin Console (admin.google.com), not in Terraform. A Google Workspace Group Admin must add the user's `@provable.com` account to the group. Once added, all IAM role bindings on the group apply automatically to the user.

To request access, contact a Google Workspace Group Admin. Access takes effect within a few minutes.

### Permissions granted to the group

The group holds 5 project-scoped IAM roles on `protocol-development-sandbox`:

| Role | Purpose |
|---|---|
| `roles/viewer` | Read access to all project resources |
| `roles/compute.instanceAdmin.v1` | Create, modify, and delete Compute Engine instances |
| `roles/compute.osAdminLogin` | SSH into VMs as an OS admin (via OS Login) |
| `roles/iap.tunnelResourceAccessor` | Tunnel through Identity-Aware Proxy (IAP) for SSH |
| `roles/storage.admin` | Full control of Cloud Storage buckets and objects |

Together these roles allow the user to provision test infrastructure, SSH into nodes through IAP, and manage Cloud Storage buckets for test artifacts.

### Where the bindings are defined

The bindings live in the `ProvableHQ/infrastructure` repository, not in this repository:

| Binding | Location |
|---|---|
| `roles/viewer` (baseline, set at project creation) | `gcp/organization-config/service-projects.tf:146-167` |
| Other 4 roles (VM + IAP + Storage) | `gcp/protocol-development-sandbox/workload/iam.tf` |

Group membership itself is not defined in any Terraform file. It lives in Google Workspace.

---

## Common Commands

### Provision and run a test (interactive)

```bash
cd test_suites/snarkos-p2p-tests
./run_test_suite.sh
```

### Provision and run a test (headless)

```bash
cd test_suites/snarkos-p2p-tests
./run_test_suite.sh --test swap_ledgers --tfvars light.tfvars --no-prompt
```

### SSH into a node

```bash
gcloud compute ssh mike-testnet-v123-validator-0 --zone=us-central1-a
```

### Destroy infrastructure

```bash
cd test_suites/snarkos-p2p-tests/terraform
terraform destroy -var-file=light.tfvars -auto-approve
```

### Control Talisker automation

```bash
scripts/talisker_control.sh status
scripts/talisker_control.sh trigger --branch main
scripts/talisker_control.sh stop
```

---

## Important Files

| File | Purpose |
|---|---|
| `test_suites/snarkos-p2p-tests/run_test_suite.sh` | Master orchestrator (GCP) |
| `test_suites/snarkos-p2p-tests/terraform/main.tf` | GCP instance definitions |
| `test_suites/snarkos-p2p-tests/terraform/variables.tf` | Input variables + defaults |
| `test_suites/snarkos-p2p-tests/terraform/*.tfvars` | Configuration profiles (light, heavy, prerelease) |
| `test_suites/snarkos-p2p-tests/playbooks/setup.yml` | Ansible main setup |
| `test_suites/snarkos-p2p-tests/playbooks/vars.yml` | Generated by STM (runtime vars) |
| `test_suites/snarkos-p2p-tests/tests/*/run_test.yml` | Individual test implementations |
| `stress-testing-manager/infrastructure/main.tf` | STM EC2 definition |
| `stress-testing-manager/infrastructure/ansible/setup.yml` | STM setup (Talisker installation) |
| `packer/stress-test-base.json.pkr.hcl` | Base image config (x86_64) |
| `scripts/talisker_control.sh` | Talisker control CLI |

---

## S3 Buckets

| Bucket | Purpose | Retention |
|---|---|---|
| `provable-binaries-releases` | SnarkOS binaries | 20 days |
| `provable-logs-results` | Test logs + analysis | 90 days |
| `aleo-snapshots` | Ledger checkpoints | Indefinite |
| `snarkos-compiler-cache` | sccache build cache | 30 days |
| `ephnet-terraform-state-bucket-eq` | Terraform state | Indefinite |

---

## Naming Convention Examples

All resources follow: `${owner}-${devnet_name}-<role>`

```
owner=mike, devnet_name=testnet-v123
↓
GCP instance names:
  - mike-testnet-v123-validator-0
  - mike-testnet-v123-client-0
  - mike-testnet-v123-prover-0

Terraform labels:
  - role: validator|client|prover|tx-runner
  - owner: mike
  - devnet: testnet-v123

Firewall tags:
  - validator, client, prover

Ansible groups:
  - snarkos_validator, snarkos_client, snarkos_prover

S3 paths:
  - logs/mike/testnet-v123/2024-06-16T12-34-56/
```

---

## Configuration Hierarchy

```
tfvars profiles (light, heavy, prerelease)
  ↓ Override
Terraform variable defaults
  ↓ Override
Ansible generated vars.yml
  ↓ Override
Playbook-level vars + host_vars
```

---

## Next Steps

- **Start here:** [DEPLOYMENT_PATTERNS.md](./DEPLOYMENT_PATTERNS.md)
- **Then:** [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md)
- **Reference:** [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## TODO

- [20260810]
  - SSH access to gce instances for snarkos-p2p-tests should be setup for public key ./devnet-key.pub (not oslogin)

## Questions?

Refer to the relevant document above, or search within a document using your browser's find function (Ctrl+F or Cmd+F).

For code reference, see:
- Terraform modules: `test_suites/snarkos-p2p-tests/terraform/modules/`
- Ansible playbooks: `test_suites/snarkos-p2p-tests/playbooks/`
- Test implementations: `test_suites/snarkos-p2p-tests/tests/*/`
- Utilities: `test_suites/snarkos-p2p-tests/utils/*/`
