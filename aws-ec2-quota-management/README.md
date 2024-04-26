# AWS EC2 Quota Management

This folder contains two bash scripts to manage EC2 quotas in US regions:

1. `request_increase_vcpu.sh`: Requests a service quota increase for "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" in each US region. Update the `desired_value` variable before running.

2. `see_vcpu_limits.sh`: Lists the current quota values for "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" in each US region.

## Prerequisites
- AWS CLI installed and configured.
- `jq` command-line JSON processor installed (for `see_vcpu_limits.sh`).

## Usage
1. Update `desired_value` in `request_increase_vcpu.sh` if needed.
2. Run `./request_increase_vcpu.sh` to request a quota increase.
3. Run `./see_vcpu_limits.sh` to view current quota values.