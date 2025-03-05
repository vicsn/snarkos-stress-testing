# Test Runner

## Prerequisites

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
    - `brew tap hashicorp/tap`
    - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
    - `brew install awscli`
- Make sure you have access to github.com/ProvableHQ/snarkos-staging
- You can build binaries with github actions or use the local cross-compilation method and use AWS S3 for release distribution. To use the local build method, run these steps first on Mac:
    - `brew tap SergioBenitez/osxct`
    - `brew install x86_64-unknown-linux-gnu`
    - `brew install openssl@3` (this should create a folder `/opt/homebrew/Cellar/openssl@3/3.4.0`. In case newer versions are released, update the version in the file `playbooks/roles/snarkos_build_locally/defaults/main.yml` and try it out.)
    - `rustup target add x86_64-unknown-linux-gnu`

The local build method uses the S3 bucket `release-bucket-2122415`, which been created on AWS using the command `aws s3api create-bucket --bucket release-bucket --region us-east-1`. By default in the `vars.example.yml` file, it compiles snarkOS with the `test_targets` feature (lowering the coinbase proving target, tx cannon needs to be compiled with the `enable_test_targets` feature alongside) and the `test_skip_tx_checks` feature (allows for fake txs to be processed, only exists for the `malice` snarkOS branches.)

## Configuration

- Copy `playbooks/vars.example.yml` to `playbooks/vars.yml` and fill in the required fields.
- You can change instance types and counts in `terraform/vars.tf*`
- You can change the network in `terraform/vars.tf*` and `playbooks/vars.yml`.

## AWS authentication

Authentication happens via Google SSO:
- Via `drive.google.com`, go to the top right apps icon, click on the app called "AWS access portal".
- Choose a scope and click on "Access keys".
- Follow the steps to authenticate using `aws configure sso`.
  - The profile name should be the same as the profile in `terraform/provider.tf`.
- After initial setup, you can use `aws sso login --profile <profile>` 

## Running your devnet

`./run_test_suite.sh` will allow you to choose infra to set up and tests to run.

`./auto_run_test_suite.sh` is used mainly for atuomatically running the tests, but also can be ran manually. Examples:

```
./auto_run_test_suite.sh l y y test_name # Run test_name in light environment also setup terraform.
./auto_run_test_suite.sh l y n # Just setup terraform for light environment.
./auto_run_test_suite.sh l n y test_name # Run test_name in light environment, but don't setup terraform.
./auto_run_test_suite.sh l y y test_name my_vars # Run test_name in light environment also setup terraform with alternative vars file.
```

## Monitoring

- [Grafana](https://aleostresstest.grafana.net/d/single-region-tests/single-region-tests?from=now-3h&to=now&refresh=) can be used with `devnet_name=single-region-tests`. If you change your `devnet_name`, you'll need to customize and import `grafana.json` to a new dashboard.
- [Elastic](https://eq-external.kb.eu-north-1.aws.elastic-cloud.com:9243/app/discover#/).
- If ECR logging is enabled, [AWS console](https://us-west-2.console.aws.amazon.com/ecs/v2/clusters?region=us-west-2).

## Running multiple devnets in parallel

Should be possible by changing the `devnet_name` in `playbooks/vars.yml`. Note that you will hit the quota limits pretty soon. See for upgrading [these scripts](https://github.com/ProvableHQ/infrastructure/tree/main/misc-scripts).

## Changing the region

Should be possible, but there may be stuff you need to update:
- Default region is `us-west-2`
- Set region in `inventory/dynamic_inventory.aws_ec2.yml` and `terraform/provider.tf`
    - Region can be left blank in `dynamic_inventory.aws_ec2.yml` to scan all regions but will be significantly slower
- Pushing a base image to the new region using [packer](../../special_devnets/packer/)
- Creating a new ECS cluster
- Pushing the tx-cannon image to [the ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html)
- Creating a new Grafana instance
- Creating a new Elastic instance

And there may also be stuff you want to keep the same, e.g. the Terraform S3 bucket.

## Usage of keymaterial

The transaction cannons use hardcoded private keys, made possible by snarkos
nodes using the fixed `DEVELOPMENT_MODE_RNG_SEED`.
