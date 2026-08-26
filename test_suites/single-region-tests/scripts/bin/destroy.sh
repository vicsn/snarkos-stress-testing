#!/usr/bin/env bash
# bin/destroy.sh — tear down provisioned infrastructure.
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
pueue_dispatch_self "destroy" -- "$0" "${ORIG_ARGS[@]}"

# No EXIT-trap log collection here: a destroy failure shouldn't try to pull logs
# off machines that may be half-gone. Still report status to Slack.
notify_job_begin "destroy"
trap 'notify_job_end $?' EXIT

echo "Destroying infrastructure..."
cd "$PARENT_DIR"

# IMPORTANT: destroy_infra.sh derives its own location from $0 (not BASH_SOURCE).
# If we *source* it, $0 is this entrypoint (scripts/bin/destroy.sh) and it builds
# scripts/bin/terraform. Run it as its own process so $0 is destroy_infra.sh and
# its internal `dirname "$0"` resolves back to the project root. Exported env
# (OWNER, GCP_*, TF_*) propagates to the child; export the helper functions too
# in case it calls into any of them.
export -f set_network_vars run_test run_utility common_ansible \
          download_and_upload_logs prepare_log_files_dir runner_manages_logs \
          notify_enabled _slack_post notify_job_begin notify_job_end die isuint

bash "$PARENT_DIR/destroy_infra.sh" "$@"
