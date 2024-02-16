provider "aws" {
  alias  = "west1"
  region = "us-west-1"
}

provider "aws" {
  alias  = "west2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "east1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "east2"
  region = "us-east-2"
}

module "snarkos_node_setup_west1" {
  providers = {
    aws = aws.west1
  }
  source        = "./modules/snarkos_node_setup"
  region        = "us-west-1"
  instance_count = var.validator_count
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name
  region_index = 0
}

module "snarkos_node_setup_west2" {
  providers = {
    aws = aws.west2
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-west-2"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 1
  validator_count = var.validator_count
}

module "snarkos_node_setup_east1" {
  providers = {
    aws = aws.east1
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-east-1"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 2
  validator_count = var.validator_count
}

module "snarkos_node_setup_east2" {
  providers = {
    aws = aws.east2
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-east-2"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 3
  validator_count = var.validator_count
}
