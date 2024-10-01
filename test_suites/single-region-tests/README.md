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

## Authentication

Authentication happens via Google SSO:
- Via e.g. `drive.google.com`, go to the top right apps icon, click on the app called "AWS access portal".
- Choose a scope and click on "Access keys".
- Follow the steps to authenticate using `aws configure sso`.
  - The profile name should be the same as the profile in `terraform/provider.tf`.
- After initial setup, you can use `aws sso login --profile <profile>` 

## Monitoring

- [Grafana](https://aleostresstest.grafana.net/d/single-region-tests/single-region-tests?from=now-3h&to=now&refresh=)
- [Elastic](https://eq-external.kb.eu-north-1.aws.elastic-cloud.com:9243/app/discover#/)

## Running multiple devnets in parallel

Should be possible by changing the `devnet_name` in `playbooks/vars.yml`. Note that you will hit the quota limits pretty soon. See for upgrading [these scripts](https://github.com/ProvableHQ/infrastructure/tree/main/misc-scripts).

## Changing the region

Should be possible, but there may be stuff you need to update:
- Pushing a base image to the new region using [packer](../../special_devnets/packer/)
- Creating a new ECS cluster
- Pushing the tx-cannon image to [the ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html)
- Creating a new Grafana instance
- Creating a new Elastic instance

And there may also be stuff you want to keep the same, e.g. the Terraform S3 bucket.

## Running

`./run_test_suite.sh` will allow you to choose infra to set up and tests to run.

## Usage of keymaterial

The transaction cannons use hardcoded private keys, made possible by snarkos
nodes using the fixed `DEVELOPMENT_MODE_RNG_SEED`.
