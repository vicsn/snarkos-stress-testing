# Test Runner

## Prerequisites

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
    - `brew tap hashicorp/tap`
    - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
    - `brew install awscli`
- Create a new hosted Grafana instance using the provided grafana.json
- Create a new hosted Elastic (Kibana) instance
- Use Github actions to build and release a snarkOS binary on github.com/ProvableHQ/snarkos-staging

## Configuration

- Copy `playbooks/vars.example.yml` to `playbooks/vars.yml` and fill in the required fields

## Optional Configuration

These configurations have defaults and are optional to set.

- Default region is `us-west-2`
- Set region in `inventory/dynamic_inventory.aws_ec2.yml` and `terraform/provider.tf`
    - Region can be left blank in `dynamic_inventory.aws_ec2.yml` to scan all regions but will be significantly slower
- Set instance type and count in `terraform/variables.yml`

## Running

`./run_test_suite.sh` will allow you to choose infra to set up and tests to run.

## Usage of keymaterial

The transaction cannons use hardcoded private keys, made possible by snarkos
nodes using the fixed `DEVELOPMENT_MODE_RNG_SEED`.
