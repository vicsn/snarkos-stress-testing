# Slack credential existence checks.
#
# These data sources exist so that `terraform plan` fails fast when the
# Secret Manager secrets are missing (they must be created out-of-band
# before the first apply — see GCP_MIGRATION.md Phase 4). The Ansible
# playbook and full_run.sh delegation both fetch values via
# `gcloud secrets versions access` at runtime rather than reading from
# Terraform state, so no secret material lands in tfstate.
#
# We reference the secret METADATA (google_secret_manager_secret) rather
# than a specific version (google_secret_manager_secret_version) so the
# check is not sensitive to individual version states. A destroyed
# version does not break `terraform plan`; only a missing secret does.

data "google_secret_manager_secret" "slack_token" {
  secret_id = "stress-testing-manager-slack-token"
  project   = var.gcp_project
}

data "google_secret_manager_secret" "slack_channel_id" {
  secret_id = "stress-testing-manager-slack-channel-id"
  project   = var.gcp_project
}
