output "instance_public_ips" {
  value = aws_instance.snarkos_secondary_client_node.*.public_ip
}