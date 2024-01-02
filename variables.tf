variable "aws_region" {
<<<<<<< HEAD:.devnet-iac/variables.tf
  default     = "us-east-2"
=======
  default     = "us-west-2"
>>>>>>> main:variables.tf
}

variable "instance_type" {
  default = "m5.4xlarge"
}

variable "instance_count" {
  default = 5
}

variable "key_pair_name" {
  default     = "devnet-ansible"
}
