variable "tx_sender_instance_type" {
  description = "Instance type for tx-sender nodes"
  default     = "m5.2xlarge"
}

variable "tx_sender_instance_count" {
  description = "Number of tx-sender nodes"
  default     = 0
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

resource "aws_iam_role" "tx_sender_service_node_ec2_role" {
  name = "${var.owner}-tx-sender-ec2-role"

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

resource "aws_iam_policy" "tx_sender_node_s3_access" {
  name        = "${var.owner}-tx-sender-s3-access-policy"
  description = "Allows SnarkOS EC2 instances for preparing and sending transactions to access the S3 bucket for binaries."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tx_sender_node_access_attach" {
  role       = aws_iam_role.tx_sender_service_node_ec2_role.name
  policy_arn = aws_iam_policy.tx_sender_node_s3_access.arn
}

resource "aws_iam_instance_profile" "tx_sender_service_node_ec2_instance_profile" {
  name = "${var.owner}-tx-sender-service-instance-profile"
  role = aws_iam_role.tx_sender_service_node_ec2_role.name
}

resource "aws_instance" "tx_sender_service_node" {
  count         = var.tx_sender_instance_count
  ami           = var.ami_id
  instance_type = var.tx_sender_instance_type
  key_name      = var.key_name
  iam_instance_profile = aws_iam_instance_profile.tx_sender_service_node_ec2_instance_profile.name

  security_groups = [var.sec_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 32
  }

  tags = {
    Name   = "${var.owner}-tx-sender-node-${count.index}"
    Role   = "tx-sender-node"
    Owner  = "${var.owner}"
    Dev    = count.index
    Devnet = var.devnet_name
  }
}
