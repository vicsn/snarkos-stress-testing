# Aleo SnarkOS Stress Testing Manager (GCP)

Long-running GCE instance that hosts `pueued` and delegates
`snarkos-stress-testing` workloads on behalf of engineers and CI. Runs on
Google Cloud in the `protocol-development-sandbox` project. See
[GCP_MIGRATION.md](./GCP_MIGRATION.md) for the design rationale of the
AWS→GCP move.

---

## What lives here

| Component | Where |
|---|---|
| Terraform (GCE + IAM + VPC + firewall) | [`infrastructure/`](./infrastructure) |
| Terraform (GCS buckets) | [`infrastructure/storage.tf`](./infrastructure/storage.tf) |
| Orchestrator CLI | [`infrastructure/tf_stack.sh`](./infrastructure/tf_stack.sh) |
| Ansible playbook | [`infrastructure/ansible/setup.yml`](./infrastructure/ansible/setup.yml) |
| Ansible inventory (dynamic, GCP) | [`infrastructure/ansible/inventory/dynamic_inventory.gcp.yaml`](./infrastructure/ansible/inventory/dynamic_inventory.gcp.yaml) |
| Systemd + pueue templates | [`infrastructure/ansible/templates/`](./infrastructure/ansible/templates) |

As of the state migration described in [§ State migration](#state-migration-adopting-provable-logs-results-from-terraform_init), this stack now owns the `provable-logs-results` GCS bucket. The pre-existing `snarkos-stress-testing@` terraform SA retains `roles/storage.objectAdmin` on it (unchanged behavior).

The AWS-era `packer/` directory is retained as `.DELETE` placeholders while
the AWS teardown is documented — the GCP base image comes from the shared
[`packer/`](../packer) at the repo root (`stress-test-base` family, project
`protocol-development-sandbox`).

---

## Prerequisites

- `gcloud` CLI authenticated with edit access to
  `protocol-development-sandbox`:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project protocol-development-sandbox
  ```
- OS Login enabled on your account:
  ```bash
  gcloud projects add-iam-policy-binding protocol-development-sandbox \
    --member="user:you@provable.com" \
    --role="roles/compute.osLogin"
  ```
- Terraform ≥ 1.10, Ansible ≥ 2.16.
- **Secret Manager secrets** created out-of-band (see below).

### One-time Secret Manager setup

Slack credentials are read from GCP Secret Manager (no more `vars.yml` in
the repo). Create them once per project:

```bash
echo -n "xoxb-YOUR-TOKEN"     | gcloud secrets create stress-testing-manager-slack-token \
    --data-file=- --project=protocol-development-sandbox
echo -n "C0YOURCHANNELID"     | gcloud secrets create stress-testing-manager-slack-channel-id \
    --data-file=- --project=protocol-development-sandbox
```

IAM access is granted to the STM SA automatically by `iam.tf` during
`terraform apply`.

---

## Provision and setup

From `infrastructure/`:

```bash
./tf_stack.sh plan
./tf_stack.sh provision --auto-approve
./tf_stack.sh setup
```

- **`provision`** — `terraform apply` on the GCP resources
  (`google_compute_instance.stm`, static IP, VPC, firewall, SA, IAM).
- **`setup`** — resolves the OS Login username via
  `gcloud compute ssh <instance> --command="whoami"`, then runs
  `ansible/setup.yml` with target `full`. Installs Rust toolchain, pueue
  daemon (systemd), sccache configured for the GCS backend, and pulls the
  latest `snarkos-stress-testing` artifact from
  `gs://provable-binaries-releases/stress-testing/latest.tar.gz`.

### Manual ansible run (using the dynamic inventory)

`tf_stack.sh setup` uses a static inline inventory resolved from Terraform outputs. To run the playbook manually against the label-filtered dynamic inventory instead:

```bash
cd stress-testing-manager/infrastructure/ansible
STM_USER="$(gcloud compute ssh "$(cd ../ && terraform output -raw stm_instance_name)" \
  --zone="$(cd ../ && terraform output -raw stm_zone)" \
  --command='whoami' | tail -1 | tr -d '[:space:]')"
ansible-playbook -i inventory/dynamic_inventory.gcp.yaml setup.yml \
  -e "ansible_user=${STM_USER}" \
  -e "stm_user=${STM_USER}" \
  -e "stm_home=/home/${STM_USER}"
```

### Staging workspace

Parallel stack in workspace `staging`:

```bash
./tf_stack.sh provision --staging --auto-approve
./tf_stack.sh setup --staging
```

Terraform state is per-workspace inside the shared GCS bucket
`tfstate-snarkos-stress-testing` under prefix `stress-testing-manager`.

---

## SSH into the manager

OS Login handles all SSH — no key files on disk.

```bash
INSTANCE=$(./tf_stack.sh output | awk '/stm_instance_name/ {print $3}' | tr -d '"')
ZONE=$(./tf_stack.sh output    | awk '/stm_zone/          {print $3}' | tr -d '"')
gcloud compute ssh "$INSTANCE" --zone="$ZONE"
```

Inside the STM your username will be `sa_<numeric>` for service accounts
or `ext_<prefix>_<domain>` for humans — the Ansible playbook parameterises
`stm_user` so `/home/$stm_user/…` layout works for any OS Login shape.

---

## Artifact deployment

Code changes reach the STM via a GCS artifact, not rsync:

1. **Local upload** — package the current worktree:
   ```bash
   RELEASES_BUCKET=provable-binaries-releases \
     ../../scripts/bin/upload-artifact.sh
   ```
   Writes `stress-testing-<timestamp>.tar.gz` and `latest.tar.gz` under
   `gs://<bucket>/stress-testing/`.

2. **CI/CD upload** — [`.github/workflows/upload-stm-artifact.yml`](../.github/workflows/upload-stm-artifact.yml)
   runs on every push to `main` under paths that could affect the STM
   (`test_suites/`, `scripts/`, `common/`, `stress-testing-manager/`),
   authenticating via Workload Identity Federation (WIF placeholders in
   the workflow — replace before use).

3. **STM pull** — `setup` (or `update --update-target stress-testing`)
   invokes `scripts/bin/pull-artifact.sh` on the STM, which fetches
   `latest.tar.gz` into `$HOME/snarkos-stress-testing/`.

---

## Updating

Partial updates reuse `setup.yml` subsets without touching Terraform:

```bash
./tf_stack.sh update                                       # both (repo + pueue), default
./tf_stack.sh update --update-target stress-testing        # repo pull only
./tf_stack.sh update --update-target pueue --pueue-version 4.0.1
```

Full re-setup: `./tf_stack.sh setup`.

---

## State migration: adopting provable-logs-results from terraform_init/

This one-time procedure moves the `provable-logs-results` GCS bucket from the `terraform_init/` bootstrap state into this STM stack's state. The bucket is never destroyed or recreated — only the Terraform state file that tracks it changes.

### 0. Safety model (READ FIRST)

This migration involves TWO Terraform states manipulating ONE global GCS bucket. There is no atomic operation across states. The safe path relies on the ORDER of operations and on `force_destroy = false` (which stays in force throughout) to block accidental destroy.

**CRITICAL RULE:** While the migration is in progress (between Step 3b and Step 5.d), NO ONE runs `terraform apply` on EITHER stack. Announce start/end in Slack; lock the shared state bucket if the team has a locking convention.

The safe ordering below preserves the `terraform_init` code blocks until AFTER STM has successfully imported the resources. If someone accidentally runs `terraform apply` in `terraform_init` between Step 3b and Step 5.d, Terraform sees "code has resource, state does not" → attempts CREATE → hits GCS 409 (bucket already exists) → **fails safely without side effects**. The reverse ordering (code delete first, then state rm) creates a window where an accidental apply would attempt DESTROY — protected only by `force_destroy = false`, which is a soft protection that should not be the primary safety mechanism.

Wave 2's `terraform_init` code deletion MUST happen AFTER Step 5.d, not before.

### 1. Prerequisites

- Wave 1 code (storage.tf, outputs.tf, SRT iam.tf, this runbook) is merged to `main`, NOT yet applied.
- Operator has `gcloud auth application-default login` with `snarkos-stress-testing@protocol-development-sandbox.iam.gserviceaccount.com` impersonation, or equivalent roles granting `storage.buckets.get` + `storage.objects.list` on `provable-logs-results` and both stacks' state buckets, plus `roles/iam.securityAdmin` on the project (needed by `terraform import` on IAM members).
- STM stack initialized: `cd stress-testing-manager/infrastructure && terraform init`
- **Staging first:** run Steps 2–5 against the `staging` STM workspace before touching the default workspace. See [§ Staging workspace](#staging-workspace) above. Note: `terraform_init` has no workspace concept (single shared state) — Steps 3 and 3b execute directly against the shared state once at migration time.

### 2. Baseline confirmations

Both stacks must be clean before proceeding.

```bash
# STM side — expect exactly 3 planned adds (bucket + 2 IAM members), zero destroys
cd stress-testing-manager/infrastructure
terraform workspace select <target>   # staging or default
terraform plan -var="owner=$USER"

# terraform_init side — expect "No changes."
cd test_suites/snarkos-p2p-tests/terraform_init
terraform plan
```

If either baseline fails, STOP. Do not proceed to Step 3.

### 3. Confirm state addresses in terraform_init

```bash
cd test_suites/snarkos-p2p-tests/terraform_init
terraform state list
```

Verify exactly these three addresses appear:
- `google_storage_bucket.logs`
- `google_storage_bucket_iam_member.sa_logs_admin`
- `google_storage_bucket_iam_member.logs_viewer`

If any address differs (e.g. resource inside a module, renamed), STOP. Adjust the `state rm` command in Step 3b to the actual address. Do not proceed on assumption.

### 3b. Remove the three resources from terraform_init state

The code blocks stay in place — only the state entry is removed. This is intentional (see Safety model above).

```bash
cd test_suites/snarkos-p2p-tests/terraform_init
terraform state rm \
  google_storage_bucket.logs \
  google_storage_bucket_iam_member.sa_logs_admin \
  google_storage_bucket_iam_member.logs_viewer

# Verify removal
terraform state list | grep -E 'logs$|sa_logs_admin|logs_viewer'
# Must be empty

# Expected intermediate state: terraform plan now shows planned ADDS for the three resources
# (code still has them; state does not). Do NOT terraform apply here.
terraform plan
```

### 4. Import the resources into STM state

Import ID format for `google_storage_bucket_iam_member` is `b/<bucket>/<role>/<member>` per the [google provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam#import).

```bash
cd stress-testing-manager/infrastructure

terraform import -var="owner=$USER" \
  google_storage_bucket.results \
  provable-logs-results

terraform import -var="owner=$USER" \
  'google_storage_bucket_iam_member.sa_results_admin' \
  'b/provable-logs-results/roles/storage.objectAdmin/serviceAccount:snarkos-stress-testing@protocol-development-sandbox.iam.gserviceaccount.com'

terraform import -var="owner=$USER" \
  'google_storage_bucket_iam_member.results_viewer' \
  'b/provable-logs-results/roles/storage.objectViewer/projectViewer:protocol-development-sandbox'
```

### 5. Verify STM state

```bash
cd stress-testing-manager/infrastructure

# 5.a — all three addresses present
terraform state list | grep -E 'results$|sa_results_admin|results_viewer'

# 5.b — bucket properties match code
terraform state show google_storage_bucket.results
# Must show: name = "provable-logs-results", lifecycle_rule.condition.age = 180,
# uniform_bucket_level_access = true, force_destroy = false, versioning disabled, labels intact.

# 5.c — IAM member properties match code
terraform state show google_storage_bucket_iam_member.sa_results_admin
# Must show: role = "roles/storage.objectAdmin", member = "serviceAccount:snarkos-stress-testing@..."

# 5.d — plan must show NO CHANGES
terraform plan -var="owner=$USER"
```

If Step 5.d shows any change to `.results` or the two IAM members, STOP and go to [§ Rollback matrix](#rollback-matrix).

### 6. Signal for Wave 2

After Step 5.d is confirmed clean, post to Slack and open the Wave 2 PR (code deletion in `terraform_init/`). Wave 2 removes the resource blocks and variable from `terraform_init/` code, making the intermediate ADDS plan from Step 3b become a "No changes" plan.

### 7. Rollback matrix

| If failure occurs at … | State of the bucket | Recovery |
|---|---|---|
| Step 2 (baseline plan errors) | Untouched | Fix the offending resource / permission; retry Step 2. |
| Step 3 (state-list addresses wrong) | Untouched | Adjust addresses; retry Step 3b. |
| Step 3b (state rm errors) | Untouched | `terraform state rm` is transactional per-resource — if it fails, no changes. Retry. |
| Between Step 3b and Step 4 (state-orphaned) | Bucket exists in GCS; no state tracks it | Re-import into `terraform_init` using ORIGINAL addresses: `terraform import google_storage_bucket.logs provable-logs-results` and the two IAM members with the OLD names. Return to Step 2. Do NOT run `terraform apply` on either stack until reconciled. |
| Step 4 (STM import fails on one resource) | Bucket exists; partial STM state | Roll back partial STM imports: `terraform state rm <address>` for each successfully imported resource. Then re-import into `terraform_init` per the row above. Investigate the failure and retry the entire migration. |
| Step 5.d (plan shows unexpected diff after import) | Bucket exists; all three in STM state; code drift | Diagnose with `terraform plan -no-color`. Common causes: label-value order, missing `versioning { enabled = false }` block, `uniform_bucket_level_access` mismatch. Fix `storage.tf` to match state. Do NOT `terraform apply` — that would re-write live bucket properties. Amend and re-run Step 5.d. |
| Wave 2 Todo 5 apply on `terraform_init` shows destroy plan | Bucket exists; STM owns it | Code deletion was incomplete or state has residue. Re-run Step 3 confirmations and Step 3b as needed. |
| Post-migration: SRT `terraform apply` fails on IAM condition change | Bucket + STM ownership intact; SRT IAM NOT extended | SRT nodes lack write access to results bucket. No runtime breakage (no on-node upload code exists today). Fix the SRT apply error and retry — the migration and SRT IAM apply are independent and both idempotent. |

### 8. Restoration path of last resort

GCS versioning on `tfstate-snarkos-stress-testing` retains prior state object generations.

```bash
# List generations
gcloud storage ls -a gs://tfstate-snarkos-stress-testing/<prefix>/<workspace>.tfstate

# Fetch a prior generation
gcloud storage cp 'gs://tfstate-snarkos-stress-testing/<prefix>/<workspace>.tfstate#<gen>' ./restored.tfstate

# Re-install
terraform state push restored.tfstate
```

Consult the [GCP Terraform GCS backend docs](https://developer.hashicorp.com/terraform/language/settings/backends/gcs) before any push.

### 9. Post-migration housekeeping

After both PRs are merged, open a small follow-up PR to update the description on `var.results_bucket` in `stress-testing-manager/infrastructure/variables.tf` from "GCS bucket for test logs and results uploaded by full_run.sh" to "GCS bucket for test logs and results. Managed by this stack; consumed by SRT via terraform_remote_state."

---

## Slack credentials

Loaded automatically from GCP Secret Manager on the STM:

| Source | Used when |
|--------|-----------|
| Existing `SLACK_TOKEN` / `SLACK_CHANNEL_ID` env | Highest priority (never overridden) |
| `~/.config/snarkos-stress-testing/slack_env.sh` on the STM | After `tf_stack.sh setup` provisions it from Secret Manager |
| `gcloud secrets versions access` in `slack_config.sh` | Fallback when the env file is absent |
| Legacy `stress-testing-manager/infrastructure/vars.yml` | Last resort for local runs (not part of GCP flow) |

Set `NOTIFY_SLACK_DISABLED=1` to skip notifications entirely.

---

## Destroying

```bash
./tf_stack.sh destroy --force --auto-approve            # default workspace
./tf_stack.sh destroy --staging --auto-approve          # staging
```

The default workspace requires `--force` to prevent accidental teardown.

---

## Running tests

See [snarkos-p2p-tests/README.md](../test_suites/snarkos-p2p-tests/README.md).

From your laptop, `./scripts/full_run.sh` in that test suite delegates to
this manager by default. It reads the STM's instance name and zone from
the STM terraform outputs and SSHes over `gcloud compute ssh` — no
`stress-testing-manager-ip.txt`, no static key files.

To force a local run instead of delegating:

```bash
FULL_RUN_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=prerelease
```

To retrieve the manager's public IP:

```bash
./tf_stack.sh ip
```

---

## AWS decommissioning

The legacy AWS STM stack is retained as an untouched fallback until the GCP
STM has run production workloads for a full stress-testing cycle. Teardown
steps are documented in [`GCP_MIGRATION.md`](./GCP_MIGRATION.md) under
"Deferred Work / AWS Teardown".
