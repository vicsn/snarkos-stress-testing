#!/usr/bin/env bash
# lib/unlock-state.sh — release a stale terraform state lock (GCS backend).
#
#   scripts/lib/unlock-state.sh          # show who holds the lock, confirm, unlock
#   scripts/lib/unlock-state.sh --force  # skip the confirmation prompt
#
# The GCS backend identifies a lock by the lock object's *generation number*,
# not by the UUID terraform prints as `ID:` in the error — hand-typing that
# UUID fails with "Lock ID should be numerical value". This looks the
# generation up itself, shows who has held the lock and for how long, refuses
# while a terraform process is still alive, and only then force-unlocks.
#
# Like every other entrypoint it runs on the manager (see lib/stm.sh): that is
# where runs hold the lock, and where the terraform working directory is
# already initialised against this backend. STM_LOCAL=1 runs it here instead,
# for when SSH to the manager is down.
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) die "Unknown argument: $arg (usage: $(basename "$0") [--force])" ;;
  esac
done
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

command -v gcloud >/dev/null || die "gcloud is required to read the lock object."
cd "$PARENT_DIR/terraform"

# Backend coordinates come from provider.tf, so this can never act on another
# suite's state.
BUCKET="$(awk -F'"' '/^[[:space:]]*bucket[[:space:]]*=/ {print $2; exit}' provider.tf)"
PREFIX="$(awk -F'"' '/^[[:space:]]*prefix[[:space:]]*=/ {print $2; exit}' provider.tf)"
[[ -n "$BUCKET" && -n "$PREFIX" ]] \
  || die "Could not read the GCS backend bucket/prefix from terraform/provider.tf."

# -reconfigure, not the plain tf_init used by the run path: this only ever
# reads/removes a lock object, so adopting the backend declared in provider.tf
# is always right. It also side-steps "Backend configuration changed" from a
# working directory last initialised against a different backend.
terraform init -input=false -reconfigure >/dev/null \
  || die "terraform init -reconfigure failed; fix that before unlocking."
WORKSPACE="$(terraform workspace show 2>/dev/null || echo default)"
LOCK_URI="gs://${BUCKET}/${PREFIX}/${WORKSPACE}.tflock"

# Absent object means no lock; any other failure (auth, permissions) must not
# be mistaken for one.
if ! GENERATION="$(gcloud storage objects describe "$LOCK_URI" --format='value(generation)' 2>&1)"; then
  if grep -qiE 'not found|404|does not exist' <<<"$GENERATION"; then
    echo "No lock object at ${LOCK_URI} — the state is not locked. Nothing to do."
    exit 0
  fi
  die "Could not read ${LOCK_URI}: ${GENERATION}"
fi

echo
echo "Lock object : ${LOCK_URI}"
echo "Generation  : ${GENERATION}   <- the ID terraform actually wants"
gcloud storage cat "$LOCK_URI" 2>/dev/null | python3 -c '
import json, re, sys
from datetime import datetime, timezone
try:
    lock = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in ("Who", "Operation", "Version", "Info", "ID"):
    if lock.get(key):
        print(f"{key:<12}: {lock[key]}")
created = lock.get("Created", "")
if created:
    label = "Created"
    iso = re.sub(r"(\.\d{6})\d+", r"\1", created).replace("Z", "+00:00")
    try:
        minutes = (datetime.now(timezone.utc) - datetime.fromisoformat(iso)).total_seconds() / 60
        print(f"{label:<12}: {created}  ({minutes:.0f} min ago)")
    except ValueError:
        print(f"{label:<12}: {created}")
' || echo "(could not parse lock metadata)"
echo

# Liveness: a lock held by a *running* apply must never be broken. We are on
# the host that runs terraform (the manager), so a local process check is the
# direct signal; compare it against the `Who` field above.
RUNNING_PROCS="$(pgrep -fl terraform 2>/dev/null || true)"
if [[ -n "$RUNNING_PROCS" ]]; then
  echo "terraform still appears to be RUNNING on $(hostname):"
  printf '  %s\n' "$RUNNING_PROCS"
  (( FORCE )) \
    || die "Refusing to unlock while terraform is running — stop it first, or re-run with --force if you are certain."
  echo "WARNING: --force given; unlocking anyway."
fi

if (( ! FORCE )); then
  [[ -t 0 ]] || die "No TTY to confirm on; re-run with --force."
  read -r -p "Force-unlock ${LOCK_URI}? [y/N]: " answer
  [[ "$answer" =~ ^[yY]$ ]] || { echo "Aborted; lock left in place."; exit 1; }
fi

terraform force-unlock -force "$GENERATION"

gcloud storage objects describe "$LOCK_URI" >/dev/null 2>&1 \
  && die "Lock object is still present at ${LOCK_URI}; the unlock did not take effect."
echo "State unlocked. Re-run your provision now."
