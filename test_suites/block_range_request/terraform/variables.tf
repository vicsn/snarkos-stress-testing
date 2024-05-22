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
  default     = 30
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
    batchtransfer       = { instance_count = 20 }
    batchdeploy         = { instance_count = 5 }
    invalidsolutions    = { instance_count = 5 }
    validsolutions      = { instance_count = 20 }
    rejectedaborted     = { instance_count = 5 }
    restrequester       = { instance_count = 10 }
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
