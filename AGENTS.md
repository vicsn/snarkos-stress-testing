# Agents Documentation Guide

Quick reference for using Agents and tools with the snarkos-stress-testing project.

---

## Available Skills

### snarkos-stress-testing (Project-Specific Skill)

**Location:** `.agents/skills/snarkos-stress-testing/SKILL.md`

Expert knowledge of the snarkos-stress-testing framework:
- Infrastructure provisioning (Terraform GCP — single-region-tests + stress-testing-manager; AWS retained only for network-sync-tests)
- Configuration management (Ansible)
- Test orchestration (pueue task queue)
- Stress Testing Manager (GCE-based; delegates full_run.sh over `gcloud compute ssh`)
- Log analysis (Python/Rust)

**When to use:**
- Modifying Terraform infrastructure
- Creating/debugging Ansible playbooks
- Adding new tests
- Understanding architecture & components
- Troubleshooting deployment issues

**Load the skill:**
```
/skill snarkos-stress-testing
```

---

## Using the Skill Effectively

### 1. **Infrastructure Changes**

Use the skill when:
- Adding/removing compute instance types
- Modifying firewall rules or network topology
- Updating Terraform modules
- Changing variable defaults or configurations

**Example workflow:**
```bash
# 1. Load the skill
/skill snarkos-stress-testing

# 2. Ask for help modifying Terraform
# "I want to add a new analytics instance type to the GCP network"

# 3. Reference ARCHITECTURE.md section "GCP Single-Region-Tests"
# or follow COMMON_WORKFLOWS.md "Modify Terraform Configuration"
```

### 2. **Test Development**

Use the skill when creating new tests:
- Writing test YAML playbooks
- Adding pre/post hooks
- Integrating with orchestrator

**Follow:** `docs/COMMON_WORKFLOWS.md` → "Add a New Test"

### 3. **Operations & Automation**

Use the skill for:
- Provisioning/destroying networks
- Running tests (interactive + headless)
- Managing the Stress Testing Manager (provision, setup, update, destroy)
- Troubleshooting failures

**Quick reference:** `docs/QUICK_REFERENCE.md`

---

## Documentation Structure

All documentation is in the `docs/` folder:

```
docs/
├── README.md                 # Start here (248 lines)
├── DEPLOYMENT_PATTERNS.md   # 10 high-level patterns (395 lines)
├── ARCHITECTURE.md          # Detailed reference (734 lines)
├── COMMON_WORKFLOWS.md      # Step-by-step procedures (667 lines)
└── QUICK_REFERENCE.md       # 1-page cheat sheet (238 lines)
```

**Total: 2,282 lines | 65KB | Comprehensive coverage**

---

## Reading Paths by Role

### 🚀 Operators / Test Runners

**Goal:** Run stress tests, collect logs, troubleshoot

**Path (30 min):**
1. `docs/README.md` (5 min)
2. `docs/QUICK_REFERENCE.md` (2 min)
3. `docs/COMMON_WORKFLOWS.md` → "Provision & Run a GCP Test" (15 min)
4. Bookmark `docs/QUICK_REFERENCE.md` for daily use

**Key skills:**
- `scripts/full_run.sh --mode=light --tests=<name>`
- `scripts/bin/run-test.sh --test=<name>`
- `gcloud compute ssh <instance>`

---

### 🏗️ Infrastructure Engineers

**Goal:** Understand architecture, modify infrastructure, add resources

**Path (40 min):**
1. `docs/README.md` (5 min)
2. `docs/DEPLOYMENT_PATTERNS.md` (5 min)
3. `docs/ARCHITECTURE.md` (15 min)
4. `docs/COMMON_WORKFLOWS.md` → "Modify Terraform Configuration" (10 min)
5. Reference `docs/ARCHITECTURE.md` for deep dives

**Key tasks:**
- Add new instance types
- Modify firewall rules
- Create Terraform modules
- Update variable profiles

---

### 🧪 Test Developers

**Goal:** Create new tests, understand test structure

**Path (25 min):**
1. `docs/README.md` (5 min)
2. `docs/DEPLOYMENT_PATTERNS.md` → Section 6 "Test Suite Abstraction" (5 min)
3. `docs/COMMON_WORKFLOWS.md` → "Add a New Test" (15 min)

**Key tasks:**
- Create `tests/<test-name>/run_test.yml`
- Add pre/post hooks (optional)
- Tests are auto-discovered (no registration needed)
- Validate & test

---

### 🔧 DevOps / Operators

**Goal:** Provision the Stress Testing Manager, run pueue-based test suites, monitor

**Path (25 min):**
1. `docs/README.md` (5 min)
2. `docs/ARCHITECTURE.md` → "Stress Testing Manager (STM)" (5 min)
3. `stress-testing-manager/README.md` → provision + setup workflow (5 min)
4. Bookmark `stress-testing-manager/infrastructure/tf_stack.sh` for daily use

**Key tasks:**
- Provision STM on GCP (`tf_stack.sh provision` + `setup`)
- Monitor pueued via `gcloud compute ssh <stm> -- systemctl status pueued`
- Trigger test suites (delegates over `gcloud compute ssh`)
- View logs & results in GCS + Cloud Logging

---

## Common Commands Quick Reference

### Provision & Run a Test

```bash
cd test_suites/single-region-tests

# Full pipeline (provision + setup + test + destroy via pueue)
scripts/full_run.sh --mode=light --tests=swap_ledgers

# Run all tests
scripts/full_run.sh --mode=heavy --tests=all

# Individual steps
scripts/bin/provision.sh --mode=light
scripts/bin/setup.sh
scripts/bin/run-test.sh --test=swap_ledgers
scripts/bin/destroy.sh

# Interactive test selection
scripts/bin/select-test.sh

# Run without pueue (sequential)
PUEUE_DISABLED=1 scripts/full_run.sh --mode=light --tests=swap_ledgers
```

### SSH Into a Node

```bash
gcloud compute ssh mike-single-region-tests-snarkos-validator-0 --zone=us-central1-b

# Inside node
sudo systemctl status snarkos
sudo journalctl -u snarkos -f
curl http://localhost:3030/testnet/block/height/latest
```

### Terraform Operations

```bash
cd test_suites/single-region-tests/terraform

terraform plan -var-file=light.tfvars
terraform apply -var-file=light.tfvars -auto-approve -var="owner=$USER"
terraform destroy -auto-approve -var="owner=$USER"
```

### Ansible Playbooks

```bash
cd test_suites/single-region-tests/playbooks

# Check sync status
ansible-playbook is_synced.yml -i ../inventory/dynamic_inventory.gcp.yaml

# Restart validators
ansible-playbook restart_snarkos.yml -i ../inventory/dynamic_inventory.gcp.yaml

# Collect logs
ansible-playbook fetch_and_zip_snarkos_logs.yml -i ../inventory/dynamic_inventory.gcp.yaml
```

### Stress Testing Manager (STM)

```bash
# Provision the STM (GCE c3d-standard-4 + static IP + IAM SA)
cd stress-testing-manager/infrastructure
./tf_stack.sh provision --auto-approve

# Bootstrap toolchain (Rust, pueue, sccache→GCS, Slack from Secret Manager)
./tf_stack.sh setup

# Partial re-run (repo sync + pueue only)
./tf_stack.sh update --update-target both

# Delegated full test run (from your laptop; SSH is gcloud compute ssh)
cd ../../test_suites/single-region-tests
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
scripts/full_run.sh --mode=light --tests=prerelease

# Tear down
cd ../../stress-testing-manager/infrastructure
./tf_stack.sh destroy --force --auto-approve
```

Legacy `scripts/talisker_control.sh` was removed as part of the AWS→GCP consolidation — the STM now manages pueue tasks natively via `pueued` on the manager instance.

### Build GCP Base Image (Packer)

```bash
cd packer

# 1. Install plugins (first time only)
packer init stress-test-base.pkr.hcl

# 2. Authenticate (if not already)
gcloud auth application-default login

# 3. Build — VPC/subnet required (no default VPC in project)
# The VPC is owned by the STM: <workspace>-stress-testing-manager-vpc.
# For the default workspace, use "default-stress-testing-manager-vpc".
# To discover the current name:
#   (cd ../stress-testing-manager/infrastructure && ./tf_stack.sh output | grep vpc_name)
packer build \
  -var 'network=default-stress-testing-manager-vpc' \
  -var 'subnetwork=protocol-development-sandbox-subnet-us-central1' \
  stress-test-base.pkr.hcl

# 4. Use the custom image in Terraform (optional — default is stock Ubuntu)
cd ../test_suites/single-region-tests/terraform
terraform apply \
  -var 'image_family=stress-test-base' \
  -var 'image_project=protocol-development-sandbox' \
  -var-file=light.tfvars -var="owner=$USER"

# 5. Revert to stock Ubuntu (if needed)
terraform apply \
  -var 'image_family=ubuntu-2204-lts' \
  -var 'image_project=ubuntu-os-cloud' \
  -var-file=light.tfvars -var="owner=$USER"
```

**What gets baked in:** Docker, Docker Compose, GitHub CLI, gcloud CLI, Node/Process Exporter, Google Ops Agent, python3, libclang-dev, zip/unzip.
**What does NOT get baked in:** snarkOS binary (compiled separately, cached in GCS).
**Variables:** `gcp_project`, `gcp_zone`, `machine_type`, `image_family`, `network`, `subnetwork`.
**Default image family:** `stress-test-base` in `protocol-development-sandbox`.
**Build time:** ~10 minutes.
**Details:** `packer/README.md`.

---

## Log Collection & Upload

Logs are uploaded to GCS by `download_and_upload_logs()` in `scripts/lib/common.sh`.

**Bucket:** `gs://provable-logs-results/`
**Path format:** `manual_test_runs/<user>/<RUN_ID>/<test_name>/`
**Example:** `gs://provable-logs-results/manual_test_runs/mikenichols/20260707T172234Z/swap_ledgers/`

### Who uploads

The **machine running the scripts** (laptop or stress-testing-manager) — not the GCE compute instances. The uploader needs `gcloud` auth with write access to the bucket.

**SRT compute-node upload capability (enabled, not yet exercised):** The SRT `snarkos_sa` service account now has `roles/storage.objectCreator` on `provable-logs-results`. On-node scripts CAN upload directly (`gcloud storage cp gs://provable-logs-results/…`) under the attached instance SA. No workflow today uses this — uploads still run from the STM/laptop. See `test_suites/single-region-tests/terraform/iam.tf` for the binding.

### When uploads happen

| Caller | When |
|--------|------|
| `scripts/bin/run-test.sh` | After every test completes |
| `scripts/bin/collect-logs.sh` | Standalone log collection |
| `scripts/bin/run-utility.sh` | When utility is `upload_logs_to_gcs` |
| `scripts/bin/destroy.sh` | EXIT trap during teardown |
| `scripts/lib/common.sh` | EXIT trap on any script failure |

### Override bucket name

```bash
export RESULTS_AND_LOGS_BUCKET="my-custom-bucket"
```

Default: `provable-logs-results` (set in `common.sh:68`).

### Viewing logs

```bash
# List runs
gcloud storage ls gs://provable-logs-results/manual_test_runs/$USER/

# Download a specific run
gcloud storage cp -r gs://provable-logs-results/manual_test_runs/$USER/<RUN_ID>/ ./log_files/

# Browse in console
open "https://console.cloud.google.com/storage/browser/provable-logs-results/manual_test_runs/$USER/"
```

### Cloud Logging (Ops Agent)

In addition to GCS log files, the Google Ops Agent on each node streams snarkOS journald logs to Cloud Logging with labels:

```bash
gcloud logging read \
  'labels.test_suite="single-region-tests" AND labels.commit_id="<hash>"' \
  --project=protocol-development-sandbox --limit=10
```

---

## Documentation Cross-References

### High-Level Concepts

| Concept | Where to Learn |
|---|---|
| Cloud strategy (GCP vs AWS) | `DEPLOYMENT_PATTERNS.md` § 1 |
| Three-phase deployment | `DEPLOYMENT_PATTERNS.md` § 2 |
| IaC stacking (Packer → Terraform → Ansible) | `DEPLOYMENT_PATTERNS.md` § 3 |
| Naming conventions | `DEPLOYMENT_PATTERNS.md` § 4 |
| Dynamic inventory | `DEPLOYMENT_PATTERNS.md` § 5 |
| Test suite abstraction | `DEPLOYMENT_PATTERNS.md` § 6 |
| Variable precedence | `DEPLOYMENT_PATTERNS.md` § 7 |
| Firewall patterns | `DEPLOYMENT_PATTERNS.md` § 8 |
| Log collection & GCS | `DEPLOYMENT_PATTERNS.md` § 9 |
| STM automation (pueue-based) | `DEPLOYMENT_PATTERNS.md` § 10 |

### Detailed References

| Component | Where to Reference |
|---|---|
| GCP Terraform modules | `ARCHITECTURE.md` → "GCP Single-Region-Tests" |
| Ansible playbooks | `ARCHITECTURE.md` → "Ansible Structure" |
| Stress Testing Manager | `ARCHITECTURE.md` → "Stress Testing Manager (STM)" and `stress-testing-manager/README.md` |
| Packer configuration | `packer/README.md` and `ARCHITECTURE.md` → "Packer (Base Image Builder)" |
| Log analysis stack | `ARCHITECTURE.md` → "Log Analysis Stack" |
| GCS buckets & IAM | `ARCHITECTURE.md` → "Shared Infrastructure" |

### Step-by-Step Procedures

| Task | Where to Follow |
|---|---|
| Provision & run a test | `COMMON_WORKFLOWS.md` → "Provision & Run a GCP Test" |
| SSH into a node | `COMMON_WORKFLOWS.md` → "SSH Into a Node" |
| Run Ansible playbooks | `COMMON_WORKFLOWS.md` → "Run a Specific Ansible Playbook Manually" |
| Modify Terraform | `COMMON_WORKFLOWS.md` → "Modify Terraform Configuration" |
| Add new instance type | `COMMON_WORKFLOWS.md` → "Add a New Instance Type" |
| Add firewall rule | `COMMON_WORKFLOWS.md` → "Add a New Firewall Rule" |
| Create new test | `COMMON_WORKFLOWS.md` → "Add a New Test" |
| Manage the STM | `stress-testing-manager/README.md` (provision, setup, update, destroy) |
| Analyze results | `COMMON_WORKFLOWS.md` → "Analyze Test Results" |
| Troubleshoot | `COMMON_WORKFLOWS.md` → "Troubleshooting" |

---

## Quick Access

### Operators' Toolkit

Save these as bookmarks:

```bash
# Quick reference
docs/QUICK_REFERENCE.md

# Run a test (full pipeline)
test_suites/single-region-tests/scripts/full_run.sh --mode=light --tests=swap_ledgers

# Get node status
gcloud compute ssh <instance> -- 'curl http://localhost:3030/testnet/block/height/latest'

# Download logs
gcloud storage cp -r "gs://provable-logs-results/manual_test_runs/$(whoami)/" ./logs/

# Stress Testing Manager control
stress-testing-manager/infrastructure/tf_stack.sh output
stress-testing-manager/infrastructure/tf_stack.sh update --update-target both
```

### Engineers' Toolkit

Save these as references:

```bash
# Architecture overview
docs/ARCHITECTURE.md

# Terraform patterns
test_suites/single-region-tests/terraform/main.tf
test_suites/single-region-tests/terraform/variables.tf

# Ansible patterns
test_suites/single-region-tests/playbooks/setup.yml
test_suites/single-region-tests/inventory/dynamic_inventory.gcp.yaml

# Configuration profiles
test_suites/single-region-tests/terraform/light.tfvars
test_suites/single-region-tests/terraform/heavy.tfvars

# Script architecture
test_suites/single-region-tests/scripts/full_run.sh
test_suites/single-region-tests/scripts/lib/common.sh
```

---

## When to Load the Skill

### ✅ Load the skill for:
- Questions about infrastructure design
- Modifying Terraform/Ansible
- Understanding architecture
- Adding new components
- Troubleshooting failures

### ❌ Don't need the skill for:
- Running standard workflows (use `docs/QUICK_REFERENCE.md`)
- One-off SSH commands
- Simple status checks

---

## Example Interactions

### "I want to add a new analytics instance to the GCP network"

1. Load skill: `/skill snarkos-stress-testing`
2. Ask: "How do I add a new analytics instance type to the GCP Terraform configuration?"
3. Skill will reference: `docs/ARCHITECTURE.md` and `docs/COMMON_WORKFLOWS.md`
4. Follow the step-by-step procedure

### "The network won't sync. What should I check?"

1. Load skill: `/skill snarkos-stress-testing`
2. Ask: "Network won't sync. Where should I start debugging?"
3. Skill will reference: `docs/COMMON_WORKFLOWS.md` → "Troubleshooting"
4. Follow the checklist

### "How do I run the swap_ledgers test?"

1. No need to load skill — reference `test_suites/single-region-tests/RUN_TEST_SUITE.md` directly
2. Or: `docs/COMMON_WORKFLOWS.md` → "Provision & Run a GCP Test"
3. Quick: `cd test_suites/single-region-tests && scripts/full_run.sh --mode=light --tests=swap_ledgers`

---

## Key Files & Directories

| Path | Purpose |
|---|---|
| `docs/` | Comprehensive engineering documentation (start here) |
| `test_suites/single-region-tests/` | GCP primary test suite |
| `test_suites/network-sync-tests/` | AWS secondary test suite |
| `stress-testing-manager/` | Central automation (GCE-based; pueue task queue on GCP) |
| `packer/` | Base image builder |
| `scripts/` | Operational utilities |
| `log_analysis_scripts/` | Post-run analysis tools |

---

## Linting & Validation

Always lint before committing. Preferred tools by file type:

### All-in-one

```bash
# Run the full lint suite (ansible-lint across all playbooks/roles)
LINT_PYTHON=python3.13 bash lint.sh
```

### Terraform

```bash
cd test_suites/single-region-tests/terraform

terraform fmt -check -recursive    # formatting
terraform validate                 # syntax + provider schema
terraform plan -var="owner=test" -var-file=light.tfvars  # full plan
```

### Ansible

```bash
# Lint all playbooks (uses .ansible-lint config)
LINT_PYTHON=python3.13 bash lint.sh

# Syntax-check a single playbook
ansible-playbook --syntax-check playbooks/setup.yml

# Dry-run (check mode) against live inventory
ansible-playbook playbooks/setup.yml -i inventory/dynamic_inventory.gcp.yaml --check
```

### Shell scripts

```bash
# shellcheck individual scripts
shellcheck scripts/full_run.sh
shellcheck scripts/bin/*.sh
shellcheck scripts/lib/*.sh

# Or via pre-commit
pre-commit run shellcheck --all-files
```

### Packer

```bash
cd packer
packer validate stress-test-base.pkr.hcl
packer fmt -check stress-test-base.pkr.hcl
```

### YAML

```bash
yamllint -c .yamllint.yaml playbooks/setup.yml
```

### Pre-commit (runs all hooks)

```bash
pre-commit run --all-files
```

Hooks configured in `.pre-commit-config.yaml`: ansible-lint, shellcheck, yamllint.

---

## Further Reading

- **Project README:** `README.md` (project overview)
- **Linting & Pre-commit:** `.pre-commit-config.yaml` (ansible-lint, shellcheck)
- **Configuration:** `.gitignore`, `.yamllint.yaml`, `.typos.toml`

---

## Support & Feedback

- Questions about the framework? Check `docs/README.md` first
- Issues with a procedure? Reference `docs/COMMON_WORKFLOWS.md`
- Need detailed architecture info? Read `docs/ARCHITECTURE.md`
- Quick answer needed? Use `docs/QUICK_REFERENCE.md`

Load the skill (`/skill snarkos-stress-testing`) for complex questions or architectural guidance.

---

**Last updated:** 2026-07-06
**Documentation version:** 2.1.0

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
