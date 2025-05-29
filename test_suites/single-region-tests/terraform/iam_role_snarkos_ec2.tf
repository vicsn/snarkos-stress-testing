resource "aws_iam_role" "snarkos_ec2_role" {
  name = "${var.owner}-SnarkOS-EC2-Role"

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

resource "aws_iam_role_policy_attachment" "snarkos_s3_access_attach" {
  role       = aws_iam_role.snarkos_ec2_role.name
  policy_arn = aws_iam_policy.snarkos_s3_access.arn
}
