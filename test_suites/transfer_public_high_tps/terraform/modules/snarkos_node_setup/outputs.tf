output "instance_ips" {
  value = aws_instance.snarkos_node.*.public_ip
}

output "snarkos_lb_dns_name" {
  value = aws_elb.snarkos_lb.dns_name
}