#!/bin/bash

BUCKET="provable-binaries-releases"
CUTOFF_DATE=$(date -v-20d -u +"%Y-%m-%dT%H:%M:%S")

echo "Deleting objects in '$BUCKET' older than $CUTOFF_DATE..."

aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --query "Contents[?LastModified<='${CUTOFF_DATE}'].Key" \
  --output text |
tr '\t' '\n' |
while read -r key; do
  if [ -n "$key" ]; then
    echo "Deleting: $key"
    aws s3api delete-object --bucket "$BUCKET" --key "$key"
  fi
done
