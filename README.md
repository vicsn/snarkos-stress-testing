# Stress Testing

A collection of integration tests with an infrastructure as code (IaC) approach.

- [builder](./builder): A builder machine for re-usable snarkOS binaries.
- [log_analysis_scripts](./log_analysis_scripts): collection of scripts for log analysis.
- [release_scripts](./release_scripts): collection of scripts for release management.
- [scripts](./scripts): Collection of shell and python utility scripts to work with the network created for testing
- [test_suites](./test_suites): a maintained integration test runner.

## Development Setup

After cloning the repository, it is recommend to set up the pre-commit hook for lints:

First, install the required Python packages.
```bash
pip install pre-commit ansible ansible-lint
```

Then, activate the hook.
```bash
pre-commit install
```

You may also need to install a newer version of bash and shellcheck if you are on MacOS.

For example, you can install them through homebrew using this command.
```
brew install bash shellcheck
```
