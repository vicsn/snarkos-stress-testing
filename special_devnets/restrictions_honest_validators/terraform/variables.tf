variable "instance_type" {
  description = "Instance type for snarkOS nodes"
  default     = "m5.4xlarge"
}

variable "instance_count" {
  description = "Number of snarkOS validator nodes"
  default     = 10
}

variable "client_instance_count" {
  description = "Number of client nodes"
  default     = 0
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.4xlarge"
}

# ------------------------------------------------
# Cannons

variable "tx_cannon_types" {
  description = "Map of tx-cannon node types and their instance counts"
  type = map(object({
    instance_count = number
  }))
  default = {
    batchtransfer       = { instance_count = 1 }
    networkdriver         = { instance_count = 1 }
  }
}

locals {
  tx_cannon_instances = toset(flatten([
    for type, specs in var.tx_cannon_types : [
      for i in range(specs.instance_count) : {
        type  = type
        index = i
      }
    ]
  ]))
}
