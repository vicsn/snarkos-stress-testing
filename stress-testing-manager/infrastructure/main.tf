resource "aws_instance" "stress_testing_manager" {
  ami                         = data.aws_ami.latest_stress_testing_manager_base_ubuntu.id
  instance_type               = "t2.xlarge"
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
    Name = "Stress Testing Manager"
  }
}

resource "null_resource" "run_at_end_stress_testing_manager" {
  provisioner "local-exec" {
    command = <<-EOF
      until nc -z -v -w5 ${aws_instance.stress_testing_manager.public_ip} 22
      do
        echo "Waiting for $ip to be ready..."
        sleep 2
      done
      ssh-keyscan -H ${aws_instance.stress_testing_manager.public_ip} >> ~/.ssh/known_hosts
    EOF
  }

  depends_on = [aws_instance.stress_testing_manager]
}

resource "random_id" "random" {
  keepers = {
    uuid = uuid()
  }
  byte_length = 8
}

resource "null_resource" "ansible_provisioner" {
  triggers = {
    always = random_id.random.hex
  }

  provisioner "local-exec" {
    command = <<-EOF
      until nc -z -v -w5 ${aws_instance.stress_testing_manager.public_ip} 22
      do
        echo "Waiting for $ip to be ready..."
        sleep 2
      done
      ansible-playbook --extra-vars "github_token=${var.github_token}" \
            --extra-vars "slack_channel_id=${var.SLACK_CHANNEL_ID}" --extra-vars "slack_token=${var.SLACK_TOKEN}" \
              --extra-vars "releases_bucket=${var.RELEASES_BUCKET}" --extra-vars "results_bucket=${var.RESULTS_BUCKET}" \
                --extra-vars "elastic_cloud_id=${var.ELASTIC_CLOUD_ID}" --extra-vars "elastic_api_key=${var.ELASTIC_API_KEY}" --extra-vars "grafana_cloud_api_key=${var.GRAFANA_CLOUD_API_KEY}" \
                -i ${aws_instance.stress_testing_manager.public_ip}, playbook.yml
    EOF
    working_dir = "${path.module}/ansible"
  }

  depends_on = [aws_instance.stress_testing_manager]
}
