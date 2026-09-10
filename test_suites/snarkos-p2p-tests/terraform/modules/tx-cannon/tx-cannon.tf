variable "tx_cannon_instance_type" {
  description = "Machine type for tx-cannon nodes"
  default     = "c3d-standard-30"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "image_self_link" {
  description = "Self-link of the base image to use for tx-cannon instances"
  type        = string
}

variable "network_tag" {
  description = "Network tag for firewall rule targeting"
  type        = string
}

variable "devnet_name" {
  description = "Unique name for this devnet deployment"
  type        = string
}

variable "owner" {
  description = "Identifier for the user or team deploying this infrastructure"
  type        = string
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zones" {
  description = "List of zones to spread tx-cannon nodes across"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC network ID to attach tx-cannon instances to"
  type        = string
}

variable "subnet_self_link" {
  description = "Subnet self-link to attach tx-cannon instances to"
  type        = string
}

variable "ssh_metadata" {
  description = "Instance metadata map for SSH access (OS Login or metadata SSH keys)"
  type        = map(string)
  default     = { enable-oslogin = "TRUE" }
}

# ------------------------------------------------
# Service Account for tx-cannon instances (GCS read-only to release bucket)

resource "google_service_account" "tx_cannon_sa" {
  account_id   = "${substr(lower(replace(var.owner, "/[^a-z0-9-]/", "-")), 0, 20)}-txcannon-sa"
  display_name = "TX Cannon Service Account (${var.owner})"
  project      = var.project
}

resource "google_project_iam_member" "tx_cannon_gcs_viewer" {
  project = var.project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.tx_cannon_sa.email}"

  condition {
    title       = "release_bucket_only"
    description = "Restrict to provable-binaries-releases bucket"
    expression  = "resource.name.startsWith(\"projects/_/buckets/provable-binaries-releases\")"
  }
}

# ------------------------------------------------
# Compute instances

resource "google_compute_instance" "tx_cannon_node" {
  count        = var.tx_cannon_instance_count
  name         = "${var.owner}-tx-cannon-node-${count.index}"
  machine_type = var.tx_cannon_instance_type
  zone         = var.zones[count.index % length(var.zones)]

  tags = [var.network_tag]

  labels = {
    role   = "tx-cannon-node"
    dev    = count.index
    owner  = lower(replace(var.owner, "/[^a-z0-9-]/", "-"))
    devnet = lower(replace(var.devnet_name, "/[^a-z0-9-]/", "-"))
  }

  metadata = var.ssh_metadata

  boot_disk {
    initialize_params {
      image = var.image_self_link
      size  = 20
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_self_link
    access_config {}
  }

  service_account {
    email  = google_service_account.tx_cannon_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
