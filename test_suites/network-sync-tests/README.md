# Client Node Sync Runner

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

## AWS authentication

Authentication happens via Google SSO:
- Via `drive.google.com`, go to the top right apps icon, click on the app called "AWS access portal".
- Choose a scope and click on "Access keys".
- Follow the steps to authenticate using `aws configure sso`.
  - The profile name should be the same as the profile in `terraform/provider.tf`.
- After initial setup, you can use `aws sso login --profile <profile>` 

## Running your test

`./run_client_sync_test.sh` will run the client sync test. You need to select the network.

## Monitoring

- [Grafana](https://aleostresstest.grafana.net/d/single-region-tests/single-region-tests?from=now-3h&to=now&refresh=) can be used with `devnet_name=single-region-tests`. If you change your `devnet_name`, you'll need to customize and import `grafana.json` to a new dashboard.
- [Elastic](https://eq-external.kb.eu-north-1.aws.elastic-cloud.com:9243/app/discover#/).
- If ECR logging is enabled, [AWS console](https://us-west-2.console.aws.amazon.com/ecs/v2/clusters?region=us-west-2).

## Updating the snapshots
Please update the `playbooks/snapshot_urls_mainnet.txt` and `playbooks/snapshot_urls_testnet.txt` files on a regular basis. Also note that older snapshots may no longer be available.
