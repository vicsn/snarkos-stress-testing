output "snarkos_node_public_ips" {
  value = [for instance in aws_instance.snarkos_node : instance.public_ip]
  description = "Public IP addresses of SnarkOS nodes"
}

output "snarkos_lb_dns_name" {
  value = aws_elb.snarkos_lb.dns_name
}