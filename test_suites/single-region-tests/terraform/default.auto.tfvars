# GCP Project ID
gcp_project = "protocol-development-sandbox"
gcp_region  = "us-central1"

#
# @env: DEVNET_NAME
# override with `DEVNET_NAME="" ; TF_VARS_devnet_name=$DEVNET_NAME`
#
#   * local tests                     DEVNET_NAME="single-region-tests"
#   * automatic pre-release tests     DEVNET_NAME="prerelease-devnet"
#   * ?? custom / special override    DEVNET_NAME="my_devnet"
#
devnet_name = "single-region-tests"

# number of instances
validator_instance_count = 1
client_instance_count    = 0
prover_instance_count    = 0

# # define machine types
# validator_instance_type  = "c3d-standard-30"
# client_instance_type     = "c3d-standard-8"
# prover_instance_type     = "c3d-standard-8"
# tx_runner_instance_type  = "c3d-standard-30"

release_bucket = "provable-binaries-releases"

# Packer-built base image (use ubuntu-2204-lts / ubuntu-os-cloud for stock)
image_family  = "stress-test-base"
image_project = "protocol-development-sandbox"

vpc = {
  "us-central1" = {
    zones = ["us-central1-b", "us-central1-c", "us-central1-f"]
  }
}

# Admin users with compute and monitoring access
admin_users = [
  "group:gcp-engineering-viewer@provable.com",
  "user:mikenichols@provable.com"
]
