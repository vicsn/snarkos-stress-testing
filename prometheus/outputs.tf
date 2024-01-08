# outputs.tf
output "prometheus_server" {
  value = aws_instance.prometheus_server.public_ip
}
