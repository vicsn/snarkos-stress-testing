resource "aws_iam_role" "stress_testing_manager_role" {
  name = "aws_iam_stress_testing_manager_role${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy" "stress_testing_manager_access_policy" {
  name = "stress_testing_manager_access_policy${local.name_suffix}"
  role = aws_iam_role.stress_testing_manager_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "ec2:DescribeAddresses",
          "ec2:DescribeCoipPools",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeClassicLinkInstances",
          "ec2:DescribeVpcClassicLink",
          "ec2:CreateSecurityGroup",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:GetCoipPoolUsage",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:AllocateAddress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:AssignIpv6Addresses",
          "ec2:ReleaseAddress",
          "ec2:UnassignIpv6Addresses",
          "ec2:DescribeVpcPeeringConnections",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "outposts:GetOutpostInstanceTypes",
          "iam:AttachRolePolicy",
          "iam:CreateRole",
          "iam:CreatePolicy",
          "iam:PutRolePolicy",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "stress_testing_manager_iam_policy" {
  name = "stress_testing_manager_iam_policy${local.name_suffix}"
  role = aws_iam_role.stress_testing_manager_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "iam:AttachRolePolicy",
          "iam:AddRoleToInstanceProfile",
          "iam:CreateRole",
          "iam:CreatePolicy",
          "iam:CreateInstanceProfile",
          "iam:PutRolePolicy",
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GetInstanceProfile",
          "iam:ListRolePolicies",
          "iam:ListPolicyVersions",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:PassRole",
          "iam:DeleteRole",
          "iam:DeletePolicy",
          "iam:DeleteInstanceProfile",
          "iam:DetachRolePolicy",
          "iam:RemoveRoleFromInstanceProfile"

        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "power_user_attachement" {
  role       = aws_iam_role.stress_testing_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

#
# Attach the role to an instance profile, which will be linked to your EC2 instances
#

resource "aws_iam_instance_profile" "stress_testing_manager_instance_profile" {
  name = "stress_testing_manager_instance_profile${local.name_suffix}"
  role = aws_iam_role.stress_testing_manager_role.name
}
