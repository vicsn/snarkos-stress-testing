variable "regions" {
  description = "List of regions for deployment"
  default     = ["us-west-2", "us-west-1", "us-east-1", "us-east-2", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ca-central-1", "eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1", "ap-northeast-2", "sa-east-1", "ap-south-1"]
}

variable "validator_count" {
  description = "Number of validator instances to create in one region"
  default     = 10
}

variable "primary_client_count" {
  description = "Number of primary client instances to create in the 2 primary client regions"
  default     = 50
}

variable "secondary_client_count" {
  description = "Number of secondary client instances to create in each region but the validator and primary client regions"
  default     = 75
  }

variable "tertiary_client_count" {
  description = "Number of tertiary client instances to create in each region but the validator and primary client regions"
  default     = 75
  }

variable "instance_type" {
  description = "Type of instance to deploy"
  default     = "m5.4xlarge"
}

variable "instance_type_client" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "instance_type_secondary_client" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "instance_type_tertiary_client" {
  description = "Type of instance to deploy"
  default     = "m5.2xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}