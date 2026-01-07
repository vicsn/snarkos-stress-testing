locals {
  env          = terraform.workspace
  is_default   = terraform.workspace == "default"

  name_suffix  = local.is_default ? "" : "-${local.env}"   # "" for the default workspace, "-staging" for staging
}
