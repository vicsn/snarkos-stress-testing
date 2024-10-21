# ------------------------------------------------
# Generated key to be used for ssh access to the nodes

resource "aws_key_pair" "generated_key" {
  key_name   = "tx-cannon-devnet-key"
  public_key = file("../${path.module}/devnet-key.pub")
}

# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source = "./modules/stress_base_ami"
}

module "sg" {
  source      = "./modules/security_group"
  name        = "tx-cannon-sg"
  description = "Security group for tx-cannons"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

module "tx-cannon" {
  source = "./modules/tx-cannon"
  count  = 1
  ami_id = module.stress_base_ami.ami_id
  key_name = aws_key_pair.generated_key.key_name
  sec_group_name = module.sg.security_group_name
  devnet_name = var.devnet_name
  tx_cannon_instance_count = var.tx_cannon_instance_count
  tx_cannon_instance_type = var.tx_cannon_instance_type
}

variable "devnet_name" {
  description = "Unique name for this devnet deployment"
  default     = "single-region-tests"
}