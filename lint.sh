#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv-lint"

resolve_stable_python() {
  local candidate release
  for candidate in python3.12 python3.11 python3.13 python3; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    release=$("$candidate" -c 'import sys; print(sys.version_info.releaselevel)' 2>/dev/null) || continue
    [[ "$release" == "final" ]] || continue
    echo "$candidate"
    return 0
  done
  return 1
}

resolve_lint_python() {
  if [[ -n "${LINT_PYTHON:-}" ]]; then
    echo "$LINT_PYTHON"
    return 0
  fi

  if [[ -x "${VENV_DIR}/bin/python" ]]; then
    echo "${VENV_DIR}/bin/python"
    return 0
  fi

  local stable_python
  stable_python="$(resolve_stable_python)" || {
    echo "Error: no stable Python 3 interpreter found (alpha/beta/rc versions crash ansible-lint)." >&2
    exit 1
  }

  if "$stable_python" -m ansiblelint --version >/dev/null 2>&1; then
    echo "$stable_python"
    return 0
  fi

  echo "Creating lint venv at ${VENV_DIR} using ${stable_python}..."
  "$stable_python" -m venv "$VENV_DIR"
  "${VENV_DIR}/bin/pip" install -q ansible ansible-lint
  echo "${VENV_DIR}/bin/python"
}

LINT_PYTHON="$(resolve_lint_python)"

ansible-galaxy collection install community.general ansible.posix amazon.aws -p ~/.ansible/collections/ --force

export ANSIBLE_ROLES_PATH=./test_suites/single-region-tests/playbooks/roles:./common/roles:${ANSIBLE_ROLES_PATH:-}
export ANSIBLE_DEPRECATION_WARNINGS=False

"$LINT_PYTHON" -m ansiblelint -v --force-color -c test_suites/single-region-tests/.ansible-lint \
        --exclude "special_devnets/*" \
        --exclude "test_suites/single-region-tests/.pre-commit-config.yaml" \
        --exclude "test_suites/single-region-tests/terraform/*" \
        --exclude "test_suites/network-sync-tests/playbooks/[var|ip|log]*" \
        --exclude "test_suites/network-sync-tests/playbooks/set_client_facts.yml" \
        --exclude "test_suites/network-sync-tests/playbooks/setup.yml" \
        --exclude "test_suites/network-sync-tests/playbooks/snarkos-shallow/*" \
        --exclude "test_suites/single-region-tests/playbooks/[var|set_|ip|log|wait_]*" \
        --exclude "test_suites/single-region-tests/tests/load_saved_transactions/tx_submitter/target/*"
