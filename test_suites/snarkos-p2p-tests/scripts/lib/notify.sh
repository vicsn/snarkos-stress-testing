#!/usr/bin/env bash
# lib/notify.sh — best-effort Slack notifications around meaningful steps.
#
# Sourced by lib/common.sh. Wraps notify_slack.sh. Design rules:
#   * Best-effort: a Slack failure NEVER fails a job.
#   * Quiet on stdout: only an *initial* post emits its thread ts, and only via
#     command substitution. Diagnostics go to stderr.
#   * Loud enough to debug: when the vars are set but the notifier can't be
#     found, or the API returns an error, say so on stderr (don't hide it).
#   * Thread-aware across processes: if SLACK_THREAD_TS is already in the
#     environment (full_run banner, or orchestrator enqueue), reuse it so
#     every job in a run replies in one thread. Otherwise open a fresh thread.
#
# Env knobs:
#   SLACK_TOKEN, SLACK_CHANNEL_ID (or CHANNEL_ID)  — required to enable.
#   NOTIFY_SLACK_DISABLED=1                         — force off.
#   NOTIFY_DEBUG=1                                  — print resolution/decisions.

[[ -n "${_NOTIFY_SH_SOURCED:-}" ]] && return 0
_NOTIFY_SH_SOURCED=1

# notify_slack.sh keys its default channel off $CHANNEL_ID; accept the
# SLACK_CHANNEL_ID name too (preferred) and normalise.
: "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"
# SCRIPTS_DIR is set by common.sh; derive a fallback if sourced standalone.
: "${SCRIPTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_NOTIFY_SLACK_SH="${MONOREPO_ROOT:-$(cd "${SCRIPTS_DIR}/../.." && pwd)}/scripts/notify_slack.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/slack_config.sh"

_notify_warn() {        # warn-once on stderr (best-effort, never throws)
  echo "notify: $*" >&2
  return 0
}
_notify_dbg() { [[ "${NOTIFY_DEBUG:-0}" == 1 ]] && echo "notify[dbg]: $*" >&2; return 0; }

notify_enabled() {
  if [[ "${NOTIFY_SLACK_DISABLED:-0}" == 1 ]]; then
    _notify_warn "disabled via NOTIFY_SLACK_DISABLED=1"
    return 1
  fi
  load_slack_config || true
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"
  if [[ -z "${SLACK_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]]; then
    _notify_warn "SLACK_TOKEN and/or SLACK_CHANNEL_ID not set (did you 'export' them?) -> notifications off"
    return 1
  fi
  if [[ ! -x "$_NOTIFY_SLACK_SH" ]]; then
    if [[ -f "$_NOTIFY_SLACK_SH" ]]; then
      _notify_warn "notify_slack.sh found but NOT executable: $_NOTIFY_SLACK_SH"
    else
      _notify_warn "notify_slack.sh not found: $_NOTIFY_SLACK_SH"
    fi
    return 1
  fi
  return 0
}

# _slack_post <message> [thread_ts] [color]
# Echoes the thread ts ONLY for an initial (un-threaded) message. Surfaces the
# notifier's stderr on failure. Always returns 0 (safe under `set -e`).
_slack_post() {
  notify_enabled || return 0
  local msg="$1" thread="${2:-}" color="${3:-}" out err errfile
  # Pass token/channel explicitly so we don't depend on them being exported
  # into the notifier's environment.
  local args=(-m "$msg" -c "$SLACK_CHANNEL_ID" -k "$SLACK_TOKEN")
  [[ -n "$thread" ]] && args+=(-t "$thread")
  [[ -n "$color"  ]] && args+=(-o "$color")

  errfile="$(mktemp 2>/dev/null || echo "/tmp/notify.$$.$RANDOM")"
  out="$("$_NOTIFY_SLACK_SH" "${args[@]}" 2>"$errfile")" || true
  err="$(tr '\n' ' ' <"$errfile" 2>/dev/null)"; rm -f "$errfile"
  # notify_slack.sh exits 0 even on API failure, so detect via its stderr.
  if [[ -n "$err" ]]; then
    _notify_warn "Slack post failed: ${err}"
    return 0
  fi
  _notify_dbg "posted ok (thread=${thread:-<new>})"
  # Initial (un-threaded) post: emit the new thread ts (last line only).
  [[ -z "$thread" ]] && printf '%s\n' "$out" | tail -n1
  return 0
}

# notify_job_begin <job_label> — open (or join) this job's thread.
notify_job_begin() {
  SLACK_JOB_NAME="${1:-${SLACK_JOB_NAME:-job}}"
  export SLACK_JOB_NAME
  notify_enabled || return 0
  if [[ -n "${SLACK_THREAD_TS:-}" ]]; then
    _slack_post "▶️ Starting job: *${SLACK_JOB_NAME}* (run \`${RUN_ID}\`)" "$SLACK_THREAD_TS" >/dev/null
  else
    SLACK_THREAD_TS="$(_slack_post "▶️ Starting job: *${SLACK_JOB_NAME}* (run \`${RUN_ID}\`)")"
    export SLACK_THREAD_TS
    _notify_dbg "opened thread ts=${SLACK_THREAD_TS:-<none>}"
  fi
  return 0
}

# notify_job_end [rc] — terminal status into the job thread; returns rc.
notify_job_end() {
  local rc="${1:-$?}"
  if notify_enabled && [[ -n "${SLACK_THREAD_TS:-}" ]]; then
    local color text
    if [[ "$rc" -eq 0 ]]; then
      color="good";   text="✅ Finished job *${SLACK_JOB_NAME:-job}* with status \`0\`"
    else
      color="danger"; text="❌ Finished job *${SLACK_JOB_NAME:-job}* with status \`${rc}\`"
    fi
    _slack_post "$text" "$SLACK_THREAD_TS" "$color" >/dev/null
  fi
  return "$rc"
}

# notify_open_for_enqueue <job_label> — orchestrator-side: echo a thread ts
# so the caller can pass SLACK_THREAD_TS=<ts> into `pueue add`. Reuses
# SLACK_THREAD_TS when the run banner (or a parent job) already opened one.
notify_open_for_enqueue() {
  notify_enabled || return 0
  if [[ -n "${SLACK_THREAD_TS:-}" ]]; then
    _slack_post "⏳ Enqueuing job: *${1:-job}* (run \`${RUN_ID}\`)" "$SLACK_THREAD_TS" >/dev/null
    printf '%s\n' "$SLACK_THREAD_TS"
    return 0
  fi
  _slack_post "⏳ Enqueuing job: *${1:-job}* (run \`${RUN_ID}\`)"
}

# notify_run_banner <text> — parent Slack message for the whole run, plus
# Grafana / Cloud Logging links windowed from RUN_ID. Exports SLACK_THREAD_TS
# so later jobs reply in this thread. Self-test:
#   NOTIFY_DEBUG=1 bash -c 'source scripts/lib/common.sh; notify_run_banner hi'
notify_run_banner() {
  local text="$1"
  local links
  links="$(observability_slack_links || true)"
  if [[ -n "$links" ]]; then
    text="${text}"$'\n'"${links}"
  fi
  if [[ -n "${SLACK_THREAD_TS:-}" ]]; then
    _slack_post "$text" "$SLACK_THREAD_TS" >/dev/null
  else
    SLACK_THREAD_TS="$(_slack_post "$text")"
    export SLACK_THREAD_TS
    _notify_dbg "opened run thread ts=${SLACK_THREAD_TS:-<none>}"
  fi
}

# Slack mrkdwn links for the snarkOS on-call Grafana dashboard and Cloud Logging,
# windowed from RUN_ID (UTC). Grafana `to` is `now` so the live window follows
# the run; logs use start−1m .. start+12h so the explorer still has a range
# after the banner is posted. Do not include GCP `rapt=` (session-only).
observability_slack_links() {
  command -v python3 >/dev/null || return 1
  RUN_ID="${RUN_ID:-}" \
  GCP_PROJECT="${GCP_PROJECT:-protocol-development-sandbox}" \
  NETWORK="${NETWORK:-testnet}" \
  python3 - <<'PY'
from datetime import datetime, timedelta, timezone
from urllib.parse import quote, urlencode
import os

rid = os.environ.get("RUN_ID", "")
project = os.environ.get("GCP_PROJECT", "protocol-development-sandbox")
network = os.environ.get("NETWORK", "testnet")
try:
    start = datetime.strptime(rid, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    start = datetime.now(timezone.utc)

grafana_from = start.strftime("%Y-%m-%dT%H:%M:%S.000Z")
logs_start = (start - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
logs_end = (start + timedelta(hours=12)).strftime("%Y-%m-%dT%H:%M:%S.000Z")

grafana_qs = urlencode(
    {
        "var-interval": "$__auto",
        "var-rate_interval": "$__auto",
        "var-rate_interval_short": "$__auto",
        "from": grafana_from,
        "to": "now",
        "timezone": "utc",
        "var-project": project,
        "var-network": network,
        "var-severity": "WARNING",
        "var-search": "",
        "var-role": "$__all",
        "var-DS_GOOGLE_CLOUD_MONITORING": "cex6fj2p02m0wd",
        "var-DS_LOGGING": "bf6hh0chl7xtse",
        "var-DS_PROMETHEUS": "cfv3f1jscpx4we",
        "refresh": "30s",
    },
    safe="$:",
    quote_via=quote,
)
grafana = (
    "https://provable.grafana.net/d/snarkos-oncall/snarkos-incident-response?"
    + grafana_qs
)

query = (
    f'logName="projects/{project}/logs/syslog"\n'
    'labels.role="snarkos-validator"\n'
    '-"systemd"'
)
logs = (
    "https://console.cloud.google.com/logs/query;"
    f"query={quote(query, safe='')};"
    "storageScope=project;"
    "summaryFields="
    + quote(
        "labels/commit_id,jsonPayload/_HOSTNAME,"
        "jsonPayload/SYSLOG_IDENTIFIER,labels/role,labels/owner"
        ":false:32:beginning",
        safe=",:_",
    )
    + f";startTime={logs_start};endTime={logs_end}"
    f"?project={quote(project, safe='')}"
)

print(f"<{grafana}|Grafana>  <{logs}|Logs>")
PY
}
