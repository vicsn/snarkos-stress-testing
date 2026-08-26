#!/usr/bin/env bash
# build-packer-image.sh
#
# Build the Packer base image (`stress-test-base` family) for the
# snarkos-stress-testing framework.
#
# Runs `packer init` and `packer build` against
# `packer/stress-test-base.pkr.hcl`. Output: a new image in family
# `stress-test-base` in project `protocol-development-sandbox`.
# Duration: ~14 minutes.
#
# Prerequisites:
#   - packer               (brew install hashicorp/tap/packer)
#   - ansible-playbook     (packer's Ansible provisioner; pip install ansible)
#   - gcloud + ADC         (gcloud auth application-default login)
#
# Usage:
#   .agents/skills/snarkos-stress-testing/resources/build-packer-image.sh
#
# The build streams to stdout AND to a timestamped log file under
# $HOME/tmp/packer-builds/ so you can `tail -f` it from another shell.
#
# Env-var overrides (all optional):
#   REPO_ROOT       Path to the repo root  (default: git rev-parse --show-toplevel)
#   PACKER_LOG_DIR  Directory for logs     (default: $HOME/tmp/packer-builds)
#   NETWORK         GCP VPC                (default: template default `vpc-protocol-development-sandbox`)
#   SUBNETWORK      GCP subnet             (default: `subnet-03-us-central1` — required
#                                           in custom-mode VPCs; the packer template
#                                           leaves it empty and would fail otherwise)
#   GCP_PROJECT     GCP project            (default: template default `protocol-development-sandbox`)
#   GCP_ZONE        GCP zone               (default: template default `us-central1-b`)

set -euo pipefail

# ---------------------------------------------------------------
# Config
# ---------------------------------------------------------------
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PACKER_LOG_DIR="${PACKER_LOG_DIR:-$HOME/tmp/packer-builds}"
SUBNETWORK="${SUBNETWORK:-subnet-03-us-central1}"

PACKER_DIR="$REPO_ROOT/packer"
TEMPLATE="stress-test-base.pkr.hcl"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$PACKER_LOG_DIR/stress-test-base-$STAMP.log"

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------
say "Preflight checks"

[[ -d "$PACKER_DIR" ]]              || fail "Packer directory not found: $PACKER_DIR"
[[ -f "$PACKER_DIR/$TEMPLATE" ]]    || fail "Template not found: $PACKER_DIR/$TEMPLATE"

command -v packer >/dev/null         || fail "packer not on PATH — install via: brew install hashicorp/tap/packer"
command -v ansible-playbook >/dev/null || fail "ansible-playbook not on PATH — pip install ansible"
command -v gcloud >/dev/null         || fail "gcloud not on PATH — install the Google Cloud SDK"

# ADC is what packer's googlecompute plugin uses (NOT gcloud user creds)
gcloud auth application-default print-access-token >/dev/null 2>&1 \
  || fail "GCP ADC not configured — run: gcloud auth application-default login"

mkdir -p "$PACKER_LOG_DIR"

# ---------------------------------------------------------------
# Build vars
# ---------------------------------------------------------------
VAR_ARGS=(-var "subnetwork=$SUBNETWORK")
[[ -n "${NETWORK:-}"     ]] && VAR_ARGS+=(-var "network=$NETWORK")
[[ -n "${GCP_PROJECT:-}" ]] && VAR_ARGS+=(-var "gcp_project=$GCP_PROJECT")
[[ -n "${GCP_ZONE:-}"    ]] && VAR_ARGS+=(-var "gcp_zone=$GCP_ZONE")

# ---------------------------------------------------------------
# Run
# ---------------------------------------------------------------
cd "$PACKER_DIR"

say "packer init $TEMPLATE"
packer init "$TEMPLATE" 2>&1 | tee -a "$LOG"

say "packer build ${VAR_ARGS[*]} $TEMPLATE"
say "This takes ~14 minutes. Log file: $LOG"
printf '    Tail from another shell:  tail -f %s\n\n' "$LOG"

packer build "${VAR_ARGS[@]}" "$TEMPLATE" 2>&1 | tee -a "$LOG"

# ---------------------------------------------------------------
# Verify
# ---------------------------------------------------------------
PROJECT="${GCP_PROJECT:-protocol-development-sandbox}"
say "Verifying new image via gcloud"
gcloud compute images describe-from-family stress-test-base \
  --project="$PROJECT" \
  --format='value(name,creationTimestamp,selfLink)' \
  | tee -a "$LOG"

say "Build complete. Full log: $LOG"
