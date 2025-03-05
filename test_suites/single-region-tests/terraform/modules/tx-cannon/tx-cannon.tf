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

resource "aws_iam_role" "tx_cannon_node_ec2_role" {
  name = "TXCannon-EC2-Role"
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
  name        = "TXCannon-S3-Access-Policy"
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
        Resource = [
          "arn:aws:s3:::tx-cannons",
          "arn:aws:s3:::tx-cannons/*",
          "arn:aws:s3:::snarkos-releases-for-testing",
          "arn:aws:s3:::snarkos-releases-for-testing/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tx_cannon_node_access_attach" {
  role       = aws_iam_role.tx_cannon_node_ec2_role.name
  policy_arn = aws_iam_policy.tx_cannon_node_s3_access.arn
}

resource "aws_iam_instance_profile" "tx_cannon_node_ec2_instance_profile" {
  name = "TXCannon-EC2-Instance-Profile"
  role = aws_iam_role.tx_cannon_node_ec2_role.name
}

resource "aws_instance" "tx_cannon_node" {
  count         = var.tx_cannon_instance_count
  ami           = var.ami_id
  instance_type = var.tx_cannon_instance_type
  key_name      = var.key_name
  iam_instance_profile = aws_iam_instance_profile.tx_cannon_node_ec2_instance_profile.name

  security_groups = [var.sec_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20  # Adjust the volume size if needed
  }

  tags = {
    Name = "tx-cannon-node-${count.index}",
    Role = "tx-cannon-node",
    Dev = count.index
    Devnet = var.devnet_name
  }
}
