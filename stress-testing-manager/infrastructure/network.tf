# ------------------------------------------------
# VPC + subnet (shared module from snarkos-p2p-tests)
#
# STM owns this VPC AND subnet. snarkos-p2p-tests and other test suites
# consume both via terraform_remote_state, reading vpc_id, subnet_self_links,
# and subnet_cidrs. All suites share the 10.41.0.0/16 subnet — no separate
# per-suite subnets.

module "network" {
  source     = "../../test_suites/snarkos-p2p-tests/terraform/modules/gcp-snarkos-network"
  project_id = var.gcp_project
  vpc_name   = local.vpc_name
  subnets = {
    (var.gcp_region) = {
      cidr  = local.stm_subnet_cidr
      zones = [var.gcp_zone]
    }
  }
  enable_ops_agent_sa = false
}

# ------------------------------------------------
# Firewall rules (shared module)
#
# The module creates SSH from Cloudflare WARP CIDRs, HTTPS 443, snarkOS
# ports (3030, 4130-4230, 5000, 9000), external LB 3030, metrics
# (9090/9100/9256), and unrestricted egress.
#
# STM does not run snarkOS or serve traffic on those ports, so the extra
# rules are inert (no listeners). TODO: extend the firewall_rule module
# with per-rule enable/disable toggles so STM can opt out of snarkos/lb/
# metrics rules.

module "firewall" {
  source             = "../../test_suites/snarkos-p2p-tests/terraform/modules/firewall_rule"
  target_network_tag = local.network_tag
  project            = var.gcp_project
  vpc                = module.network.vpc_id
  allow_cidr_ranges  = [local.stm_subnet_cidr]
}

# ------------------------------------------------
# External SSH allowlist — one /32 per entry in var.external_ssh_users.
# OS Login is unchanged; this rule authorizes the LEGACY `ubuntu` account
# only (see ansible/setup.yml + ansible_vars.tf for the key file plumbing).
resource "google_compute_firewall" "stm_allow_ssh_external" {
  count   = length(var.external_ssh_users) > 0 ? 1 : 0
  name    = "${local.network_tag}-allow-ssh-external"
  network = module.network.vpc_id
  project = var.gcp_project

  direction = "INGRESS"
  source_ranges = [
    for u in var.external_ssh_users :
    can(regex("/", u.ip_address)) ? u.ip_address : "${u.ip_address}/32"
  ]
  target_tags = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ------------------------------------------------
# Allow all traffic between STM and snarkos-p2p-tests instances (VPC-internal).
#
# source_tags matches VMs tagged with the STM tag or any SRT tag (see
# var.srt_source_tags default and override docs). source_ranges keeps the
# shared-subnet CIDR path as a fallback for VMs that arrive untagged. GCP
# evaluates source_ranges and source_tags as a union — either match allows
# ingress. This rule subsumes the previous stm_allow_icmp (STM subnet ICMP)
# because local.network_tag is in source_tags and the allow block covers
# all protocols. Renaming would ForceNew the firewall resource, so the
# name is retained even though the scope is now VPC-internal.
resource "google_compute_firewall" "stm_allow_srt_internal" {
  name        = "${local.network_tag}-allow-srt-internal"
  network     = module.network.vpc_id
  project     = var.gcp_project
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow all traffic from STM- and SRT-tagged instances (and the shared-subnet CIDR fallback) to the STM."

  source_ranges = var.srt_source_cidrs
  source_tags   = concat([local.network_tag], var.srt_source_tags)
  target_tags   = [local.network_tag]

  allow {
    protocol = "all"
  }
}
