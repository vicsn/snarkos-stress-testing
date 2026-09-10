# ------------------------------------------------
# Workspace-aware naming.
#
# STM resources are prefixed with the current Terraform workspace.
# Default workspace produces `default-stress-testing-manager`;
# non-default workspaces (e.g. `staging`) produce `staging-stress-testing-manager`.

locals {
  # Workspace used as the naming prefix — mirrors snarkos-p2p-tests' local.stm_workspace
  stm_workspace = terraform.workspace

  instance_name = "${local.stm_workspace}-stress-testing-manager"
  network_tag   = "${local.stm_workspace}-stress-testing-manager"
  vpc_name      = "${local.stm_workspace}-stress-testing-manager-vpc"

  # Shared subnet CIDR. STM owns it; snarkos-p2p-tests reuses it via
  # terraform_remote_state (see
  # test_suites/snarkos-p2p-tests/terraform/locals.tf:resolved_subnet_self_link).
  stm_subnet_cidr = "10.41.0.0/16"
}
