#!/bin/bash

ansible-galaxy collection install community.general ansible.posix amazon.aws -p ~/.ansible/collections/ --force

export ANSIBLE_ROLES_PATH=./test_suites/single-region-tests/playbooks/roles:$ANSIBLE_ROLES_PATH
export ANSIBLE_DEPRECATION_WARNINGS=False

python3 -m ansiblelint -v --force-color -c test_suites/single-region-tests/.ansible-lint \
        --exclude "special_devnets/*" \
        --exclude "test_suites/single-region-tests/.pre-commit-config.yaml" \
        --exclude "test_suites/single-region-tests/terraform/*" \
        --exclude "test_suites/network-sync-tests/playbooks/[var|ip|log]*" \
        --exclude "test_suites/network-sync-tests/playbooks/set_client_facts.yml" \
        --exclude "test_suites/network-sync-tests/playbooks/snarkos-shallow/*" \
        --exclude "test_suites/single-region-tests/playbooks/[var|set_|ip|log|wait_]*"

