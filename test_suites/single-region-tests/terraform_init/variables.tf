# ------------------------------------------------
# All resource names are interpolated from service_name.
#
#   State bucket:    tfstate-${service_name}
#   Release bucket:  ${release_bucket_name}
#   Service account: ${service_name}
#   SA display name: Terraform State SA (${service_name})
#
# Override gcp_project / gcp_region as needed.

variable "service_name" {
  description = "Root name used to derive bucket, SA, and IAM resource names"
  type        = string
  default     = "snarkos-stress-testing"
}

variable "gcp_project" {
  description = "GCP project that owns the state bucket and service account"
  type        = string
  default     = "protocol-development-sandbox"
}

variable "gcp_region" {
  description = "GCS bucket location"
  type        = string
  default     = "us-central1"
}

variable "state_prefix" {
  description = "Object prefix inside the bucket (maps to terraform workspace key)"
  type        = string
  default     = "single-region-tests"
}

variable "state_admins" {
  description = "Additional IAM members (user:/group:/serviceAccount:) granted objectAdmin on the state bucket"
  type        = list(string)
  default     = []
}

# ------------------------------------------------
# Release binary bucket

variable "release_bucket_name" {
  description = "GCS bucket for snarkOS release binaries (built by ephemeral builder, consumed by setup.yml)"
  type        = string
  default     = "provable-binaries-releases"
}


