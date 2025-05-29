# EC2 Instance Connect IAM Policy
# Uncomment and run this code if you want to set up EC2 Instance Connect for a specific Devnet

# This policy allows EC2 Instance Connect for instances tagged with a specific Devnet name
# After setting this up, the root account needs to create a permission set and grant access to users

# resource "aws_iam_policy" "ec2_instance_connect" {
#   name        = "${var.owner}-${var.devnet_name}-ec2-instance-connect-policy"
#   path        = "/"
#   description = "Policy to allow EC2 Instance Connect for specific Devnet"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "ec2-instance-connect:SendSSHPublicKey"
#         ]
#         Resource = "arn:aws:ec2:*:*:instance/*"
#         Condition = {
#           StringEquals = {
#             "ec2:ResourceTag/Devnet": var.devnet_name
#           }
#         }
#       },
#     ]
#   })
# }

# After running this code, follow these steps to grant user access:

# 1. Go to the IAM Identity Center in the AWS Console
# 2. Create a new Permission Set:
#    - Add "ReadOnlyAccess" from AWS managed policies
#    - Add the customer managed policy created above (e.g., "mydevnet-ec2-instance-connect-policy")
# 3. Assign users who need EC2 access to the account with this new Permission Set
