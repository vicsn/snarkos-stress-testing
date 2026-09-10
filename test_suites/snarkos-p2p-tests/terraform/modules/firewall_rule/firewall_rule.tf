variable "target_network_tag" {
  description = "Base name used as the network tag and firewall rule prefix"
  type        = string
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "vpc" {
  description = "VPC network name or self-link"
  type        = string
  default     = "default"
}

variable "cloudflare_warp_cidrs" {
  description = "Source CIDRs allowed to reach SSH (port 22)"
  type        = list(string)
  default = [
    "104.28.192.0/19",
    "104.28.208.0/20",
    "104.28.222.0/24",
    "104.30.134.190/32",
    "104.30.164.90/32",
    "104.30.164.91/32",
    "104.30.164.92/32",
    "104.28.172.156/32",
  ]
}

variable "allow_cidr_ranges" {
  description = "List of CIDR ranges allowed for internal traffic"
  type        = list(string)
}

variable "stm_source_cidrs" {
  description = "STM subnet CIDRs authorized to reach nodes on SSH 22 and snarkOS ports; empty list disables the rule."
  type        = list(string)
  default     = []
}

variable "extra_ssh_source_tags" {
  description = "Additional network tags appended to allow_ssh.source_tags. Callers pass peer tags (e.g. SRT passes the STM tag) so peer VMs can SSH into instances tagged with target_network_tag. Empty list keeps behaviour identical to only accepting SSH from self-tagged sources."
  type        = list(string)
  default     = []
}

variable "extra_ssh_source_cidrs" {
  description = "Additional CIDRs appended to allow_ssh.source_ranges (in addition to var.cloudflare_warp_cidrs). Callers pass external IPs that must be able to SSH into instances tagged with target_network_tag — e.g. SRT passes the STM's public IP so operators tunneling through the STM can reach SRT nodes. Empty list keeps behaviour identical to Cloudflare-WARP-only ingress."
  type        = list(string)
  default     = []
}

variable "allow_all_source_cidrs" {
  description = "CIDRs granted all-protocols ingress to target_network_tag instances via the allow_peer_all rule. Callers pass peer subnets or public IPs that need full access (e.g. SRT passes the STM subnet CIDRs and the STM public static IP). Empty list disables the rule unless allow_all_source_tags is also non-empty."
  type        = list(string)
  default     = []
}

variable "allow_all_source_tags" {
  description = "Network tags granted all-protocols ingress to target_network_tag instances via the allow_peer_all rule. Callers pass peer VM tags that need full access (e.g. SRT passes the STM network tag). Empty list disables the rule unless allow_all_source_cidrs is also non-empty."
  type        = list(string)
  default     = []
}

locals {
  tag = var.target_network_tag
}

# ------------------------------------------------
# Ingress rules

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.target_network_tag}-allow-ssh"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = concat(var.cloudflare_warp_cidrs, var.extra_ssh_source_cidrs)
  source_tags   = concat([local.tag], var.extra_ssh_source_tags)
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_https" {
  name    = "${var.target_network_tag}-allow-https"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "allow_snarkos" {
  name    = "${var.target_network_tag}-allow-snarkos"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = var.allow_cidr_ranges
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    # SnarkOS REST API, P2P communication, and core services (internal only)
    ports = [
      "3030",      # SnarkOS REST API (internal)
      "4130-4230", # SnarkOS P2P port range
      "5000",      # Misc application services
      "9000",      # SnarkOS metrics
    ]
  }
}

resource "google_compute_firewall" "allow_lb_external" {
  name    = "${var.target_network_tag}-allow-lb-external"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    # External load balancer access to SnarkOS REST API
    ports = ["3030"]
  }
}

resource "google_compute_firewall" "allow_metrics" {
  name    = "${var.target_network_tag}-allow-metrics"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    # Monitoring and observability services
    ports = [
      "9090", # Prometheus
      "9100", # Node Exporter
      "9000", # Snarkos Metrics
      "9256", # Process Exporter
    ]
  }
}

# ------------------------------------------------
# Egress — unrestricted

resource "google_compute_firewall" "allow_egress" {
  name    = "${var.target_network_tag}-allow-egress"
  network = var.vpc
  project = var.project

  direction          = "EGRESS"
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.tag]

  allow {
    protocol = "all"
  }
}

# ------------------------------------------------
# Optional: STM subnet ingress (SSH + snarkOS ports)

resource "google_compute_firewall" "allow_stm_internal" {
  count   = length(var.stm_source_cidrs) > 0 ? 1 : 0
  name    = "${var.target_network_tag}-allow-stm-internal"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = var.stm_source_cidrs
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    ports    = ["22", "3030", "4130-4230", "5000", "9000"]
  }
}

# ------------------------------------------------
# Peer network — all-protocols ingress from trusted peer sources.
#
# Used for bidirectional STM<>SRT connectivity: SRT calls this module with the
# STM's public IP, STM subnet CIDRs, and STM network tag as peer sources so
# STM-originated traffic can reach any port on SRT nodes. The mirror rule
# (SRT-originated → STM, also all-protocols) lives in STM's stm_allow_srt_internal.
resource "google_compute_firewall" "allow_peer_all" {
  count   = length(var.allow_all_source_cidrs) + length(var.allow_all_source_tags) > 0 ? 1 : 0
  name    = "${var.target_network_tag}-allow-peer-all"
  network = var.vpc
  project = var.project

  direction     = "INGRESS"
  source_ranges = length(var.allow_all_source_cidrs) > 0 ? var.allow_all_source_cidrs : null
  source_tags   = length(var.allow_all_source_tags) > 0 ? var.allow_all_source_tags : null
  target_tags   = [local.tag]

  allow {
    protocol = "all"
  }
}

# ------------------------------------------------
# Outputs

output "network_tag" {
  value       = local.tag
  description = "Network tag to apply to instances to subject them to these firewall rules"
}
