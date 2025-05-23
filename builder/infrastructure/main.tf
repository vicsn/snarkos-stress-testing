resource "aws_instance" "builder" {
  ami                         = data.aws_ami.latest_builder_base_ubuntu.id
  instance_type               = "t2.large"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.builder_main_key.key_name

  iam_instance_profile = aws_iam_instance_profile.builder_instance_profile.name

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 100
    volume_type = "gp2"
  }

  vpc_security_group_ids      = [
    aws_security_group.aleo_builder.id,
    aws_security_group.allow_out.id
  ]

  tags = {
    Name = "Aleo Builder"
  }
}

resource "null_resource" "run_at_end_builder" {
  provisioner "local-exec" {
    command = <<-EOF
      until nc -z -v -w5 ${aws_instance.builder.public_ip} 22
      do
        echo "Waiting for $ip to be ready..."
        sleep 2
      done
      ssh-keyscan -H ${aws_instance.builder.public_ip} >> ~/.ssh/known_hosts
    EOF
  }

  depends_on = [aws_instance.builder]
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
      until nc -z -v -w5 ${aws_instance.builder.public_ip} 22
      do
        echo "Waiting for $ip to be ready..."
        sleep 2
      done
      ansible-playbook --extra-vars "ARDBEG_SECRET=${var.ARDBEG_SECRET}" \
          --extra-vars "github_token=${var.github_token}" \
            --extra-vars "slack_channel_id=${var.SLACK_CHANNEL_ID}" --extra-vars "slack_token=${var.SLACK_TOKEN}" \
              --extra-vars "releases_bucket=${var.RELEASES_BUCKET}" --extra-vars "results_bucket=${var.RESULTS_BUCKET}" \
                --extra-vars "elastic_cloud_id=${vars.ELASTIC_CLOUD_ID}" --extra-vars "elastic_api_key=${vars.ELASTIC_API_KEY}" --extra-vars "grafana_cloud_api_key=${vars.GRAFANA_CLOUD_API_KEY}" \
                -i ${aws_instance.builder.public_ip}, playbook.yml
    EOF
    working_dir = "${path.module}/ansible"
  }

  depends_on = [aws_instance.builder]
}
