resource "aws_iam_policy" "snarkos_s3_access" {
  name        = "SnarkOS-S3-Access-Policy"
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
          "arn:aws:s3:::${var.RELEASE_BUCKET}",
          "arn:aws:s3:::${var.RELEASE_BUCKET}/*"
        ]
      }
    ]
  })
}
