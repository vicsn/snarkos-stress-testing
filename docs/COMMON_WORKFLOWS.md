# Common Workflows

Step-by-step procedures for frequent tasks.

---

## Anatomy of a Test Run

Complete flow from provision → setup → test → collect.

### 1. **Provisioning** (5-10 min)

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Initialize Terraform (once per workspace)
terraform init

# Plan infrastructure
terraform plan -var-file=light.tfvars

# Apply infrastructure
terraform apply -var-file=light.tfvars
```

**What happens:**
- GCP creates compute instances (validators, clients, provers, TX runner)
- Google Cloud creates network + firewall rules
- Terraform outputs node IPs to dynamic inventory

**Variables flow:**
```
light.tfvars
  ├─ validator_instance_count = 3
  ├─ client_instance_count = 3
  ├─ prover_instance_count = 1
  └─ instance_type = "n2-standard-4"
```

### 2. **Ansible Setup** (5-10 min)

```bash
cd ../playbooks

# Generate dynamic inventory from Terraform
./bin/generate_inventory.sh

# Run initial setup (once per provision)
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml \
  -e "snarkos_version=v0.13.5"
```

**What happens:**
- SSH to all nodes, install dependencies
- Download snarkOS binary from GCS (`gs://provable-binaries-releases/`)
- Generate validator keypairs (unique per node)
- Configure systemd service
- Start monitoring agents (Google Ops Agent, Prometheus exporters)

**Host groups created:**
```yaml
[snarkos_validator]     # 3 validators
[snarkos_client]        # 3 clients
[snarkos_prover]        # 1 prover
[tx_runner]             # 1 TX runner
```

### 3. **Test Execution** (2-30 min, depends on test)

```bash
# Method 1: Interactive (via full_run.sh)
./scripts/full_run.sh
# → Prompts for test selection
# → Enqueues via pueue job queue
# → Streams logs

# Method 2: Direct (via run-test.sh)
./scripts/bin/run-test.sh --test=swap_ledgers
# → Atomizes test as "run-test:swap_ledgers"
# → Enqueues in pueue
# → Returns immediately

# Method 3: Direct playbook (skip pueue)
ansible-playbook playbooks/run_test.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml \
  -e "SELECTED=swap_ledgers VARS_FILE=light.tfvars"
```

**What happens (pueue flow):**
1. `run-test.sh` validates test exists in `tests/{test_name}/`
2. Calls `scripts/lib/pueue.sh dispatch` (enqueues job)
3. Pueue worker picks up job, runs `run_test.yml`
4. Test playbook includes `tests/{test_name}/run_test.yml`
5. Optional pre/post hooks execute (if they exist)

**Test example:**
```yaml
# tests/swap_ledgers/run_test.yml
- name: Stop network
  command: systemctl stop snarkos
  become: yes

    - name: Download ledger snapshot
      ansible.builtin.command:
        cmd: >-
          gcloud storage cp
          gs://snapshots-{{ network }}/archive/{{ lookup('pipe', 'date -u +%Y-%m-%d') }}_00-00-01.tar
          /tmp/ledger.tar

- name: Restart network
  command: systemctl start snarkos
  become: yes

- name: Wait for sync
  include_tasks: ../../playbooks/is_synced.yml
```

### 4. **Log Collection** (2-3 min)

```bash
# Collect all logs from all nodes
ansible-playbook playbooks/fetch_and_zip_snarkos_logs.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml

# Logs uploaded to:
# gs://provable-logs-results/manual_test_runs/${USER}/${RUN_ID}/<test_name>/
```

**What happens:**
- SSH to each node
- Collect systemd journal (snarkOS)
- Collect application logs
- Zip + upload to GCS (`gs://provable-logs-results/`)
- Store for post-run analysis

### 5. **Post-Run Analysis** (Variable)

```bash
# Download logs
gcloud storage cp -r gs://provable-logs-results/manual_test_runs/$USER/<RUN_ID>/ ./logs/

# Run analysis
cd log_analysis_scripts/
python analysis_01_prepare_logfile.py \
  --input logs/snarkos.log \
  --output logs_normalized.json

python analysis_02_sync_profiling.py \
  --input logs_normalized.json \
  --output sync_chart.png
```

---

## Interactive Mode: Full Run

Recommended for development/debugging:

```bash
cd test_suites/snarkos-p2p-tests
./scripts/full_run.sh
```

**Prompts:**

1. **Terraform vars profile:**
   - `light.tfvars` (3 val, 3 client, 1 prover) — fast, cheap
   - `heavy.tfvars` (10 val, 20 client, 10 prover) — thorough, expensive
   - `prerelease.tfvars` (pre-release validation config)

2. **Test name:**
   - `swap_ledgers` — swap ledger snapshot
   - `unbond_validators` — stress test unbond/rebond
   - `malicious_flood` — network flooding attack
   - (11 other tests available)

3. **Proceed?**
   - `yes` — start provisioning
   - `no` — cancel

**Flow:**
```
Provision infrastructure
  ↓ (5-10 min)
Setup Ansible
  ↓ (5-10 min)
Run test
  ↓ (varies)
Collect logs
  ↓ (2-3 min)
✓ Complete + GCS upload
```

---

## Headless Mode: Non-Interactive

For automation (Talisker, CI/CD):

```bash
cd test_suites/snarkos-p2p-tests
./scripts/full_run.sh \
  --test=swap_ledgers \
  --tfvars=light.tfvars \
  --no-prompt
```

Or breakdown into steps:

```bash
# Provision only
./scripts/bin/provision.sh --tfvars=light.tfvars

# Setup only
./scripts/bin/setup.sh

# Run single test
./scripts/bin/run-test.sh --test=swap_ledgers

# Collect logs
./scripts/bin/collect-logs.sh
```

---

## Add a New Test

Create a pluggable test in `tests/` directory.

### Minimal Test (1 file)

```bash
mkdir -p test_suites/snarkos-p2p-tests/tests/my_custom_test
cd test_suites/snarkos-p2p-tests/tests/my_custom_test
```

**`run_test.yml`** (required):

```yaml
---
- name: My Custom Test
  hosts: snarkos_validator
  tasks:
    - name: Do something
      debug:
        msg: "Running my custom test"
    
    - name: Verify success
      assert:
        that:
          - true
        fail_msg: "Test failed"
```

### Full Test (3 files: pre-run-post)

```bash
mkdir -p test_suites/snarkos-p2p-tests/tests/my_complex_test
cd test_suites/snarkos-p2p-tests/tests/my_complex_test
```

**`pre-test.sh`** (optional setup):

```bash
#!/bin/bash
set -e

echo "Setting up test environment..."

# Example: Prepare data files
mkdir -p /tmp/test_data
echo "test data" > /tmp/test_data/input.txt
```

**`run_test.yml`** (required):

```yaml
---
- name: My Complex Test
  hosts: snarkos_validator
  tasks:
    - name: Read test data
      stat:
        path: /tmp/test_data/input.txt
      register: test_file
    
    - name: Verify data exists
      assert:
        that:
          - test_file.stat.exists
    
    - name: Run test logic
      debug:
        msg: "Test is running..."
    
    - name: Wait for completion
      pause:
        seconds: 30
```

**`post-test.sh`** (optional cleanup):

```bash
#!/bin/bash
set -e

echo "Cleaning up test environment..."

# Example: Clean up data files
rm -rf /tmp/test_data
```

### Optional Validation Script

**`check.sh`** (optional post-test validation):

```bash
#!/bin/bash
set -e

echo "Validating test results..."

# Check all nodes are synced
BLOCK_HEIGHTS=$(curl -s http://localhost:3030/rpc/latest_block_height)
echo "Block height: $BLOCK_HEIGHTS"

if [ "$BLOCK_HEIGHTS" -lt 100 ]; then
  echo "ERROR: Network did not advance"
  exit 1
fi

echo "✓ Test passed"
```

### Register with Orchestrator

Test is automatically discovered by scripts. Just ensure structure:

```
tests/my_custom_test/
├── run_test.yml              # REQUIRED
├── pre-test.sh               # OPTIONAL
├── post-test.sh              # OPTIONAL
└── check.sh                  # OPTIONAL
```

### Run Your Test

```bash
cd test_suites/snarkos-p2p-tests

# Via pueue
./scripts/bin/run-test.sh --test=my_custom_test

# Or directly
ansible-playbook playbooks/run_test.yml \
  -i inventory/dynamic_inventory.gcp.yaml \
  -e "SELECTED=my_custom_test"
```

---

## Provision Without Running a Test

Useful for manual exploration:

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Initialize
terraform init

# Plan
terraform plan -var-file=light.tfvars

# Apply
terraform apply -var-file=light.tfvars

# Setup nodes
cd ../playbooks
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml
```

Now you have a live network to explore manually.

---

## SSH Into a Node

```bash
# Get node IP from Terraform output
cd test_suites/snarkos-p2p-tests/terraform
VALIDATOR_IP=$(terraform output -raw validator_ips | head -1)

# SSH
gcloud compute ssh mike-testnet-v123-validator-0 \
  --zone=us-central1-a \
  --project=my-gcp-project

# Inside the node:
sudo systemctl status snarkos
sudo journalctl -u snarkos -f --lines=100

# Check block height
curl http://localhost:3030/rpc/latest_block_height

# View node info
snarkos node --help
```

---

## Run Ansible Playbook Manually

```bash
cd test_suites/snarkos-p2p-tests/playbooks

# Generate dynamic inventory
../inventory/dynamic_inventory.gcp.yaml

# Run playbook
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml \
  -v  # Add -v for verbose output

# Run specific task
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml \
  --tags="snarkos_install"

# Run against specific host group
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml \
  -l snarkos_validator  # Only validators
```

---

## Check Network Sync Status

```bash
cd test_suites/snarkos-p2p-tests/playbooks

ansible-playbook is_synced.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml
```

Blocks until all nodes reach same block height.

---

## Add a New Utility

Utilities are similar to tests but with pre/post hooks.

```bash
mkdir -p test_suites/snarkos-p2p-tests/utils/my_utility
cd test_suites/snarkos-p2p-tests/utils/my_utility
```

**Structure:**

```
utils/my_utility/
├── pre-utility.sh        # OPTIONAL: setup
├── run_utility.yml       # REQUIRED: main logic
└── post-utility.sh       # OPTIONAL: cleanup
```

**Example:**

```bash
# pre-utility.sh
#!/bin/bash
echo "Preparing utility..."
mkdir -p /tmp/utility_data

# run_utility.yml
---
- hosts: snarkos_validator
  tasks:
    - name: Run utility logic
      debug:
        msg: "Utility running..."

# post-utility.sh
#!/bin/bash
echo "Cleaning up..."
rm -rf /tmp/utility_data
```

### Run Your Utility

```bash
./scripts/bin/run-utility.sh --utility=my_utility
```

---

## Destroy Infrastructure

Clean up GCP resources:

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Plan destroy
terraform plan -destroy -var-file=light.tfvars

# Apply destroy
terraform destroy -var-file=light.tfvars -auto-approve
```

**Cost warning:** Destroying frees resources (good). But rebuilding takes 10-15 min.

---

## Scale Infrastructure

Change cluster size without destroying:

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Edit variables
cp light.tfvars custom.tfvars
vim custom.tfvars

# Change:
# validator_instance_count = 5      # was 3
# client_instance_count = 10         # was 3
# prover_instance_count = 3          # was 1

# Apply scaling
terraform apply -var-file=custom.tfvars

# Re-setup Ansible
cd ../playbooks
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml
```

---

## Modify Terraform Configuration

Add/remove firewall rules, change instance types:

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Edit main.tf or modules/
vim main.tf

# Plan changes
terraform plan -var-file=light.tfvars

# Apply changes
terraform apply -var-file=light.tfvars
```

---

## Control Stress-Testing-Manager (STM) Daemon

STM is a separate GCE instance running Talisker daemon.

```bash
# Provision STM
cd stress-testing-manager/infrastructure
./tf_stack.sh provision
./tf_stack.sh setup

# Control daemon
cd ../../scripts

# Check status
./talisker_control.sh status

# Trigger test run
./talisker_control.sh trigger --branch main
./talisker_control.sh trigger --tag v0.13.5

# Stop daemon (preserves infrastructure)
./talisker_control.sh stop

# Destroy STM
cd ../stress-testing-manager/infrastructure
./tf_stack.sh destroy
```

---

## Analyze Test Results

### Download Logs

```bash
gcloud storage cp -r \
  gs://provable-logs-results/manual_test_runs/$USER/<RUN_ID>/ \
  ./results/
```

### Prepare Logs

```bash
cd log_analysis_scripts

python analysis_01_prepare_logfile.py \
  --input ../results/snarkos.log \
  --output results_normalized.json
```

### Visualize Sync Profiling

```bash
python analysis_02_sync_profiling.py \
  --input results_normalized.json \
  --output sync_chart.png

# View chart
open sync_chart.png
```

### Analyze Consensus Timing

```bash
python analysis_02_val_consensus_profiling.py \
  --input results_normalized.json \
  --output consensus_timing.csv

# Open in spreadsheet
```

### Run Rust Timing Analyzer

```bash
cd timing_analysis
cargo run --release -- \
  --input ../results_normalized.json \
  --output timing_stats.json

open timing_stats.json  # View results
```

---

## Troubleshooting

### Ansible Inventory

The dynamic inventory (`inventory/dynamic_inventory.gcp.yaml`) discovers hosts by
GCE label. It uses each instance's **private IP** for both the Ansible hostname
(`hostnames: [private_ip]`) and the SSH target
(`ansible_host: networkInterfaces[0].networkIP`).

Because the inventory targets private IPs, run inventory and playbook commands
from a host inside the shared VPC. Use the stress-testing-manager, the ephemeral
builder, or another VM in the same subnet. Laptops cannot reach private IPs
directly.

**SSH to the manager:**

```bash
ssh ubuntu@stress-testing-manager
```

**Move to the playbooks directory:**

```bash
cd ~/snarkos-stress-testing/test_suites/snarkos-p2p-tests/playbooks
```

**List hosts grouped by devnet label:**

```bash
ansible-inventory --graph devnet_snarkos_p2p_tests
ansible-inventory --graph devnet_stress_testing_manager
```

**List hosts grouped by role label:**

```bash
ansible-inventory --graph role_snarkos_prover
ansible-inventory --graph role_snarkos_builder
ansible-inventory --graph role_tx_runner
```

**Test connectivity to every SRT host:**

```bash
ansible -m ping devnet_snarkos_p2p_tests
```

**If a host is missing from the graph, verify:**

- The instance status is `RUNNING`. The inventory filter drops other states.
- The instance has correct `devnet` and `role` labels applied by Terraform.
- Your gcloud application-default credentials can list instances in the project.
- The Ansible collection `google.cloud >= 1.13.0` is installed.

**If ping fails but the host appears in the graph, verify:**

- The SSH key `/home/ubuntu/snarkos-stress-testing/devnet-key` exists on the caller.
- Firewall rules allow SSH from the source subnet on port 22.
- The target instance shares the same VPC as the source host.

### Test Won't Start

**Check pueue queue:**
```bash
cd test_suites/snarkos-p2p-tests
pueue status

## example failing job
#
# ~$ pueue status
# Group "default" (1 parallel): running
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#  Id   Status              Deps      Command                                                                    Path           Start        End        
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
#  10   Failed (127)                  env PUEUE_WORKER=1 PATH=/home/ubuntu/.cargo/bin:/usr/local/sbin:/usr/loc   /home/ubuntu   2026-08-07   2026-08-07 
#                                     al/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/b                  11:03:58     11:03:59   
#                                     in /home/ubuntu/snarkos-stress-testing/test_suites/snarkos-p2p-tests/s                                          
#                                     cripts/bin/provision.sh --mode=light --vars=vars

# inspect logs for failing task GroupId: 10
pueue logs 10

# Clear stuck jobs
pueue clean
```

### Nodes Won't Sync

**SSH to validator:**
```bash
sudo journalctl -u snarkos -f

# Look for:
# - "synced block X of Y"
# - Connection errors
# - Ledger corruption
```

**Re-run setup:**
```bash
ansible-playbook playbooks/setup.yml \
  -i inventory/dynamic_inventory.gcp.yaml
```

### Infrastructure Won't Provision

**Check Terraform:**
```bash
cd terraform
terraform validate
terraform plan -var-file=light.tfvars
```

**Check GCP quota:**
```bash
gcloud compute project-info describe --project=my-project
```

### Logs Not Uploading

**Verify GCS access:**
```bash
gcloud storage ls gs://provable-logs-results/manual_test_runs/$USER/

# Check authentication
gcloud auth list
```

---

## See Also

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — Detailed reference
- [`QUICK_REFERENCE.md`](./QUICK_REFERENCE.md) — Command cheat sheet
- [`DEPLOYMENT_PATTERNS.md`](./DEPLOYMENT_PATTERNS.md) — Design patterns
