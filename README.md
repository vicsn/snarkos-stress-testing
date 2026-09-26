# snarkOS stress testing

Infrastructure and tests for stressing snarkOS. The P2P network suite and the stress-testing manager run on GCP. The CDN/ledger suite runs on AWS.

Guides: [docs/README.md](./docs/README.md).

## Layout

- [test_suites/snarkos-p2p-tests](./test_suites/snarkos-p2p-tests): GCP P2P network (validators, clients, provers).
- [test_suites/snarkos-cdn-tests](./test_suites/snarkos-cdn-tests): AWS single-machine suite for loading a ledger or syncing from CDN/snapshots.
- [stress-testing-manager](./stress-testing-manager): long-running GCE instance that runs pueue and launches test suites.
- [single-machine-with-ssh-forwarding](./single-machine-with-ssh-forwarding): one machine with SSH agent forwarding.
- [packer](./packer): GCP base image (`stress-test-base`).
- [common](./common): shared Ansible roles.
- [scripts](./scripts): shell and Python helpers.
- [log_analysis_scripts](./log_analysis_scripts): log analysis.

## Development setup

```bash
pip install pre-commit ansible ansible-lint
pre-commit install
```

On macOS you may also need a newer bash and shellcheck:

```bash
brew install bash shellcheck
```
