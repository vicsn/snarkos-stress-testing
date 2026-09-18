#!/usr/bin/env bash
# Diagnose GCP CLI auth for this repo and print (or run) the missing commands.
#
# Two credential stores:
#   gcloud auth login                      — user creds for `gcloud storage`,
#                                            `gcloud compute`, OS Login SSH
#   gcloud auth application-default login  — ADC for terraform and packer
#
# `gcloud auth login --update-adc` refreshes both in one browser flow.
#
#   scripts/ensure_gcloud_auth.sh          # diagnose; print commands
#   scripts/ensure_gcloud_auth.sh --login  # run missing logins (needs a TTY)
#   scripts/ensure_gcloud_auth.sh --help
set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-protocol-development-sandbox}"
DO_LOGIN=0

usage() {
  cat <<EOF
ensure_gcloud_auth.sh — print (or run) the gcloud auth this repo needs.

Usage:
  $(basename "$0") [--login]

  --login   Run the missing interactive login(s). Requires a TTY.
  -h, --help

User credentials (\`gcloud auth login\`) are what \`gcloud storage ls\` uses.
ADC (\`gcloud auth application-default login\`) is what terraform/packer use.
Project should be ${GCP_PROJECT}.
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --login)   DO_LOGIN=1 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v gcloud >/dev/null; then
  echo "gcloud is not on PATH. Install the Cloud SDK, then rerun this script."
  echo "  brew install --cask google-cloud-sdk"
  exit 1
fi

user_ok=0
adc_ok=0
gcloud auth print-access-token >/dev/null 2>&1 && user_ok=1
gcloud auth application-default print-access-token >/dev/null 2>&1 && adc_ok=1

account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
project="$(gcloud config get-value project 2>/dev/null || true)"
[[ "$project" == "(unset)" ]] && project=""

echo "gcloud CLI (user):  $( ((user_ok)) && echo "OK (${account:-active})" || echo "MISSING — needed for gcloud storage / compute")"
echo "ADC (terraform):    $( ((adc_ok)) && echo OK || echo "MISSING — needed for terraform / packer")"
echo "project:            ${project:-UNSET}  (want ${GCP_PROJECT})"

need_user=0 need_adc=0 need_project=0
(( user_ok )) || need_user=1
(( adc_ok )) || need_adc=1
[[ "$project" == "$GCP_PROJECT" ]] || need_project=1

if (( need_user == 0 && need_adc == 0 && need_project == 0 )); then
  echo "Auth looks good."
  exit 0
fi

echo
echo "Run:"
if (( need_user && need_adc )); then
  echo "  gcloud auth login --update-adc"
elif (( need_user )); then
  echo "  gcloud auth login"
elif (( need_adc )); then
  echo "  gcloud auth application-default login"
fi
if (( need_project )); then
  echo "  gcloud config set project ${GCP_PROJECT}"
fi

if (( DO_LOGIN == 0 )); then
  echo
  echo "Re-run with --login to execute those commands (opens a browser)."
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "ERROR: --login needs an interactive TTY (browser prompt)." >&2
  exit 1
fi

if (( need_user && need_adc )); then
  gcloud auth login --update-adc
elif (( need_user )); then
  gcloud auth login
elif (( need_adc )); then
  gcloud auth application-default login
fi
if (( need_project )); then
  gcloud config set project "${GCP_PROJECT}"
fi
echo "Auth updated."
