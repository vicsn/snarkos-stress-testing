variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "ami_id" {
  description = "The ami id"
}

variable "key_name" {
  description = "The key name"
}

variable "sec_group_name" {
  description = "The security group"
}

variable "devnet_name" {
  description = "The devnet"
}

variable "owner" {
  description = "The deployment owner"
}

resource "aws_iam_role" "tx_cannon_service_node_ec2_role" {
  name = "${var.owner}-TXCannon-Service-EC2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "tx_cannon_node_s3_access" {
  name        = "${var.owner}-TXCannon-S3-Access-Policy"
  description = "Allows SnarkOS EC2 instances to access the S3 bucket for binaries."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "tx_cannon_node_ecr_access" {
  name        = "${var.owner}-TXCannon-ECR-Access-Policy"
  description = "Allows SnarkOS EC2 instances to access ECR for tx-cannon docker containers."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tx_cannon_node_access_attach" {
  role       = aws_iam_role.tx_cannon_service_node_ec2_role.name
  policy_arn = aws_iam_policy.tx_cannon_node_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "tx_cannon_node_ecr_access_attach" {
  role       = aws_iam_role.tx_cannon_service_node_ec2_role.name
  policy_arn = aws_iam_policy.tx_cannon_node_ecr_access.arn
}

resource "aws_iam_instance_profile" "tx_cannon_service_node_ec2_instance_profile" {
  name = "${var.owner}-TXCannon-Service-EC2-Instance-Profile"
  role = aws_iam_role.tx_cannon_service_node_ec2_role.name
}

resource "aws_instance" "tx_cannon_service_node" {
  count         = var.tx_cannon_instance_count
  ami           = var.ami_id
  instance_type = var.tx_cannon_instance_type
  key_name      = var.key_name
  iam_instance_profile = aws_iam_instance_profile.tx_cannon_service_node_ec2_instance_profile.name

  security_groups = [var.sec_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20  # Adjust the volume size if needed
  }

  tags = {
    Name   = "${var.owner}-tx-cannon-node-${count.index}"
    Role   = "tx-cannon-node"
    Owner  = "${var.owner}"
    Dev    = count.index
    Devnet = var.devnet_name
  }
}
