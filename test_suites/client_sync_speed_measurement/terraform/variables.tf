variable "regions" {
  description = "List of regions for deployment"
  default     = ["us-west-2", "us-west-1", "us-east-1", "us-east-2", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ca-central-1", "eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1", "sa-east-1"]
}


variable "validator_count" {
  description = "Number of validator instances to create in one region"
  default     = 10
}

variable "attacker_tx_cannon_count" {
  description = "Number of tx cannon instances to create in each region but the validator region and the network driver region"
  default     = 3
}

variable "instance_type" {
  description = "Type of validator instance to deploy"
  default     = "m5.4xlarge"
}

variable "instance_type_client" {
  description = "Type of client instance to deploy"
  default     = "m5.4xlarge"
}

variable "instance_type_attacker_tx_cannon" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}
