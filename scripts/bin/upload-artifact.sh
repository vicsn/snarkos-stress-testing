#!/usr/bin/env bash
# upload-artifact.sh — Package and upload the stress-testing repo to GCS.
#
# Produces two objects:
#   gs://<RELEASES_BUCKET>/stress-testing/stress-testing-<TS>.tar.gz  (versioned)
#   gs://<RELEASES_BUCKET>/stress-testing/latest.tar.gz               (pointer)
#
# The STM's Ansible playbook pulls `latest.tar.gz` during setup.
# Run from any directory; the tarball is scoped to the git-root.
set -euo pipefail

BUCKET="${RELEASES_BUCKET:-provable-binaries-releases}"
PREFIX="stress-testing"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARBALL="stress-testing-${TIMESTAMP}.tar.gz"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

echo "==> packaging ${REPO_ROOT} -> /tmp/${TARBALL}"
tar czf "/tmp/${TARBALL}" \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.terraform' \
  --exclude='.terraform.lock.hcl' \
  --exclude='target' \
  --exclude='__pycache__' \
  --exclude='.venv*' \
  --exclude='node_modules' \
  --exclude='devnet-key*' \
  --exclude='stress-testing-manager-ip.txt' \
  --exclude='*.tfstate' \
  --exclude='*.tfstate.backup' \
  --exclude='log_files' \
  --exclude='graphify-out' \
  --exclude='.agents' \
  --exclude='.codegraph' \
  --exclude='.omo' \
  --exclude='.opencode' \
  --exclude='.claude' \
  --exclude='.graphifyignore' \
  --exclude='vars.*.yaml' \
  -C "$REPO_ROOT" .

echo "==> uploading gs://${BUCKET}/${PREFIX}/${TARBALL}"
gcloud storage cp "/tmp/${TARBALL}" "gs://${BUCKET}/${PREFIX}/${TARBALL}"

echo "==> updating gs://${BUCKET}/${PREFIX}/latest.tar.gz"
gcloud storage cp "/tmp/${TARBALL}" "gs://${BUCKET}/${PREFIX}/latest.tar.gz"

echo ""
echo "Uploaded: gs://${BUCKET}/${PREFIX}/${TARBALL}"
echo "Latest:   gs://${BUCKET}/${PREFIX}/latest.tar.gz"

rm -f "/tmp/${TARBALL}"
