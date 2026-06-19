#!/usr/bin/env bash
# Create the repo-root devnet-key pair if absent (used by Terraform + Ansible).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="$REPO_ROOT/devnet-key"
if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t rsa -b 4096 -f "$KEY" -N ''
  chmod 400 "$KEY"
fi
