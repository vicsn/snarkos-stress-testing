resource "aws_instance" "tx_runner" {
  ami           = module.stress_base_ami.ami_id
  instance_type = var.tx_runner_instance_type
  key_name      = aws_key_pair.generated_key.key_name
  security_groups = [module.sg.security_group_name]

  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 128
    volume_type = "gp3"
  }

  tags = {
    Name   = "${var.owner}-${var.devnet_name}-tx-runner"
    Role   = "tx-runner"
    Owner  = "${var.owner}"
    Devnet = var.devnet_name
  }
}
