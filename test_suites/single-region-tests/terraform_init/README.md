# terraform_init — Bootstrap Release Bucket + IAM Bindings

One-time setup that creates the release binary bucket and grants IAM permissions to the pre-existing service account.

## Prerequisites

The **tfstate bucket** and **service account** must already exist. Both are managed in the infrastructure repo:

> **https://github.com/ProvableHQ/infrastructure/tree/main/gcs/protocol-development-sandbox/workload**

| Pre-existing Resource | Name |
|-----------------------|------|
| GCS bucket | `tfstate-snarkos-stress-testing` |
| Service account | `snarkos-stress-testing@protocol-development-sandbox.iam.gserviceaccount.com` |

This module does NOT create or manage these — it reads them as data sources to grant IAM bindings.

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| GCS bucket | `provable-binaries-releases` | snarkOS release binary cache (90-day lifecycle) |
| GCS bucket | `provable-logs-results` | Test run logs + results (180-day lifecycle). **Formerly managed here** as `google_storage_bucket.logs`; migrated to `stress-testing-manager/infrastructure/` — see the [STM migration runbook](../../../stress-testing-manager/README.md#state-migration-adopting-provable-logs-results-from-terraform_init). |
| IAM bindings | `compute.admin`, `iam.serviceAccountAdmin`, `storage.admin`, `storage.objectAdmin` | SA permissions on project + buckets |

> **Note:** The `provable-logs-results` bucket has been migrated to `stress-testing-manager/infrastructure/`. See the [state migration runbook](../../../stress-testing-manager/README.md#state-migration-adopting-provable-logs-results-from-terraform_init) for the procedure.

## Usage

```bash
# 1. Bootstrap (run once)
cd test_suites/single-region-tests/terraform_init
terraform init
terraform apply

# 2. Copy the backend config from output
terraform output backend_config

# 3. Update terraform/provider.tf with the GCS backend (see below)

# 4. Migrate state
cd ../terraform
terraform init -migrate-state
```

## After Bootstrap

Replace `backend "local" {}` in `terraform/provider.tf` with:

```hcl
terraform {
  backend "gcs" {
    bucket = "tfstate-snarkos-stress-testing"
    prefix = "single-region-tests"
  }
}
```

Then run `terraform init -migrate-state` to move existing local state to GCS.
