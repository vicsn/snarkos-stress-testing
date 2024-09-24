output "instance_public_ips" {
  value = aws_instance.attacker_tx_cannon_node.*.public_ip
}