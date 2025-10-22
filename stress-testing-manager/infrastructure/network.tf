#
# Security group and ingress rule to allow incoming ssh
#

resource "aws_security_group" "aleo_stress_testing_manager" {
  name        = "aleo_stress_testing_manager"
  description = "Security group for the Aleo stress_testing_manager"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.aleo_stress_testing_manager.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "allow_api_ipv4" {
  security_group_id = aws_security_group.aleo_stress_testing_manager.id
  from_port         = 3030
  to_port           = 3030
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

#
# Ingress rule to allow incoming ICMP traffic
#

resource "aws_vpc_security_group_ingress_rule" "allow_aleo_icmp_ipv4" {
  security_group_id = aws_security_group.aleo_stress_testing_manager.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "10.0.0.0/16"
}

#
# Security group and egress rule to allow outgoing traffic
#

resource "aws_security_group" "allow_out" {
  name        = "allow_out"
  description = "Allow outbound traffic"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_out.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

