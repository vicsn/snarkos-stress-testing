#!/usr/bin/env bash
# bash_err_trap.sh — source after `set -e` so failures print file:line + command.
# Safe to source more than once. Does not enable errexit itself.
#
# Optional full xtrace: SCRIPT_DEBUG=1 ./script.sh

[[ -n "${_BASH_ERR_TRAP_SOURCED:-}" ]] && return 0
_BASH_ERR_TRAP_SOURCED=1

# ERR must fire inside functions (callers use `set -euo pipefail`).
set -o errtrace

report_command_failure() {
  local rc=$?
  local i
  echo "ERROR: command failed (rc=${rc})" >&2
  echo "  command:  ${BASH_COMMAND}" >&2
  echo "  location: ${BASH_SOURCE[1]}:${BASH_LINENO[0]} (${FUNCNAME[1]})" >&2
  if ((${#FUNCNAME[@]} > 2)); then
    echo "  stack:" >&2
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
      echo "    ${BASH_SOURCE[i]}:${BASH_LINENO[i - 1]} ${FUNCNAME[i]}()" >&2
    done
  fi
}

trap report_command_failure ERR

if [[ "${SCRIPT_DEBUG:-}" == 1 ]]; then
  export PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
fi
