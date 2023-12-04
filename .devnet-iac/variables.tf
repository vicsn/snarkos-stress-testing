variable "instance_count" {
  default = 5
}

variable "instance_type" {
  default = "m5.2xlarge"
}

variable "key_pair_name" {
  description = "The name of the AWS key pair to be used for the EC2 instances"
  type        = string
  default     = "s3-testnet3"
}
