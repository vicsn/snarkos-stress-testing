data "terraform_remote_state" "stm" {
  backend   = "gcs"
  workspace = local.stm_workspace

  config = {
    bucket = "tfstate-snarkos-stress-testing"
    prefix = "stress-testing-manager"
  }
}
