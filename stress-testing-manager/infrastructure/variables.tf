# ------------------------------------------------
# GCP project, region, zone

variable "gcp_project" {
  description = "GCP project ID that owns the STM instance and shared buckets"
  type        = string
  default     = "protocol-development-sandbox"
}

variable "gcp_region" {
  description = "GCP region for the STM subnet and static IP"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone that hosts the STM instance"
  type        = string
  default     = "us-central1-b"
}

# ------------------------------------------------
# Ownership / naming

variable "owner" {
  description = "Written to instance metadata `owner` field for downstream tooling attribution (usually the invoking user's login). Not used in resource naming."
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "owner must be non-empty; pass -var=\"owner=$USER\"."
  }
}

# ------------------------------------------------
# Instance shape

variable "machine_type" {
  description = "GCE machine type for the STM instance"
  type        = string
  default     = "c3d-standard-4"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Boot disk type (e.g. pd-ssd, pd-balanced, pd-standard)"
  type        = string
  default     = "pd-ssd"
}

# ------------------------------------------------
# Base image (Packer-built stress-test-base by default)

variable "image_family" {
  description = "GCE image family used as the STM base image"
  type        = string
  default     = "stress-test-base"
}

variable "image_project" {
  description = "GCP project that owns the base image family"
  type        = string
  default     = "protocol-development-sandbox"
}

# ------------------------------------------------
# Workload configuration

variable "stress_testing_branch" {
  description = "snarkos-stress-testing git branch the STM should track"
  type        = string
  default     = "main"
}

# ------------------------------------------------
# GCS buckets (created out-of-band; the STM SA is granted access to them)

variable "releases_bucket" {
  description = "GCS bucket holding snarkOS binaries and stress-testing artifact tarballs"
  type        = string
  default     = "provable-binaries-releases"
}

variable "results_bucket" {
  description = "GCS bucket for test logs and results uploaded by full_run.sh"
  type        = string
  default     = "provable-logs-results"
}

variable "cache_bucket" {
  description = "GCS bucket used by sccache as the compiler cache"
  type        = string
  default     = "snarkos-compiler-cache"
}

# ------------------------------------------------
# External SSH access — per-user IP allowlist + public keys
#
# Each entry authorizes one external user to SSH into the STM as the Linux
# user "ubuntu" from a single source IP. Keys are written to
# `../../keys.pub` by the `local_file` resource in `ansible_vars.tf`,
# auto-loaded by `ansible/setup.yml`, and installed into
# `~ubuntu/.ssh/authorized_keys` by `ansible.posix.authorized_key`.
#
# The `name` field is a tfvars-level identifier used for revocation — it is
# NOT used in terraform code and is NOT embedded in the instance metadata.
# The `name` field is also used as the SSH `comment` on the authorized_keys entry;
# keeping it unique per user is required — duplicate `name` values will collapse
# to a single authorized_keys line.
#
# OS Login stays enabled unconditionally (metadata `ssh-keys` is therefore inert).
# Org users continue to use `gcloud compute ssh` via OS Login regardless of this
# list; external users authenticate through the file-based `authorized_keys` on
# the pre-existing `ubuntu` system account.

variable "external_ssh_users" {
  description = "External users authorized to SSH into the STM as `ubuntu`. Each entry: name (tfvars identifier, unused in terraform code), ip_address (source IP, will be /32 allowlisted), public_key (full SSH public key line — e.g. \"ssh-ed25519 AAAA...\"). Leave empty to grant no external access."
  type = list(object({
    name       = string
    ip_address = string
    public_key = string
  }))
  default = []

  validation {
    condition = alltrue([
      for u in var.external_ssh_users :
      length(u.name) > 0 && length(u.ip_address) > 0 && length(u.public_key) > 0
    ])
    error_message = "Every external_ssh_users entry must have non-empty name, ip_address, and public_key."
  }

  validation {
    condition = alltrue([
      for u in var.external_ssh_users :
      can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+", u.public_key))
    ])
    error_message = "Every external_ssh_users public_key must start with a valid SSH key type (ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistpNNN) followed by base64 key data."
  }
}

# ------------------------------------------------
# Shared-subnet firewall source CIDR allowlist

variable "srt_source_cidrs" {
  description = "CIDR ranges permitted as source_ranges on the stm_allow_srt_internal firewall rule. SRT now reuses the STM subnet (10.41.0.0/16), so the default matches that subnet — the rule primarily relies on source_tags, and this CIDR is a fallback for untagged VMs inside the shared subnet. Override to add peered subnets or a wider allowance."
  type        = list(string)
  default     = ["10.41.0.0/16"]

  validation {
    condition     = length(var.srt_source_cidrs) > 0
    error_message = "srt_source_cidrs must contain at least one CIDR range."
  }

  validation {
    condition     = alltrue([for c in var.srt_source_cidrs : can(cidrnetmask(c))])
    error_message = "each srt_source_cidrs entry must be a valid CIDR (e.g. 10.41.0.0/16)."
  }
}

# ------------------------------------------------
# Single-region-tests firewall source tag allowlist
#
# SRT tag format is `${terraform.workspace}-${devnet_name}` (see
# single-region-tests/terraform/locals.tf:network_tag_prefix). The default
# matches the `default` workspace + default devnet_name (`single-region-tests`).
# Operators on a non-default workspace or devnet_name must override this
# variable to list every SRT tag that should be permitted ingress to the STM.

variable "srt_source_tags" {
  description = "Network tags applied to single-region-tests instances. Used as source_tags on stm_allow_srt_internal so any SRT-tagged VM in the STM VPC can reach the STM. Default matches the `default` workspace paired with the default devnet_name (single-region-tests), producing the tag `default-single-region-tests`."
  type        = list(string)
  default     = ["default-single-region-tests"]

  validation {
    condition     = length(var.srt_source_tags) > 0
    error_message = "srt_source_tags must contain at least one network tag."
  }

  validation {
    condition     = alltrue([for t in var.srt_source_tags : can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", t))])
    error_message = "each srt_source_tags entry must be a valid GCE network tag (lowercase letters, digits, hyphens; must start with a letter and end with a letter or digit)."
  }
}
