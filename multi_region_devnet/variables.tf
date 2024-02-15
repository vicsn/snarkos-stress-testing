variable "regions" {
  description = "List of regions for deployment"
  default     = ["us-west-2", "us-west-1"]
}

variable "instance_count" {
  description = "Number of instances to create in each region"
  default     = 5
}

variable "instance_type" {
  description = "Type of instance to deploy"
  default     = "m5.4xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}
