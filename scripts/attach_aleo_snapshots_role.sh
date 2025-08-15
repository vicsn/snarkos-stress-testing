#!/bin/bash

ROLE=AleoSnapshotsRole
PROFILE=AleoSnapshotsRole
INSTANCE_ID=$1
REGION=us-west-2

# Get the profile ARN (used for matching)
PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name "$PROFILE" \
  --query 'InstanceProfile.Arn' --output text)

echo "Profile ARN: $PROFILE_ARN"

# Remove any instance profiles if any
for A in $(aws ec2 describe-iam-instance-profile-associations --region "$REGION" \
  --filters Name=instance-id,Values="$INSTANCE_ID" \
  --query 'IamInstanceProfileAssociations[].AssociationId' --output text); do
  echo "Disassociating $A"
  aws ec2 disassociate-iam-instance-profile --region "$REGION" --association-id "$A"
done

# Wait until the profile is not associated ANYWHERE
echo "Waiting for profile to be fully free..."
while true; do
  INUSE=$(aws ec2 describe-iam-instance-profile-associations --region "$REGION" \
    --query "length(IamInstanceProfileAssociations[?IamInstanceProfile.Arn=='\`$PROFILE_ARN\`' && State!='disassociated'])" \
    --output text)
  if [ "$INUSE" = "0" ]; then break; fi
  sleep 3
done

# 3 Ensure the role is in the profile.
#    If it errors with RolesPerInstanceProfile:1, it already has a role; inspect & adjust.
aws iam add-role-to-instance-profile \
  --instance-profile-name "$PROFILE" \
  --role-name "$ROLE" || {
    echo "add-role failed; showing current roles in profile:"
    aws iam get-instance-profile --instance-profile-name "$PROFILE" \
      --query 'InstanceProfile.Roles[].RoleName'
  }

# 4 Re-associate the profile to the instance
aws ec2 associate-iam-instance-profile --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --iam-instance-profile Arn="$PROFILE_ARN"

# 5 On the instance (after ~30–60s propagation), verify:
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
aws sts get-caller-identity
aws s3 ls

