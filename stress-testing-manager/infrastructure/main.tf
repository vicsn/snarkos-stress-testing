resource "aws_instance" "stress_testing_manager" {
  ami                         = data.aws_ami.latest_stress_testing_manager_base_ubuntu.id
  instance_type               = "t3a.large"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.stress_testing_manager_main_key.key_name

  iam_instance_profile = aws_iam_instance_profile.stress_testing_manager_instance_profile.name

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 100
    volume_type = "gp2"
  }

  vpc_security_group_ids      = [
    aws_security_group.aleo_stress_testing_manager.id,
    aws_security_group.allow_out.id
  ]

  tags = {
    Name = "Stress Testing Manager${local.name_suffix}"
  }
}

resource "null_resource" "run_at_end_stress_testing_manager" {
  provisioner "local-exec" {
    command = <<-EOF
      until nc -z -v -w5 ${aws_instance.stress_testing_manager.public_ip} 22
      do
        echo "Waiting for ${aws_instance.stress_testing_manager.public_ip} to be ready..."
        sleep 2
      done
      ssh-keyscan -H ${aws_instance.stress_testing_manager.public_ip} >> ~/.ssh/known_hosts
    EOF
  }

  depends_on = [aws_instance.stress_testing_manager]
}

output "stress_testing_manager_public_ip" {
  description = "Public IP of the stress testing manager EC2 instance (for Ansible / SSH)."
  value       = aws_instance.stress_testing_manager.public_ip
}
