# ------------------------------------------------
# Derived values used across root-level resources

locals {
  # Sanitized names for use in GCP resource identifiers (lowercase, hyphens only)
  sanitized_owner       = lower(replace(var.owner, "/[^a-z0-9-]/", "-"))
  sanitized_devnet_name = lower(replace(var.devnet_name, "/[^a-z0-9-]/", "-"))

  # network-tags-and-cross-subnet: firewall tag keyed on workspace, not operator login
  network_tag_prefix = "${terraform.workspace}-${local.sanitized_devnet_name}"

  # Network name prefix used for resource naming
  name_prefix = "${var.owner}-${var.devnet_name}"

  # Resolve the first region entry from the vpc map
  region_key = keys(var.vpc)[0]
  region_cfg = var.vpc[local.region_key]

  # Zones for round-robin instance placement
  zones = local.region_cfg.zones

  # Workspace used to look up STM remote state — follows the current SRT workspace
  stm_workspace = terraform.workspace

  # STM network tag — mirrors STM's local.network_tag ("${workspace}-stress-testing-manager").
  # Passed into module fwrule (extra_ssh_source_tags) so STM VMs can SSH into SRT instances.
  stm_network_tag = "${local.stm_workspace}-stress-testing-manager"

  # Network identifiers — STM VPC + STM subnet (both via remote state).
  # SRT reuses the STM subnet in local.region_key; it does not create its own.
  # A missing region key here fails at plan time with a map-lookup error.
  resolved_vpc_id           = data.terraform_remote_state.stm.outputs.vpc_id
  resolved_subnet_self_link = data.terraform_remote_state.stm.outputs.subnet_self_links[local.region_key]

  # SnarkOS network name (used in health checks and outputs)
  snarkos_network = "testnet"

  # SSH metadata — OS Login is disabled unconditionally. The shared
  # devnet-key.pub at repo root is always injected for var.ssh_user
  # (default: ubuntu). If var.ssh_public_key is also set, it is layered
  # on top as an additional authorized key for the same user.
  devnet_public_key = trimspace(file("${path.root}/../../../devnet-key.pub"))
  ssh_metadata = {
    enable-oslogin = "FALSE"
    ssh-keys       = var.ssh_public_key != "" ? "${var.ssh_user}:${local.devnet_public_key}\n${var.ssh_user}:${trimspace(var.ssh_public_key)}" : "${var.ssh_user}:${local.devnet_public_key}"
  }
}
