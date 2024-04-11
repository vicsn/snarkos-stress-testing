variable "instance_type" {
  description = "Instance type for snarkOS nodes"
  default     = "m5.4xlarge"
}

variable "instance_count" {
  description = "Number of snarkOS nodes"
  default     = 10
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.4xlarge"
}

variable "tx_cannon_bond_instance_count" {
  description = "Number of tx-cannon bond nodes"
  default     = 10
}

variable "tx_cannon_unbond_instance_count" {
  description = "Number of tx-cannon unbond nodes"
  default     = 10
}