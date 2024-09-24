variable "aws_region" {
  default     = "us-west-1"
}

variable "instance_type" {
  default = "m5.4xlarge"
}

variable "instance_count" {
  default = 5
}

variable "key_pair_name" {
  default     = "devnet-key"
}
