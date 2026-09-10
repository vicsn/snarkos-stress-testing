# Quick Reference Card

**1-page cheat sheet for common operations.**

---

## Run a Test (GCP)

```bash
cd test_suites/snarkos-p2p-tests

# Interactive (recommended)
./scripts/full_run.sh

# Headless
./scripts/bin/run-test.sh --test=swap_ledgers

# Via pueue (see job queue)
pueue status
pueue log run-test:swap_ledgers
```

**Time: ~15-30 min depending on test**

---

## Pueue Job Queue (Atomized Tests)

```bash
cd test_suites/snarkos-p2p-tests

# Status
pueue status

# Enqueue test
pueue add --label "run-test:swap_ledgers" \
  ansible-playbook playbooks/run_test.yml \
  -e "SELECTED=swap_ledgers"

# Watch logs
pueue log run-test:swap_ledgers -f

# Clear queue
pueue clean

# Restart worker
pueue reset
```

---

## Test Inventory (12 Available)

### Ledger Operations (2)
```bash
./scripts/bin/run-test.sh --test=swap_ledgers
./scripts/bin/run-test.sh --test=load_saved_transactions
```

### Malicious Behavior (6)
```bash
./scripts/bin/run-test.sh --test=malicious_certificates
./scripts/bin/run-test.sh --test=malicious_flood
./scripts/bin/run-test.sh --test=malicious_peer_response
./scripts/bin/run-test.sh --test=malicious_resend_confirmed
./scripts/bin/run-test.sh --test=malicious_round_attack
./scripts/bin/run-test.sh --test=unbond_validators
```

### Prerelease Scenarios (3)
```bash
./scripts/bin/run-test.sh --test=prerelease_1_halt_byzantine_majority
./scripts/bin/run-test.sh --test=prerelease_2_reset_client_ledgers
./scripts/bin/run-test.sh --test=prerelease_3_reset_validator_ledgers
```

---

## Provision & Setup

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Initialize (once)
terraform init

# Plan
terraform plan -var-file=light.tfvars

# Apply
terraform apply -var-file=light.tfvars

# Setup nodes (once per provision)
cd ../playbooks
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yml

# Verify sync
ansible-playbook is_synced.yml \
  -i ../inventory/dynamic_inventory.gcp.yml
```

---

## SSH & Node Access

```bash
# SSH to validator
gcloud compute ssh mike-testnet-v123-validator-0 \
  --zone=us-central1-a

# Inside node:
sudo systemctl status snarkos
sudo journalctl -u snarkos -f
curl http://localhost:3030/rpc/latest_block_height
```

---

## Common Ansible Playbooks

```bash
cd test_suites/snarkos-p2p-tests/playbooks

# Check sync
ansible-playbook is_synced.yml \
  -i ../inventory/dynamic_inventory.gcp.yml

# Restart SnarkOS
ansible-playbook restart_snarkos.yml \
  -i ../inventory/dynamic_inventory.gcp.yml

# Stop and clean state
ansible-playbook stop_and_clean_snarkos.yml \
  -i ../inventory/dynamic_inventory.gcp.yml

# Collect logs
ansible-playbook fetch_and_zip_snarkos_logs.yml \
  -i ../inventory/dynamic_inventory.gcp.yml
```

---

## Ansible Inventory

The dynamic inventory uses **private IPs** (`hostnames: [private_ip]`,
`ansible_host: networkInterfaces[0].networkIP`). Run these from inside the VPC
(the STM or the ephemeral builder), not your laptop.

```bash
# SSH to the manager
ssh ubuntu@stress-testing-manager

# Move to playbooks directory
cd ~/snarkos-stress-testing/test_suites/snarkos-p2p-tests/playbooks

# List hosts by devnet
ansible-inventory --graph devnet_snarkos_p2p_tests
ansible-inventory --graph devnet_stress_testing_manager

# List hosts by role
ansible-inventory --graph role_snarkos_prover
ansible-inventory --graph role_snarkos_builder
ansible-inventory --graph role_tx_runner

# Test connectivity
ansible -m ping devnet_snarkos_p2p_tests
```

---

## Utilities (14 Available)

```bash
cd test_suites/snarkos-p2p-tests

# TX generation
./scripts/bin/run-utility.sh --utility=pregenerate_transactions

# State resets
./scripts/bin/run-utility.sh --utility=reset_all
./scripts/bin/run-utility.sh --utility=reset_clients

# Log collection
./scripts/bin/run-utility.sh --utility=download_logs_validators
./scripts/bin/run-utility.sh --utility=download_logs_clients
./scripts/bin/run-utility.sh --utility=download_logs_tx_runner
./scripts/bin/run-utility.sh --utility=download_logs_provers

# Validation
./scripts/bin/run-utility.sh --utility=check_network_is_advancing

# Metrics
./scripts/bin/run-utility.sh --utility=download_prometheus_snapshot

# Analysis
./scripts/bin/run-utility.sh --utility=analyze_logs

# Cleanup
./scripts/bin/run-utility.sh --utility=stop_all
./scripts/bin/run-utility.sh --utility=download_flamegraph
```

---

## Terraform Configs

| File | Use |
|------|-----|
| `light.tfvars` | Small network (3 val, 3 client, 1 prover) — dev |
| `heavy.tfvars` | Large network (10 val, 20 client, 10 prover) — prod |
| `prerelease.tfvars` | Pre-release validation config |

```bash
terraform apply -var-file=light.tfvars
terraform apply -var-file=heavy.tfvars
```

---

## Scale & Modify Infrastructure

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Edit variables
vim light.tfvars
# Change validator_instance_count, client_instance_count, etc.

# Apply scaling
terraform apply -var-file=light.tfvars

# Re-setup
cd ../playbooks
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yml
```

---

## Stress-Testing-Manager (STM)

```bash
# Provision STM
cd stress-testing-manager/infrastructure
./tf_stack.sh provision
./tf_stack.sh setup

# Control daemon
cd ../../scripts

# Status
./talisker_control.sh status

# Trigger by branch
./talisker_control.sh trigger --branch main

# Trigger by tag
./talisker_control.sh trigger --tag v0.13.5

# Stop daemon
./talisker_control.sh stop

# Destroy
cd ../stress-testing-manager/infrastructure
./tf_stack.sh destroy
```

---

## Destroy Infrastructure

```bash
cd test_suites/snarkos-p2p-tests/terraform

terraform destroy -var-file=light.tfvars -auto-approve
```

**Cost warning:** Takes 10-15 min to rebuild.

---

## Log Collection & Analysis

```bash
# Download logs
aws s3 sync \
  s3://provable-logs-results/logs/mike/testnet-v123/ \
  ./logs/

# Prepare
cd log_analysis_scripts
python analysis_01_prepare_logfile.py \
  --input logs/validator-0.log \
  --output logs.json

# Visualize sync
python analysis_02_sync_profiling.py \
  --input logs.json \
  --output sync.png

# Consensus timing
python analysis_02_val_consensus_profiling.py \
  --input logs.json \
  --output consensus.png

# Rust timing analyzer
cd timing_analysis
cargo run --release -- \
  --input logs.json \
  --output stats.json
```

---

## Key Directories

```
test_suites/snarkos-p2p-tests/
├── terraform/              # IaC (dual stacks: main + tx_cannon)
├── terraform_tx_cannon/    # TX runner stack
├── playbooks/              # Ansible (setup, run_test, run_utility)
├── tests/                  # 12 pluggable test definitions
├── utils/                  # 14 utility helpers
└── scripts/                # CLI orchestration (bin + lib)
    ├── bin/                # 8 executables
    │   ├── provision.sh
    │   ├── setup.sh
    │   ├── run-test.sh
    │   ├── run-utility.sh
    │   ├── select-test.sh
    │   ├── destroy.sh
    │   ├── collect-logs.sh
    │   └── .shellcheckrc
    ├── lib/                # 3 libraries
    │   ├── common.sh
    │   ├── notify.sh
    │   └── pueue.sh
    └── full_run.sh         # Interactive orchestrator
```

---

## Resource Naming

**Pattern:** `${owner}-${devnet_name}-<role>-<index>`

Examples:
- `mike-testnet-v123-validator-0`
- `mike-testnet-v123-client-0`
- `mike-testnet-v123-prover-0`
- `mike-testnet-v123-tx-runner`

---

## Firewall Rules (Role-Based)

| Role | Ports |
|------|-------|
| validator, client | 3030, 4130, 4130-4230 |
| prover | 9090 |
| TX runner | 3030 (send TXs) |
| prometheus | 9100 (scrape) |
| all | 22 (SSH), 443 (HTTPS), ICMP |

---

## Instance Types (GCP)

| Role | Small | Large |
|------|-------|-------|
| validator | n2-highmem-8 | n2-highmem-16 |
| client | n2-standard-4 | n2-standard-8 |
| prover | n2-highmem-8 | n2-highmem-16 |
| tx-runner | n2-standard-8 | n2-highmem-8 |

---

## S3 Buckets

| Bucket | Use |
|--------|-----|
| `provable-logs-results` | Test logs, results |
| `provable-binaries-releases` | SnarkOS binaries |
| `aleo-snapshots` | Ledger checkpoints |
| `snarkos-compiler-cache` | Build cache |

```bash
# List
aws s3 ls s3://provable-logs-results/logs/mike/

# Download
aws s3 cp s3://provable-logs-results/logs/mike/testnet-v123/ ./logs/ --recursive
```

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| Test won't start | `pueue status` → clear stuck jobs |
| Network won't sync | `is_synced.yml` → check journalctl |
| SnarkOS crashes | `journalctl -u snarkos -n 50` |
| Terraform fails | Check quota, service account perms |
| Ansible inventory empty or missing hosts | Run from inside the VPC (STM). `ansible-inventory --graph devnet_snarkos_p2p_tests`. Verify labels + `google.cloud` collection. |
| Ansible ping fails | `ansible -m ping devnet_snarkos_p2p_tests`. Verify `devnet-key` exists on caller, port 22 open, same VPC. |
| SSH fails | Verify firewall rule, public IP |
| Logs not uploading | Check S3 bucket policy, IAM role |

---

## Documentation

- **[README.md](./README.md)** — Entry point
- **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** — This file
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — Detailed reference
- **[COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md)** — Step-by-step procedures
- **[DEPLOYMENT_PATTERNS.md](./DEPLOYMENT_PATTERNS.md)** — Design patterns
- **[STRUCTURE_SUMMARY.md](../STRUCTURE_SUMMARY.md)** — Complete directory map

---

## Linting

```bash
# YAML
ansible-lint playbooks/*.yml

# Shell scripts
shellcheck scripts/bin/*.sh scripts/lib/*.sh

# All linters
./lint.sh
```

---

**For detailed procedures, see [COMMON_WORKFLOWS.md](./COMMON_WORKFLOWS.md)**
