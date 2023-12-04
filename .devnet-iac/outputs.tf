# outputs.tf
output "instance_ips" {
  value = aws_instance.snarkos_node.*.public_ip
}