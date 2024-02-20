variable "regions" {
  description = "List of regions for deployment"
  default     = ["us-west-2", "us-west-1", "us-east-1", "us-east-2"]
}

variable "validator_count" {
  description = "Number of validator instances to create in one region"
  default     = 25
}

variable "client_count" {
  description = "Number of client instances to create in each region but the validator region"
  default     = 50
}

variable "instance_type" {
  description = "Type of instance to deploy"
  default     = "m5.4xlarge"
  #default     = "m5.large"
}

variable "instance_type_client" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}
