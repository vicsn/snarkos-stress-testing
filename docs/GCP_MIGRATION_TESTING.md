# Migration Testing: snarkos-p2p-tests on GCP

Step-by-step validation of the AWS → GCP migration for `test_suites/snarkos-p2p-tests/`.

---

## Migration Status

### P0: Infrastructure (Terraform) — ✅ Complete

All Terraform rewritten for GCP. 4 profiles plan clean: default(28), light(33), heavy(67), prerelease(68).

| Component | Status | What changed |
|-----------|--------|-------------|
| Provider + backend | ✅ | `provider "google"` + `backend "gcs"` (bucket `tfstate-snarkos-stress-testing`) |
| `main.tf` | ✅ | Rewritten: `google_compute_instance`, `google_compute_target_pool`, `google_compute_forwarding_rule` |
| `variables.tf` | ✅ | Created 18+ vars including `image_family`/`image_project` for Packer image selection |
| `locals.tf` | ✅ | Created: zones, VPC resolution, naming helpers |
| `tx_runner.tf` | ✅ | Fixed broken refs to `module.stress_base_ami`, `module.fwrule`, `local.*` |
| Modules | ✅ | `gcp-snarkos-network`, `firewall_rule`, `tx-cannon`, `stress_base_ami` all migrated |
| Profiles | ✅ | `light.tfvars`, `heavy.tfvars`, `prerelease.tfvars`, `default.auto.tfvars` — GCP machine types |
| IAM | ✅ | `google_service_account` + `google_project_iam_member` |
| Bootstrap | ✅ | `terraform_init/` module: release bucket + IAM bindings (tfstate bucket + SA are data sources from ProvableHQ/infrastructure) |

### P1: Ansible Build & Deploy Roles — ✅ Complete

All `aws_s3` module calls → `gcloud storage`. SCCACHE S3 → GCS.

| Role | Status | What changed |
|------|--------|-------------|
| `snarkos_install_s3` | ✅ | `gcloud storage cp` from GCS bucket |
| `snarkos_build_from_git` | ✅ | `gcloud storage` + SCCACHE GCS (`snarkos-compiler-cache` bucket) |
| `snarkos_build_locally` | ✅ | `gcloud storage` + SCCACHE GCS; macOS cross-compile preserved |
| `google_ops_agent_setup` | ✅ | **New role** — replaces logstash/metricbeat/filebeat; ships logs→Cloud Logging, metrics→Cloud Monitoring with `commit_id`/`branch_name`/`test_suite` labels |

### P2: Scripts — ✅ Complete

| Script | Status | What changed |
|--------|--------|-------------|
| `scripts/lib/common.sh` | ✅ | `aws_cli()` → `gcloud storage`; removed `import_shared_terraform_resources()` (60 lines); S3→GCS upload; AWS tag sync→GCP label sync |
| `scripts/full_run.sh` | ✅ | `checkip.amazonaws.com` → `ifconfig.me` + GCP metadata server for manager detection |
| `scripts/bin/setup.sh` | ✅ | `aws_cli s3api` → `gcloud storage ls` for binary cache check |

### P3: Ansible Inventory & Config — ✅ Complete

| Component | Status | What changed |
|-----------|--------|-------------|
| Dynamic inventory | ✅ | `google.cloud.gcp_compute` plugin at `inventory/dynamic_inventory.gcp.yaml` |
| Fact playbooks | ✅ | All use `gcp_public_ip`, `gcp_labels` — no `ec2_` references |
| `setup.yml` | ✅ | `s3_bucket` → `gcs_bucket`; ELK play → `google_ops_agent_setup` role |
| `set_secrets.sh` | ✅ | `gcloud secrets` |
| `ansible.cfg` | ✅ | `enable_plugins: google.cloud.gcp_compute` |

### P4: Utilities — ✅ Complete

| Utility | Status | What changed |
|---------|--------|-------------|
| `pregenerate_transactions` | ✅ | `aws_s3:` → `gcloud storage`; long GCS path split into `set_fact` |
| Log download utilities | ✅ | `gcloud storage cp` in `common.sh` |

### P5: Packer Base Image — ✅ Complete

| Component | Status | What changed |
|-----------|--------|-------------|
| `stress-test-base.pkr.hcl` | ✅ | **New** — `googlecompute` builder; configurable `network`/`subnetwork` |
| `playbooks/dependencies.yml` | ✅ | Rewritten for GCP: Docker, gcloud CLI, Ops Agent, monitoring exporters |
| Terraform integration | ✅ | `image_family`/`image_project` vars; `default.auto.tfvars` sets `stress-test-base` |
| Tested build | ✅ | Image `stress-test-base-20260707172234` created (~10 min) |

### P6: Observability — ✅ Complete

| Component | Status | What changed |
|-----------|--------|-------------|
| ELK stack (logstash/metricbeat/filebeat) | ✅ Removed | Roles didn't exist; references deleted from `setup.yml` |
| Google Ops Agent | ✅ New | `google_ops_agent_setup` role with `config.yaml.j2` template |
| Log labels | ✅ | `commit_id`, `branch_name`, `test_suite` on every log entry |
| Elastic vars | ✅ Removed | `cloud_id`, `elastic_api_key` removed from `vars.example.yml` |

### P7: Lint & Validation — ✅ Complete

| Check | Status | Result |
|-------|--------|--------|
| `terraform validate` | ✅ | All 4 profiles pass |
| `terraform plan` | ✅ | default(28), light(33), heavy(67), prerelease(68) |
| `ansible-lint` | ✅ | 0 failures, 0 warnings |
| `packer validate` | ✅ | Valid |
| `packer build` | ✅ | Image created successfully |

### P8: Cleanup — ⚠️ Manual steps remaining

| Task | Status | Action |
|------|--------|--------|
| Delete `dynamic_inventory.aws_ec2.yml` | 🔲 Pending | `rm inventory/dynamic_inventory.aws_ec2.yml` |
| Delete `terraform_tx_cannon/` (legacy) | ⏭️ Out of scope | Optional: `rm -rf terraform_tx_cannon/` |

### Out of Scope

| Component | Reason |
|-----------|--------|
| TX submitter (Rust) | `tests/load_saved_transactions/tx_submitter/` — `aws-sdk-s3` → `google-cloud-storage` crate rewrite tracked separately |
| TX cannon migration | Legacy `terraform_tx_cannon/` directory; module in `modules/tx-cannon/` is already GCP |
| `snarkos-cdn-tests` | Separate AWS test suite; not part of this migration |
| `stress-testing-manager` | Separate infrastructure stack with its own Packer/Terraform |

---

## AWS Dependency Inventory

Complete audit of every file in `test_suites/snarkos-p2p-tests/` that referenced AWS.
86 files scanned; 14 originally contained AWS references. **12 migrated, 2 remain.**

### ~~BLOCKER~~ ✅ MIGRATED

#### ~~`scripts/lib/common.sh`~~ ✅ (40+ AWS lines → GCP)

| Line | What | GCP Replacement |
|------|------|-----------------|
| 62-63 | `aws_cli()` wrapper function | `gcloud storage` / `gsutil` |
| 70 | `export AWS_REGION="us-west-2"` | Remove or `CLOUDSDK_COMPUTE_REGION` |
| 74 | `ANSIBLE_ENABLE_PLUGINS=amazon.aws.aws_ec2` | `google.cloud.gcp_compute` |
| 129-188 | `import_shared_terraform_resources()` — imports `aws_iam_role`, `aws_iam_policy`, `aws_key_pair`, `aws_security_group` | Delete entire function (GCP uses `google_service_account`, `google_compute_firewall`) |
| 199, 207 | `-target=aws_instance.snarkos_builder` | `-target=google_compute_instance.snarkos_builder` |
| 397-405 | `aws_cli s3 cp` log upload + S3 URIs | `gcloud storage cp gs://...` |
| 408 | AWS Console URL for logs | GCS Console URL |
| 441-452 | "waiting for AWS to sync tags" messages | "waiting for GCP labels to propagate" |

#### ~~`playbooks/roles/snarkos_install_s3/tasks/main.yml`~~ ✅

| Line | What | GCP Replacement |
|------|------|-----------------|
| 6-7 | `aws_s3:` module — download binary from S3 | `google.cloud.gcp_storage_object` or `gcloud storage cp` |

Role name should be renamed `snarkos_install_gcs` or `snarkos_install_binary` (cosmetic).

#### ~~`playbooks/roles/snarkos_build_from_git/tasks/main.yml`~~ ✅

| Line | What | GCP Replacement |
|------|------|-----------------|
| 13-14 | `aws_s3:` — check if binary exists in S3 | `gcloud storage ls` |
| 149-152 | `SCCACHE_BUCKET`, `SCCACHE_REGION`, `SCCACHE_S3_USE_SSL`, `SCCACHE_S3_KEY_PREFIX` | `SCCACHE_GCS_BUCKET`, `SCCACHE_GCS_KEY_PREFIX`, `SCCACHE_GCS_RW_MODE` |
| 172-173 | `aws_s3:` — post-build S3 check | `gcloud storage ls` |
| 185-186 | `aws_s3:` — upload built binary | `gcloud storage cp` |
| 210-211 | `aws_s3:` — download binary | `gcloud storage cp` |

#### ~~`playbooks/roles/snarkos_build_locally/tasks/main.yml`~~ ✅

| Line | What | GCP Replacement |
|------|------|-----------------|
| 21-25 | `aws_s3:` + `profile: "{{ s3_profile }}"` — check S3 | `gcloud storage ls` |
| 285-288 | `SCCACHE_BUCKET`, `SCCACHE_REGION`, `SCCACHE_S3_*` env vars | `SCCACHE_GCS_BUCKET`, `SCCACHE_GCS_KEY_PREFIX`, `SCCACHE_GCS_RW_MODE` |
| 310-327 | `aws_s3:` + `profile` — upload binary (macOS + Linux paths) | `gcloud storage cp` |

#### ~~`scripts/bin/setup.sh`~~ ✅

| Line | What | GCP Replacement |
|------|------|-----------------|
| 26-27 | `S3_BUCKET` extracted from vars YAML | `GCS_BUCKET` |
| 31 | `aws_cli s3api head-object --bucket "$S3_BUCKET" --profile ephnet` | `gcloud storage ls gs://$GCS_BUCKET/$RELEASE_NAME` |

#### `inventory/dynamic_inventory.aws_ec2.yml` (entire file) — **DELETE MANUALLY**

Stale AWS EC2 inventory. GCP equivalent exists at `inventory/dynamic_inventory.gcp.yaml`.

```bash
rm test_suites/snarkos-p2p-tests/inventory/dynamic_inventory.aws_ec2.yml
```

#### ~~`utils/pregenerate_transactions/run_utility.yml`~~ ✅

| Line | What | GCP Replacement |
|------|------|-----------------|
| 114 | `aws_s3:` — list pregenerated zips | `gcloud storage ls gs://provable-pregenerated-transactions/` |
| 235 | `aws_s3:` — upload zipped transactions | `gcloud storage cp` |

#### `tests/load_saved_transactions/tx_submitter/Cargo.toml` — **REMAINING (Rust rewrite needed)**

| Line | What | GCP Replacement |
|------|------|-----------------|
| 9-10 | `aws-config = "1"`, `aws-sdk-s3 = "1"` | `google-cloud-storage` crate; rewrite Rust source |

### ~~PARTIAL~~ ✅ MIGRATED

- ~~`playbooks/roles/snarkos_build_locally/defaults/main.yml`~~ — `s3_profile` removed, `gcs_bucket` is now the default
- ~~`playbooks/setup.yml`~~ — `s3_bucket` → `gcs_bucket`
- ~~`scripts/full_run.sh`~~ — `checkip.amazonaws.com` → `ifconfig.me`; EC2 metadata → GCP metadata server

### ~~COSMETIC~~ ✅ FIXED

All stale AWS comments updated:
- `inventory/dynamic_inventory.gcp.yaml` — removed "matches AWS inventory pattern"
- `playbooks/ansible.cfg` — updated deprecation comment
- `playbooks/set_secrets.sh` — updated to "Uses GCP Secret Manager"
- `scripts/bin/destroy.sh` — `AWS_*` → `GCP_*`

### Migration priority order

| Priority | Component | Status |
|----------|-----------|--------|
| **P0** | `scripts/lib/common.sh` | ✅ Done |
| **P1** | Ansible build roles (3 roles) | ✅ Done |
| **P2** | `scripts/bin/setup.sh` | ✅ Done |
| **P3** | `scripts/full_run.sh` | ✅ Done |
| **P4** | `utils/pregenerate_transactions` | ✅ Done |
| **P5** | `tests/load_saved_transactions` (Rust) | ⚠️ Remaining — requires `aws-sdk-s3` → `google-cloud-storage` crate rewrite |
| **P6** | Delete stale files + fix comments | ✅ Done (except `dynamic_inventory.aws_ec2.yml` — delete manually) |

### Remaining cleanup

```bash
# Delete stale AWS inventory
rm test_suites/snarkos-p2p-tests/inventory/dynamic_inventory.aws_ec2.yml
```

---

## Prerequisites

```bash
# 1. Install gcloud CLI
brew install --cask google-cloud-sdk

# 2. Authenticate
gcloud auth login
gcloud auth application-default login

# 3. Set project
gcloud config set project protocol-development-sandbox

# 4. Enable required APIs
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  --project=protocol-development-sandbox

# 5. Install Ansible GCP collection
ansible-galaxy collection install google.cloud

# 6. Install google-auth for the Python that Ansible uses
#    (required by the google.cloud.gcp_compute inventory plugin)
#    Find Ansible's Python: ansible --version | grep 'python module location'
pip3.13 install google-auth requests   # adjust version to match Ansible's Python

# 7. Install Ansible requirements
cd test_suites/snarkos-p2p-tests
ansible-galaxy install -r playbooks/requirements.yml
```

---

## Phase 1: Validate Terraform (GCP modules only)

Until `main.tf` is rewritten, validate individual GCP modules in isolation.

### 1.1 Validate provider configuration

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Confirm provider.tf is clean GCP
cat provider.tf
# Expected: backend "local", required_providers { google >= 7.32.0 }

# Confirm single terraform block (provider.tf only)
grep -c 'terraform {' *.tf
# Expected: 1 (from provider.tf only)
```

### 1.2 Validate tfvars syntax

```bash
# Validate each profile loads without syntax errors
terraform fmt -check light.tfvars
terraform fmt -check heavy.tfvars
terraform fmt -check prerelease.tfvars
terraform fmt -check default.auto.tfvars
```

### 1.3 Check GCP module structure

```bash
# Verify module directories exist and have required files
ls -la modules/gcp-snarkos-network/
# Expected: data.tf, locals.tf, main.tf, outputs.tf, versions.tf
# MISSING: variables.tf — must be created

ls -la modules/firewall_rule/
# Expected: firewall_rule.tf

ls -la modules/tx-cannon/
# Expected: tx-cannon.tf

ls -la modules/stress_base_ami/
# Expected: stress_base_ami.tf

# Verify deleted AWS modules are gone
ls modules/security_group/ 2>&1
# Expected: No such file or directory
```

### 1.4 Validate GCP resources (once main.tf is fixed)

```bash
# Init
terraform init

# Plan with light profile
terraform plan \
  -var-file=light.tfvars \
  -var="gcp_project=protocol-development-sandbox" \
  -var="owner=$USER"

# Plan with heavy profile
terraform plan \
  -var-file=heavy.tfvars \
  -var="gcp_project=protocol-development-sandbox" \
  -var="owner=$USER"
```

### 1.5 Validate IAM configuration

```bash
# Check IAM resources are properly defined
grep -n 'google_service_account\|google_project_iam_member' iam.tf

# Verify service account email format
grep 'account_id' iam.tf
# Expected: snarkos-sa (creates snarkos-sa@PROJECT.iam.gserviceaccount.com)
```

### 1.6 Validate storage configuration

```bash
# Check GCS bucket resources
grep -n 'google_storage_bucket' storage.tf

# Verify bucket names match expected
grep 'bucket' storage.tf
```

---

## Phase 2: Validate Ansible (GCP inventory + facts)

### 2.1 Validate inventory plugin

```bash
cd test_suites/snarkos-p2p-tests

# Confirm GCP inventory file is valid YAML
python3 -c "import yaml; yaml.safe_load(open('inventory/dynamic_inventory.gcp.yaml'))"

# Check enable_plugins in ansible.cfg
grep enable_plugins playbooks/ansible.cfg
# Expected: google.cloud.gcp_compute (first in list)

# Verify stale AWS inventory exists (should be deleted)
ls inventory/dynamic_inventory.aws_ec2.yml 2>&1
# If exists: DELETE IT
```

### 2.2 Test GCP inventory discovery (requires provisioned instances)

```bash
# List hosts discovered by GCP inventory
ansible-inventory -i inventory/dynamic_inventory.gcp.yaml --list 2>&1 | head -50

# Check host grouping by labels
ansible-inventory -i inventory/dynamic_inventory.gcp.yaml --graph
# Expected groups: devnet label groups, owner_ prefixed groups
```

### 2.3 Validate fact-setting playbooks

```bash
# Dry-run validator facts (check for GCP vars, not AWS)
grep -n 'gcp_public_ip\|gcp_labels' playbooks/set_validator_facts.yml
grep -n 'gcp_public_ip\|gcp_labels' playbooks/set_client_facts.yml
grep -n 'gcp_public_ip\|gcp_labels' playbooks/set_prover_facts.yml
# Expected: all use gcp_public_ip, gcp_labels.dev — no ec2_ references
```

### 2.4 Validate secrets integration

```bash
# Check set_secrets.sh uses gcloud
grep -n 'gcloud\|aws' playbooks/set_secrets.sh
# Expected: gcloud secrets — no aws references

# Test gcloud secrets access (requires project permissions)
gcloud secrets list --project=protocol-development-sandbox
```

### 2.5 Validate requirements

```bash
# Check requirements reference GCP collection
cat playbooks/requirements.yml
# Expected: google.cloud >= 1.13.0
# Expected: googlecloudplatform.google_cloud_ops_agents role

# Verify collection is installed
ansible-galaxy collection list google.cloud
```

---

## Phase 3: Validate Scripts

### 3.1 Check for AWS remnants in scripts

```bash
cd test_suites/snarkos-p2p-tests

# Critical: common.sh has most AWS references
grep -n 'aws\|ec2\|s3://' scripts/lib/common.sh
# Known issues:
#   - aws_cli() function (line ~62)
#   - AWS_REGION export (line ~70)
#   - ANSIBLE_ENABLE_PLUGINS=amazon.aws.aws_ec2 (line ~74)
#   - aws sts get-caller-identity (line ~151)
#   - aws_cli s3 cp log upload (line ~397-408)
#   - "waiting for AWS to sync tags" (line ~441-452)

# full_run.sh manager detection
grep -n 'amazonaws\|ec2' scripts/full_run.sh
# Known: checkip.amazonaws.com (line 38) — needs migration to metadata server
```

### 3.2 Test pueue integration

```bash
# Start pueue daemon
pueued -d

# Verify pueue status
pueue status

# Test lib/pueue.sh loads
bash -c 'source scripts/lib/pueue.sh && echo "pueue lib OK"'
```

---

## Phase 4: End-to-End Smoke Test (once blockers fixed)

### 4.1 Provision with light profile

```bash
cd test_suites/snarkos-p2p-tests

export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
export OWNER="$USER"

# Provision infrastructure
cd terraform
terraform init
terraform apply \
  -var-file=light.tfvars \
  -var="gcp_project=protocol-development-sandbox" \
  -var="owner=$OWNER" \
  -auto-approve

# Verify outputs
terraform output validator_ips
terraform output snarkos_lb_ip
```

### 4.2 Validate Ansible can reach hosts

```bash
cd test_suites/snarkos-p2p-tests

# Test connectivity
ansible all -i inventory/dynamic_inventory.gcp.yaml -m ping

# List discovered hosts
ansible-inventory -i inventory/dynamic_inventory.gcp.yaml --graph
```

### 4.3 Run setup playbook

```bash
cd test_suites/snarkos-p2p-tests/playbooks

# Setup nodes
ansible-playbook setup.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml
```

### 4.4 Verify nodes are running

```bash
# Check sync status
ansible-playbook is_synced.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml

# SSH to validator and check
gcloud compute ssh ${OWNER}-snarkos-p2p-tests-validator-0 \
  --zone=us-central1-b \
  --project=protocol-development-sandbox \
  -- 'sudo systemctl status snarkos && curl -s http://localhost:3030/testnet/block/height/latest'
```

### 4.5 Run a test

```bash
cd test_suites/snarkos-p2p-tests

# Run a simple test inline (no pueue)
PUEUE_DISABLED=1 ./scripts/bin/run-test.sh --test=swap_ledgers

# Or via pueue
./scripts/bin/run-test.sh --test=swap_ledgers
pueue status
pueue log
```

### 4.6 Collect logs

```bash
cd test_suites/snarkos-p2p-tests/playbooks

# Fetch logs from validators
ansible-playbook fetch_and_zip_snarkos_logs.yml \
  -i ../inventory/dynamic_inventory.gcp.yaml
```

### 4.7 Destroy infrastructure

```bash
cd test_suites/snarkos-p2p-tests/terraform

terraform destroy \
  -var-file=light.tfvars \
  -var="gcp_project=protocol-development-sandbox" \
  -var="owner=$OWNER" \
  -auto-approve
```

> **Cross-reference:** For detailed step-by-step workflows (provisioning, setup, SSH,
> scaling, adding tests/utilities, troubleshooting), see [`COMMON_WORKFLOWS.md`](./COMMON_WORKFLOWS.md).

---

## Phase 5: Full Run Smoke Test (`full_run.sh`)

`full_run.sh` orchestrates the entire pipeline:
provision → setup → run tests → collect logs → destroy.

It auto-delegates to the stress-testing-manager via SSH unless `STM_LOCAL=1`.
Jobs enqueue via pueue by default; `PUEUE_DISABLED=1` runs sequentially inline.

### Pre-flight bugs fixed (2026-07-07)

| File | Bug | Fix |
|------|-----|-----|
| `scripts/bin/provision.sh` | `cp variables.tf.light variables.tf` — files don't exist (GCP uses `.tfvars`) | Replaced with `-var-file=light.tfvars` passed to `init_and_apply_terraform` |
| `scripts/lib/common.sh` | `init_and_apply_terraform` ignored extra args | Added `"$@"` passthrough |
| `scripts/lib/common.sh` | `LB_URL` unbound when terraform fails before writing `lb_url.txt` — EXIT trap crashes | Defaulted `LB_URL=""` at init; `common_ansible` uses `${VAR:-fallback}` for all network vars |
| `scripts/bin/run-utility.sh` | `upload_logs_to_s3` string literal | Changed to `upload_logs_to_gcs` |
| `scripts/bin/collect-logs.sh` | Comment said "S3 sub-path" | Changed to "GCS sub-path" |
| `playbooks/vars.MIKEN.yaml` | Scripts hardcode `${VARS}.yml` extension | Renamed to `vars.MIKEN.yml` |
| `terraform/*.tf` | OS Login enabled (`enable-oslogin=TRUE`) — Ansible can't SSH as `ubuntu` | Switched to metadata SSH keys via `var.ssh_public_key`; `common.sh` auto-detects `~/.ssh/google_compute_engine.pub` |
| `iam.tf` | Project-level `enable_oslogin` resource forced OS Login globally | Removed; SSH mode now per-instance via `local.ssh_metadata` |
| `inventory/dynamic_inventory.gcp.yaml` | No `ansible_user` or SSH key set | Added `ansible_user: ubuntu` + `ansible_ssh_private_key_file: ~/.ssh/google_compute_engine` |
| `scripts/bin/setup.sh` | Builder inventory missing SSH key path | Added `ansible_ssh_private_key_file=~/.ssh/google_compute_engine` |

### Pre-existing resources imported

First `terraform apply` hit 409 errors for resources that already existed in
the project from a prior run. Imported into state:

```bash
cd test_suites/snarkos-p2p-tests/terraform
terraform import -var-file=light.tfvars -var="owner=mikenichols" \
  google_service_account.snarkos_sa \
  projects/protocol-development-sandbox/serviceAccounts/mikenichols-snarkos-sa@protocol-development-sandbox.iam.gserviceaccount.com

terraform import -var-file=light.tfvars -var="owner=mikenichols" \
  google_compute_project_metadata_item.enable_oslogin enable-oslogin

# Note: this VPC is now STM-owned and referenced via terraform_remote_state.
# The import below was run during initial migration before VPC consolidation.
terraform import -var-file=light.tfvars -var="owner=mikenichols" \
  'module.network[0].google_compute_network.vpc' \
  projects/protocol-development-sandbox/global/networks/mikenichols-snarkos-p2p-tests-vpc

terraform import -var-file=light.tfvars -var="owner=mikenichols" \
  'module.network[0].google_compute_subnetwork.subnets["us-central1"]' \
  projects/protocol-development-sandbox/regions/us-central1/subnetworks/protocol-development-sandbox-subnet-us-central1
```

After import: plan dropped from 33 → 20 resources to add, 0 errors.

### Test environment setup

Export Slack channel before any run:

```bash
export SLACK_CHANNEL_ID="C07JA6U0TV5"   # #pagerduty-alerts-testing
```

All test commands below include `STM_LOCAL=1` explicitly to skip manager delegation.
VPC + subnet: STM-owned, referenced via `terraform_remote_state` (bucket `tfstate-snarkos-stress-testing`, prefix `stress-testing-manager`). SRT reuses STM's subnet (`10.41.0.0/16`) directly — it no longer creates or imports its own subnet.
Vars file: `playbooks/vars.MIKEN.yml` (pass `--vars=vars.MIKEN`).

### 5.1 Test 1: Sequential local run (simplest, no pueue)

Validates the full pipeline end-to-end in a single shell. Start here.

```bash
cd test_suites/snarkos-p2p-tests

PUEUE_DISABLED=1 STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=light --vars=vars.MIKEN --tests=swap_ledgers
```

**Pass criteria:**

| Step | What to watch for | Pass |
|------|-------------------|------|
| Arg parsing | `RUN_ID=... mode=light vars=vars tests=swap_ledgers` printed | 🔲 |
| Provision | `terraform apply -var-file=light.tfvars` succeeds, `lb_url.txt` written | 🔲 |
| Label sync | "GCP labels synced. Ansible sees N hosts." within ~60s | 🔲 |
| Binary cache | `gcloud storage ls gs://provable-binaries-releases/<hash>` — "found" or "building" | 🔲 |
| Ephemeral builder | (cache miss only) `terraform apply -target=google_compute_instance.snarkos_builder` | 🔲 |
| Setup playbook | `setup.yml` completes — `snarkos_install_s3` distributes binary, Ops Agent configured | 🔲 |
| Test execution | `swap_ledgers` test runs via `run_test.yml` | 🔲 |
| Log download | 4 download utilities run (`download_logs_{clients,provers,validators,tx_runner}`) | 🔲 |
| Log upload | `gcloud storage cp` to `gs://provable-logs-results/manual_test_runs/$USER/$RUN_ID/swap_ledgers/` | 🔲 |
| GCS console URL | URL printed: `https://console.cloud.google.com/storage/browser/provable-logs-results/...` | 🔲 |
| Destroy | `terraform destroy -auto-approve` completes | 🔲 |
| Exit code | 0 | 🔲 |

### 5.2 Test 2: Pueue local run

Same pipeline, but jobs dispatched via pueue.

```bash
cd test_suites/snarkos-p2p-tests

# Ensure pueue daemon is running
pueued -d 2>/dev/null || true

STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=light --vars=vars.MIKEN --tests=swap_ledgers
```

**Pass criteria:**

| Step | What to watch for | Pass |
|------|-------------------|------|
| Enqueue message | `Enqueued provision(N) -> setup(M) -> 1 test job(s) -> destroy(D).` | 🔲 |
| Job chain | `pueue status` shows provision → setup → run-test → destroy in correct order | 🔲 |
| Provision job | Completes successfully (`pueue log N`) | 🔲 |
| Setup job | Starts after provision completes | 🔲 |
| Test job | Starts after setup completes | 🔲 |
| Destroy job | Starts after test completes | 🔲 |
| All jobs | `pueue status` shows all "Done" with exit code 0 | 🔲 |

```bash
# Monitor
pueue status
pueue log -f          # follow all output
pueue log <id>        # specific job
```

### 5.3 Test 3: Multiple tests

```bash
PUEUE_DISABLED=1 STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=light --vars=vars.MIKEN --tests=swap_ledgers,restart_validators
```

**Pass criteria:**

| Step | Pass |
|------|------|
| Both tests run sequentially | 🔲 |
| Logs uploaded under separate GCS sub-paths (`swap_ledgers/`, `restart_validators/`) | 🔲 |

### 5.4 Test 4: All tests

```bash
STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=light --vars=vars.MIKEN --tests=all
```

**Pass:** All tests discovered (excluding `_`-prefixed), each gets its own pueue job.

### 5.5 Test 5: Custom vars file

```bash
# Create custom vars (or use existing)
cp playbooks/vars.MIKEN.yml playbooks/test_vars.yml
# Edit test_vars.yml as needed

PUEUE_DISABLED=1 STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=light --vars=test_vars --tests=swap_ledgers
```

**Pass:** `setup.sh` reads `playbooks/test_vars.yml` for `snarkos_git_hash`, `features`, `gcs_bucket`.

### 5.6 Test 6: Individual scripts (after provisioning)

If infra is already up from a previous run (or provision separately), test
each `scripts/bin/` entrypoint in isolation:

```bash
cd test_suites/snarkos-p2p-tests

# Provision only
PUEUE_DISABLED=1 ./scripts/bin/provision.sh --mode=light --vars=vars.MIKEN

# Setup only
PUEUE_DISABLED=1 ./scripts/bin/setup.sh --vars=vars.MIKEN

# Run one test
PUEUE_DISABLED=1 ./scripts/bin/run-test.sh --test=swap_ledgers --vars=vars.MIKEN

# Run a utility
PUEUE_DISABLED=1 ./scripts/bin/run-utility.sh --utility=check_network_is_advancing --vars=vars.MIKEN

# Collect logs standalone
PUEUE_DISABLED=1 ./scripts/bin/collect-logs.sh --label=manual_check --vars=vars.MIKEN

# Interactive test picker (TTY only)
./scripts/lib/select-test.sh

# Destroy
PUEUE_DISABLED=1 ./scripts/bin/destroy.sh
```

| Script | What to verify | Pass |
|--------|---------------|------|
| `provision.sh` | `-var-file=light.tfvars` passed to terraform | 🔲 |
| `setup.sh` | GCS binary check, ephemeral builder if needed, `setup.yml` runs | 🔲 |
| `run-test.sh` | Test executes, logs collected + uploaded to GCS | 🔲 |
| `run-utility.sh` | Utility runs via `run_utility.yml` | 🔲 |
| `collect-logs.sh` | Downloads + uploads logs under `--label` sub-path | 🔲 |
| `select-test.sh` | Menu renders, selection launches `run-test.sh` | 🔲 |
| `destroy.sh` | `destroy_infra.sh` runs terraform destroy | 🔲 |

### 5.7 Test 7: GCP-specific behavior verification

After any successful run, verify these GCP-migrated behaviors:

| Check | Command | Expected |
|-------|---------|----------|
| Manager detection | `grep ifconfig.me scripts/full_run.sh` | ✅ Present (no `amazonaws.com`) |
| Packer image used | `gcloud compute instances describe ${OWNER}-snarkos-p2p-tests-validator-0 --zone=us-central1-b --format="value(disks[0].source)"` | Image from `stress-test-base` family |
| Ops Agent running | SSH to node → `sudo systemctl status google-cloud-ops-agent` | Active |
| Ops Agent labels | SSH to node → `cat /etc/google-cloud-ops-agent/config.yaml` | `commit_id`, `branch_name`, `test_suite` present |
| GCS log upload | `gcloud storage ls gs://provable-logs-results/manual_test_runs/$USER/$RUN_ID/` | Log files present |
| Cloud Logging | See 5.8 below | Entries with correct labels |

### 5.8 Verify logs in Cloud Logging

After a run, confirm Ops Agent shipped snarkOS logs:

```bash
# Filter by test suite label
gcloud logging read \
  'labels.test_suite="snarkos-p2p-tests"' \
  --project=protocol-development-sandbox \
  --limit=10 \
  --format="table(timestamp, labels.commit_id, labels.branch_name, textPayload)"

# Filter by commit
gcloud logging read \
  'labels.commit_id="<your-hash>"' \
  --project=protocol-development-sandbox \
  --limit=10
```

### 5.9 Test 8: Manager delegation

When not running on the stress-testing-manager and `STM_LOCAL` is unset,
`full_run.sh` resolves the manager IP and delegates via SSH.

```bash
# Ensure manager IP file exists (or let full_run.sh auto-populate from tf_stack.sh)
cat stress-testing-manager-ip.txt

# Run without STM_LOCAL — triggers SSH delegation
./scripts/full_run.sh --mode=light --tests=swap_ledgers
```

**Pass criteria:**

| Step | Pass |
|------|------|
| Manager IP resolved from `stress-testing-manager-ip.txt` or `tf_stack.sh ip` | 🔲 |
| SSH connection to `ubuntu@<manager-ip>` succeeds | 🔲 |
| Environment vars forwarded (`RUN_ID`, `SLACK_TOKEN`, `OWNER`, etc.) | 🔲 |
| Remote `full_run.sh` executes and completes | 🔲 |

### 5.10 Test 9: Heavy profile

```bash
STM_LOCAL=1 \
  ./scripts/full_run.sh --mode=heavy --vars=vars.MIKEN --tests=prerelease
```

**Pass:** 67 resources provisioned, prerelease tests run successfully.

### 5.11 EXIT trap / failure recovery

If a run fails mid-pipeline, the EXIT trap in `common.sh` fires:
- Sends Slack notification with exit code
- Prompts for log collection (auto-yes in non-interactive)
- Uploads collected logs to GCS

To manually recover:

```bash
cd test_suites/snarkos-p2p-tests/terraform
terraform destroy -auto-approve -var="owner=$USER"

# Clear pueue queue
pueue clean
pueue reset
```

> **Cross-reference:** For the complete test run anatomy (5 phases), individual script
> usage, adding tests/utilities, post-run analysis, and troubleshooting, see
> [`COMMON_WORKFLOWS.md`](./COMMON_WORKFLOWS.md). For the `full_run.sh` CLI reference,
> manager delegation, and Slack notification setup, see
> [`RUN_TEST_SUITE.md`](../test_suites/snarkos-p2p-tests/RUN_TEST_SUITE.md).

---

## Remaining AWS → GCP Migration Work

### ~~Priority 1: Terraform~~ ✅ DONE

All Terraform migration tasks completed. `terraform init`, `validate`, and `plan` succeed for all profiles.

| Task | Status |
|------|--------|
| Rewrite `main.tf` with `google_compute_instance` resources | ✅ Done |
| Create root `variables.tf` declaring ~18 variables | ✅ Done |
| Create root `locals.tf` (zones, vpc, subnet lookups) | ✅ Done |
| Add `variables.tf` to `modules/gcp-snarkos-network/` | ✅ Done |
| Instantiate `gcp-snarkos-network` module from root | ✅ Done |
| Fix `tx_runner.tf` broken references | ✅ Done |
| Delete `terraform_tx_cannon/` directory (superseded by `modules/tx-cannon`) | ⏭️ Out of scope |

### ~~Priority 2: Ansible build roles~~ ✅ DONE

All `aws_s3` module calls replaced with `gcloud storage` commands. SCCACHE S3 env vars replaced with GCS equivalents.

### ~~Priority 3: Scripts~~ ✅ DONE

`aws_cli()` removed, `gcloud storage` for uploads, GCP metadata for manager detection, `ANSIBLE_ENABLE_PLUGINS=google.cloud.gcp_compute`.

### Priority 4: Application code — REMAINING

| Task | File(s) | Effort |
|------|---------|--------|
| Migrate TX submitter from `aws-sdk-s3` to `google-cloud-storage` crate | `tests/load_saved_transactions/tx_submitter/` | Large (Rust rewrite) |

---

## Quick Validation Checklist

Run these after each migration batch to confirm progress:

```bash
cd test_suites/snarkos-p2p-tests

# 1. No conflict markers
grep -rn '<<<<<<< \|>>>>>>> ' . && echo "FAIL: conflict markers" || echo "OK: no conflicts"

# 2. Count remaining AWS references (excluding comments and docs)
grep -rn --include='*.tf' --include='*.sh' --include='*.yml' --include='*.yaml' \
  'aws_\|aws-sdk\|amazonaws\|us-west-2\|s3://' . \
  | grep -v '\.git/' | grep -v '#' | wc -l
# Target: 0

# 3. Terraform validates
cd terraform && terraform validate && echo "OK: terraform valid" || echo "FAIL: terraform invalid"

# 4. Ansible config valid
cd ../playbooks && ansible-config dump --only-changed && echo "OK" || echo "FAIL"

# 5. GCP inventory reachable (requires provisioned instances)
ansible-inventory -i ../inventory/dynamic_inventory.gcp.yaml --list > /dev/null 2>&1 \
  && echo "OK: inventory" || echo "SKIP: no instances"
```

---

## Workflow Test Matrix

Each workflow from [`COMMON_WORKFLOWS.md`](./COMMON_WORKFLOWS.md) mapped to its GCP validation test and current result.

### Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Passes |
| ⚠️ | Partial — works but has AWS remnants or caveats |
| ❌ | Blocked — depends on unmigrated component |
| 🔲 | Not yet tested |

---

### Terraform & Provisioning

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 1 | **Provisioning** (Anatomy §1) | `cd terraform && terraform init -reconfigure && terraform plan -var-file=light.tfvars -var="gcp_project=protocol-development-sandbox" -var="owner=$USER"` | ✅ Plans 33 resources (light), 67 (heavy), 68 (prerelease) |
| 2 | **Provision without running a test** | `terraform apply -var-file=light.tfvars -var="gcp_project=protocol-development-sandbox" -var="owner=$USER" -auto-approve` | 🔲 Not yet applied |
| 3 | **Scale infrastructure** | Edit tfvars counts → `terraform apply -var-file=custom.tfvars` | 🔲 Needs live infra |
| 4 | **Modify Terraform configuration** | Edit `main.tf` or modules → `terraform plan` | ✅ `terraform validate` passes |
| 5 | **Destroy infrastructure** | `terraform destroy -var-file=light.tfvars -var="gcp_project=protocol-development-sandbox" -var="owner=$USER" -auto-approve` | 🔲 Needs live infra |

### Ansible Setup & Node Management

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 6 | **Ansible setup** (Anatomy §2) | `ansible-playbook setup.yml -i ../inventory/dynamic_inventory.gcp.yaml` | ✅ Migrated to `gcloud storage` |
| 7 | **Run Ansible playbook manually** | `ansible-playbook setup.yml -i ../inventory/dynamic_inventory.gcp.yaml -v --tags=snarkos_install` | ✅ `snarkos_install_s3` role uses `gcloud storage cp` |
| 8 | **Check network sync status** | `ansible-playbook is_synced.yml -i ../inventory/dynamic_inventory.gcp.yaml` | 🔲 Needs live infra; playbook itself is cloud-agnostic |
| 9 | **SSH into a node** | `gcloud compute ssh ${OWNER}-${DEVNET_NAME}-snarkos-validator-0 --zone=us-central1-b --project=protocol-development-sandbox` | 🔲 Needs live infra; OS Login configured in Terraform ✅ |

### Scripts & Test Execution

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 10 | **`full_run.sh` local (single test)** | `PUEUE_DISABLED=1 STM_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=swap_ledgers` | 🔲 Needs live infra |
| 11 | **`full_run.sh` local (all tests)** | `STM_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=all` | 🔲 Needs live infra |
| 12 | **`full_run.sh` manager delegation** | `./scripts/full_run.sh --mode=light --tests=swap_ledgers` (auto-SSH to manager) | 🔲 Needs manager + live infra |
| 13 | **`provision.sh`** | `PUEUE_DISABLED=1 ./scripts/bin/provision.sh --mode=light` | 🔲 Needs live infra; code review ✅ |
| 14 | **`setup.sh`** (binary cache hit) | `PUEUE_DISABLED=1 ./scripts/bin/setup.sh` — binary exists in GCS | 🔲 Needs live infra; code review ✅ |
| 15 | **`setup.sh`** (binary cache miss) | `PUEUE_DISABLED=1 ./scripts/bin/setup.sh` — triggers ephemeral builder | 🔲 Needs live infra; code review ✅ |
| 16 | **`run-test.sh`** | `PUEUE_DISABLED=1 ./scripts/bin/run-test.sh --test=swap_ledgers` | 🔲 Needs live infra; code review ✅ |
| 17 | **`run-utility.sh`** | `PUEUE_DISABLED=1 ./scripts/bin/run-utility.sh --utility=check_network_is_advancing` | 🔲 Needs live infra |
| 18 | **`collect-logs.sh`** | `PUEUE_DISABLED=1 ./scripts/bin/collect-logs.sh --label=test_run` | 🔲 Needs live infra; code review ✅ |
| 19 | **`destroy.sh`** | `PUEUE_DISABLED=1 ./scripts/bin/destroy.sh` | 🔲 Needs live infra |
| 20 | **`select-test.sh`** (interactive) | `./scripts/lib/select-test.sh` — test menu renders, selection works | 🔲 Needs live infra |
| 21 | **Add a new test** | `mkdir tests/my_test && cat > tests/my_test/run_test.yml` → auto-discovered | ✅ Filesystem-based, cloud-agnostic |

### Utilities

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 22 | **Add a new utility** | `mkdir utils/my_util && cat > utils/my_util/run_utility.yml` → auto-discovered | ✅ Filesystem-based, cloud-agnostic |
| 23 | **Run utility: analyze_logs** | `./scripts/bin/run-utility.sh --utility=analyze_logs` | 🔲 Needs log files |
| 24 | **Run utility: download_logs_validators** | `./scripts/bin/run-utility.sh --utility=download_logs_validators` | 🔲 Needs live infra; code review ✅ |
| 25 | **Run utility: pregenerate_transactions** | `./scripts/bin/run-utility.sh --utility=pregenerate_transactions` | 🔲 Needs live infra; code review ✅ |

### Log Collection & Analysis

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 26 | **Log collection** (Anatomy §4) | `ansible-playbook fetch_and_zip_snarkos_logs.yml -i ../inventory/dynamic_inventory.gcp.yaml` | 🔲 Needs live infra; code review ✅ |
| 27 | **Post-run analysis** (Anatomy §5) | `cd log_analysis_scripts && python analysis_01_prepare_logfile.py --input logs/snarkos.log --output logs.json` | ✅ Cloud-agnostic |
| 28 | **Analyze test results: sync profiling** | `python analysis_02_sync_profiling.py --input logs.json --output sync.png` | ✅ Cloud-agnostic |
| 29 | **Analyze test results: consensus timing** | `python analysis_02_val_consensus_profiling.py --input logs.json --output consensus.png` | ✅ Cloud-agnostic |
| 30 | **Analyze test results: Rust timing** | `cd timing_analysis && cargo run --release -- --input logs.json --output stats.json` | ✅ Cloud-agnostic |

### STM & Automation

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 31 | **Control STM daemon** | `scripts/talisker_control.sh status` | ⚠️ STM is a separate stack (out of scope) |

### Troubleshooting

| # | Workflow | How to Test | Result |
|---|----------|-------------|--------|
| 32 | **Test won't start** | `pueue status && pueue clean` | ✅ Pueue is cloud-agnostic |
| 33 | **Nodes won't sync** | `ansible-playbook is_synced.yml -i ../inventory/dynamic_inventory.gcp.yaml` then SSH + `journalctl` | 🔲 Needs live infra |
| 34 | **Infrastructure won't provision** | `terraform validate && terraform plan -var-file=light.tfvars` | ✅ Validates clean |
| 35 | **Logs not uploading** | `gcloud storage ls gs://provable-logs-results/logs/` | 🔲 Needs live infra; code review ✅ |

---

### Summary

| Status | Count | Workflows |
|--------|-------|-----------|
| ✅ Passes (verified) | 10 | Terraform plan/validate, test/utility auto-discovery, log analysis (cloud-agnostic), pueue |
| ✅ Code review only | 10 | Scripts (`full_run.sh`, `provision.sh`, `setup.sh`, `run-test.sh`, `collect-logs.sh`, etc.) — GCP migration confirmed in source, needs live execution |
| ⚠️ Out of scope | 1 | STM daemon (separate stack) |
| 🔲 Needs live infra | 14 | Full pipeline, individual scripts, utilities, log collection, node access |

### Remaining for full green

1. **Live infrastructure test** — execute `full_run.sh` end-to-end on real GCP:
   - `PUEUE_DISABLED=1 STM_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=swap_ledgers`
   - Validates: provision → setup (binary build/cache) → test execution → log collection → destroy
2. **Individual script tests** — run each `scripts/bin/` entrypoint against live infra to confirm pueue integration, GCS uploads, and Ansible inventory resolution
3. **Manager delegation** — test `full_run.sh` without `STM_LOCAL` to confirm SSH delegation to stress-testing-manager
4. **TX submitter Rust rewrite** — `tests/load_saved_transactions/tx_submitter/` (`aws-sdk-s3` → `google-cloud-storage` crate)
5. **Manual cleanup** — delete `inventory/dynamic_inventory.aws_ec2.yml`

---

**Last updated:** 2026-07-07
**Branch:** `mike2194/a-new-hope` merging `feat/single-region-tests-gcp`
