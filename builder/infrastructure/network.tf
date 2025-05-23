resource "aws_vpc" "aleo_builder" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "aleo-builder-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.aleo_builder.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_internet_gateway" "aleo_builder_igw" {
  vpc_id = aws_vpc.aleo_builder.id
}

resource "aws_route_table" "to_internet" {
  vpc_id = aws_vpc.aleo_builder.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aleo_builder_igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
    subnet_id = aws_subnet.public.id
    route_table_id = aws_route_table.to_internet.id
}

#
# Security group and ingress rule to allow incoming ssh
#

resource "aws_security_group" "aleo_builder" {
  name        = "aleo_builder"
  description = "Security group for the Aleo builder"
  vpc_id      = aws_vpc.aleo_builder.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.aleo_builder.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "allow_api_ipv4" {
  security_group_id = aws_security_group.aleo_builder.id
  from_port         = 3030
  to_port           = 3030
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

#
# Ingress rule to allow incoming Aleo peer-2-peer traffic
#

#
# Ingress rule to allow incoming ICMP traffic
#

resource "aws_vpc_security_group_ingress_rule" "allow_aleo_icmp_ipv4" {
  security_group_id = aws_security_group.aleo_builder.id
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
  vpc_id      = aws_vpc.aleo_builder.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_out.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

