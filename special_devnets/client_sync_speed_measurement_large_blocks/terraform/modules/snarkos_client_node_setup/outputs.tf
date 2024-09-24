output "instance_ips" {
  value = aws_instance.snarkos_client_node.*.public_ip
}

output "snarkos_client_lb_dns_name" {
  value = aws_elb.snarkos_client_lb.dns_name
}