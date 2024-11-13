resource "aws_iam_instance_profile" "snarkos_ec2_instance_profile" {
  name = "SnarkOS-EC2-Instance-Profile"
  role = aws_iam_role.snarkos_ec2_role.name
}