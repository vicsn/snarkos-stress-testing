# ------------------------------------------------
# Generated key to be used for ssh access to the nodes

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.owner}-tx-cannon-devnet-key"
  public_key = file("../${path.module}/devnet-key.pub")
}

# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source = "./modules/stress_base_ami"
}

module "sg" {
  source      = "./modules/security_group"
  name        = "${var.owner}-tx-cannon-sg"
  description = "Security group for tx-cannons"
}

variable "deployment_mode" {
  description = "Only one of 'tx-cannon' or 'tx-sender' can be active"
  type        = string
  default     = "tx-cannon"
  validation {
    condition     = var.deployment_mode == "tx-cannon" || var.deployment_mode == "tx-sender"
    error_message = "deployment_mode must be either 'tx-cannon' or 'tx-sender'"
  }
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

variable "tx_sender_instance_count" {
  description = "Number of tx-sender nodes"
  default     = 0
}

variable "tx_sender_instance_type" {
  description = "Instance type for tx-sender nodes"
  default     = "m5.large"
}

variable "owner" {
  description = "The deployment owner"
}

module "tx-cannon" {
  source = "./modules/tx-cannon"
  count  = var.deployment_mode == "tx-cannon" ? 1 : 0
  ami_id = module.stress_base_ami.ami_id
  key_name = aws_key_pair.generated_key.key_name
  sec_group_name = module.sg.security_group_name
  devnet_name = var.devnet_name
  owner = var.owner
  tx_cannon_instance_count = var.tx_cannon_instance_count
  tx_cannon_instance_type = var.tx_cannon_instance_type
}

module "tx-sender" {
  source = "./modules/tx_sender"
  count  = var.deployment_mode == "tx-sender" ? 1 : 0
  ami_id = module.stress_base_ami.ami_id
  key_name = aws_key_pair.generated_key.key_name
  sec_group_name = module.sg.security_group_name
  devnet_name = var.devnet_name
  owner = var.owner
  tx_sender_instance_count = var.tx_sender_instance_count
  tx_sender_instance_type = var.tx_sender_instance_type
}

variable "devnet_name" {
  description = "Unique name for this devnet deployment"
  default     = "single-region-tests"
}
