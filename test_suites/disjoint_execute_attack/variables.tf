variable "regions" {
  description = "List of regions for deployment"
  default     = ["us-west-2", "us-west-1"]
}

variable "validator_count" {
  description = "Number of validator instances to create in one region"
  default     = 25
}

variable "instance_type" {
  description = "Type of instance to deploy"
  default     = "m5.4xlarge"
}

variable "instance_type_tx_cannon" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}
