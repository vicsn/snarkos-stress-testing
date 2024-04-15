variable "instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.4xlarge"
}

variable "instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 6
}

variable "key_pair_name" {
  description = "The key pair name to be used for the instance"
}
