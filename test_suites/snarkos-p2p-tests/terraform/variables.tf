# ------------------------------------------------
# GCP project and region

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
  default     = "protocol-development-sandbox"
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# ------------------------------------------------
# Base image (Packer-built or stock Ubuntu)

variable "image_family" {
  description = "GCP image family. Use 'stress-test-base' for Packer-built, 'ubuntu-2204-lts' for stock."
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "image_project" {
  description = "GCP project owning the image family. Use own project for Packer-built images."
  type        = string
  default     = "ubuntu-os-cloud"
}

# ------------------------------------------------
# Ownership and naming

variable "owner" {
  description = "Name of the human or job running this deployment"
  type        = string
}

variable "devnet_name" {
  description = "Unique devnet identifier used in resource names and labels"
  type        = string
  default     = "snarkos-p2p-tests"
}

# ------------------------------------------------
# Instance counts

variable "validator_instance_count" {
  description = "Number of snarkOS validator instances"
  type        = number
  default     = 5
}

variable "client_instance_count" {
  description = "Number of snarkOS client instances"
  type        = number
  default     = 0
}

variable "prover_instance_count" {
  description = "Number of snarkOS prover instances"
  type        = number
  default     = 0
}

# ------------------------------------------------
# Instance types

variable "validator_instance_type" {
  description = "Machine type for validator instances"
  type        = string
  default     = "c3d-standard-30"
}

variable "client_instance_type" {
  description = "Machine type for client instances"
  type        = string
  default     = "c3d-standard-8"
}

variable "prover_instance_type" {
  description = "Machine type for prover instances"
  type        = string
  default     = "c3d-standard-8"
}

variable "tx_runner_instance_type" {
  description = "Machine type for TX runner instance"
  type        = string
  default     = "c3d-standard-30"
}

# ------------------------------------------------
# Disk sizes (GB)

variable "validator_disk_size" {
  description = "Boot disk size in GB for validator instances"
  type        = number
  default     = 1000
}

variable "client_disk_size" {
  description = "Boot disk size in GB for client instances"
  type        = number
  default     = 1000
}

variable "prover_disk_size" {
  description = "Boot disk size in GB for prover instances"
  type        = number
  default     = 1000
}

variable "prometheus_disk_size" {
  description = "Boot disk size in GB for prometheus server"
  type        = number
  default     = 80
}

# ------------------------------------------------
# Networking

variable "vpc" {
  description = "Map of region to zone config for SRT instance placement. Key = region (must match a region where STM has provisioned a subnet), value = { zones }. SRT no longer creates its own subnet — it reuses STM's subnet_self_links output via terraform_remote_state."
  type = map(object({
    zones = list(string)
  }))
  default = {
    "us-central1" = {
      zones = ["us-central1-b", "us-central1-c", "us-central1-f"]
    }
  }
}

# ------------------------------------------------
# Storage

variable "release_bucket" {
  description = "GCS bucket name for snarkOS release binaries"
  type        = string
  default     = "provable-binaries-releases"
}

variable "compiler_cache_bucket" {
  description = "GCS bucket name for sccache compiler cache"
  type        = string
  default     = "snarkos-compiler-cache"
}

variable "create_compiler_cache_bucket" {
  description = "Whether to create the compiler cache GCS bucket"
  type        = bool
  default     = false
}

# ------------------------------------------------
# TX cannons (optional)

variable "add_tx_cannons" {
  description = "Whether to provision TX cannon instances"
  type        = bool
  default     = false
}

variable "tx_cannon_instance_count" {
  description = "Number of TX cannon instances"
  type        = number
  default     = 4
}

variable "tx_cannon_instance_type" {
  description = "Machine type for TX cannon instances"
  type        = string
  default     = "c3d-standard-30"
}

# ------------------------------------------------
# Builder (optional)

variable "add_builder" {
  description = "Whether to provision an ephemeral builder instance"
  type        = bool
  default     = false
}

variable "builder_instance_type" {
  description = "Machine type for the ephemeral snarkOS builder"
  type        = string
  default     = "c3d-standard-30"
}

# ------------------------------------------------
# Prometheus (optional)

variable "prometheus_enabled" {
  description = "Whether to provision the Prometheus server instance. Default true preserves the historical always-on behavior; set false to skip it entirely (the Ansible prometheus_server play then no-ops on an empty host group)."
  type        = bool
  default     = false
}

# ------------------------------------------------
# SSH access

variable "ssh_user" {
  description = "Username for SSH access to instances (must match Ansible remote_user)"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Optional additional SSH public key content (e.g. 'ssh-ed25519 AAAA... user@host'), layered on top of the always-injected devnet-key.pub. Both authorize the same var.ssh_user (default: ubuntu). Empty is fine — devnet-key.pub alone remains authorized."
  type        = string
  default     = ""
}

# ------------------------------------------------
# Admin access

variable "admin_users" {
  description = "List of user/group emails granted read-only compute, logging, and monitoring access"
  type        = list(string)
  default     = ["group:gcp-engineering-viewer@provable.com"]
}
