#!/usr/bin/env bash
# lib/stm.sh — stress-testing-manager (STM) delegation.
#
# Sourced by lib/common.sh as a library, and executable on its own for ad-hoc
# manager access (one file, so there is only ever one "stm.sh"):
#
#   scripts/lib/stm.sh                 # interactive shell, cwd = this suite
#   scripts/lib/stm.sh pueue status    # one-off command
#
# There is ONE way to run anything in this suite: on the manager. A laptop
# invocation of full_run.sh or of any scripts/bin/* entrypoint hands the
# identical command to the manager over SSH, and the manager takes it from
# there (normally by enqueuing it in pueue). Ansible has to run inside the
# shared VPC anyway — the dynamic inventory targets private IPs — so the
# manager is the only host where a run works end to end.
#
# Preamble of every entrypoint:
#   parse args -> stm_dispatch_self -> pueue_dispatch_self -> do the work
#
# The caller must be authorized via `external_ssh_users` in the STM tfvars
# (SSH pubkey in ~ubuntu/.ssh/authorized_keys + a /32 firewall allow).
# Set STM_LOCAL=1 to skip delegation and run here instead (needs VPC access).

[[ -n "${_STM_SH_SOURCED:-}" ]] && return 0
_STM_SH_SOURCED=1

# Run directly? Pull in common.sh first — the definitions below need
# MONOREPO_ROOT, and the CLI block at the bottom needs die/load_slack_config.
# The guard above keeps common.sh from re-entering this file.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

# The manager always logs in as `ubuntu` with the repo at a fixed path, so the
# remote layout mirrors this one (see tf_stack.sh rsync_package).
STM_USER="${STM_USER:-ubuntu}"
STM_REPO_ROOT="${STM_REPO_ROOT:-/home/${STM_USER}/snarkos-stress-testing}"

# Written by the STM terraform apply as local_file.stm_ip (see
# stress-testing-manager/infrastructure/main.tf). This file is the canonical
# source: no `terraform output` roundtrip, so callers need no terraform.
STM_IP_FILE="${MONOREPO_ROOT}/stress-testing-manager-ip.txt"
export STM_USER STM_REPO_ROOT STM_IP_FILE

# Run identity plus the wiring the remote side cannot rederive on its own.
STM_FORWARD_ENV=(
  RUN_ID SLACK_TOKEN SLACK_CHANNEL_ID CHANNEL_ID NOTIFY_SLACK_DISABLED
  PUEUE_DISABLED DEVNET_NAME OWNER TF_STATE_REGION
  RELEASE_BUCKET RESULTS_AND_LOGS_BUCKET
  ADD_MASTER TARGET_MASTER
)

# Echo the manager's external IP; non-zero when the file is missing or empty.
stm_ip() {
  [[ -f "$STM_IP_FILE" ]] || return 1
  local ip
  ip="$(tr -d '[:space:]' < "$STM_IP_FILE")"
  [[ -n "$ip" ]] || return 1
  printf '%s\n' "$ip"
}

# True when this host IS the manager. Reads the `role` metadata attribute set
# by the STM main.tf; no DNS lookups.
stm_is_manager() {
  local role
  role="$(curl -sf --max-time 2 -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/role 2>/dev/null || true)"
  [[ "$role" == "stress-testing-manager" ]]
}

# Delegate unless we are already on the manager, were sent there by an outer
# stm_exec (loop guard), or were explicitly told to stay put.
stm_should_delegate() {
  [[ -n "${STM_LOCAL:-}" || -n "${STM_DELEGATED:-}" ]] && return 1
  ! stm_is_manager
}

# Map a path inside this repo onto the same path on the manager.
stm_remote_path() {
  local abs="$1" rel
  rel="${abs#"$MONOREPO_ROOT"/}"
  [[ "$rel" != "$abs" ]] || return 1
  printf '%s/%s\n' "$STM_REPO_ROOT" "$rel"
}

# Quote a command vector into a single `bash -c`-safe string.
_stm_quote() {
  local quoted
  quoted="$(printf '%q ' "$@")"
  printf '%s' "${quoted% }"
}

# stm_exec [command...] — run a command on the manager with this suite as cwd.
# With no command, opens an interactive login shell there. Returns the remote
# command's status.
stm_exec() {
  local ip remote_suite
  ip="$(stm_ip)" || die "No manager IP in $STM_IP_FILE — run 'stress-testing-manager/infrastructure/tf_stack.sh provision' first."
  remote_suite="$(stm_remote_path "$REPO_ROOT")" \
    || die "$REPO_ROOT is outside $MONOREPO_ROOT; cannot map it onto the manager."

  # Resolve Slack creds here so the manager reports into this run's thread even
  # when its own profile / Secret Manager lookup comes up empty.
  [[ -n "${NOTIFY_SLACK_DISABLED:-}" ]] || load_slack_config || true
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"

  local -a inner=(env "STM_DELEGATED=1")
  local var
  for var in "${STM_FORWARD_ENV[@]}"; do
    [[ -n "${!var:-}" ]] && inner+=("$var=${!var}")
  done

  # ConnectTimeout keeps an unreachable manager (VPN down, IP not allowlisted)
  # to a 10s failure instead of a long hang.
  local -a ssh_opts=(-o ForwardAgent=yes -o ConnectTimeout=10)
  local remote_cmd
  if (($#)); then
    inner+=("$@")
    remote_cmd="cd $(_stm_quote "$remote_suite") && exec $(_stm_quote "${inner[@]}")"
    # A human at a terminal gets a TTY, so remote prompts work and Ctrl-C
    # reaches the remote job instead of orphaning it. Piped or queued callers
    # keep a clean, pty-free stream.
    [[ -t 0 && -t 1 ]] && ssh_opts+=(-t)
  else
    ssh_opts+=(-t)
    remote_cmd="cd $(_stm_quote "$remote_suite") && exec bash -l"
  fi

  # Non-interactive SSH can skip login profiles, so put ~/.cargo/bin (pueue,
  # cargo) on PATH and source the manager's Slack env explicitly — the same
  # two things lib/common.sh does for scripts that source it. $HOME must
  # expand remotely, hence the escaped $.
  local login_cmd
  login_cmd="export PATH=\"\$HOME/.cargo/bin:\$PATH\"; if [[ -f \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\" ]]; then . \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\"; fi; ${remote_cmd}"

  echo "==> stress-testing-manager (${STM_USER}@${ip}): ${*:-login shell}" >&2
  # SC2029: client-side expansion is the point — _stm_quote has already made
  # the command opaque to the remote shell.
  # shellcheck disable=SC2029
  ssh "${ssh_opts[@]}" "${STM_USER}@${ip}" "bash -lc $(_stm_quote "$login_cmd")"
}

# stm_dispatch_self [args...] — hand THIS script, with these args, to the
# manager and exit with the remote status. No-op when already running there.
# Call it after arg parsing so mistakes still fail fast locally:
#   stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
stm_dispatch_self() {
  stm_should_delegate || return 0
  local self remote_self rc=0
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  remote_self="$(stm_remote_path "$self")" \
    || die "Cannot delegate $0: it lives outside $MONOREPO_ROOT."
  stm_exec "$remote_self" "$@" || rc=$?
  exit "$rc"
}

# stm_run <command...> — run a command wherever runs belong: on the manager, or
# right here when this IS the manager (or STM_LOCAL=1). Unlike
# stm_dispatch_self this returns, so callers can capture the output.
stm_run() {
  if stm_should_delegate; then
    stm_exec "$@"
  else
    (cd "$REPO_ROOT" && "$@")
  fi
}

# Ad-hoc manager access when this file is executed rather than sourced. This is
# for inspecting a run, not starting one: full_run.sh and every scripts/bin/*
# entrypoint already delegate themselves via stm_dispatch_self.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if (($#)); then
    stm_run "$@"
  else
    stm_should_delegate \
      || die "Already on the manager (or STM_LOCAL set) — no shell to open."
    stm_exec
  fi
fi
