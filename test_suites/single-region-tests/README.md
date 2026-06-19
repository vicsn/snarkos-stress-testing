# Test Runner

## Prerequisites

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
    - `brew tap hashicorp/tap`
    - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - `brew install ansible`
- [Install sccache](https://github.com/mozilla/sccache)
    - `brew install sccache`
- [Install AWS CLI](https://aws.amazon.com/cli/)
    - `brew install awscli`
- Make sure you have access to github.com/ProvableHQ/snarkos-staging
- You can build binaries with github actions or use the local cross-compilation method and use AWS S3 for release distribution. To use the local build method, run these steps first on Mac:
    - `brew tap SergioBenitez/osxct`
    - `brew install x86_64-unknown-linux-gnu`
    - `brew install openssl@3` (this should create a folder `/opt/homebrew/Cellar/openssl@3/3.4.0`. In case newer versions are released, update the version in the file `playbooks/roles/snarkos_build_locally/defaults/main.yml` and try it out.)
    - `rustup target add x86_64-unknown-linux-gnu`
- [Install pre-commit](https://pre-commit.com/#installation). It can be installed with `pip install pre-commit`.
    - Run `cd test_suites/single-region-tests && pre-commit install`. Now you have an Ansible lint commit hook.
- [Install pueue](https://github.com/Nukesor/pueue) and start the daemon before running jobs:
    - `cargo install pueue` (or `brew install pueue` if available)
    - `pueued -d` (runs in the background; use `pueue status` to confirm)
    - Set `pause_on_failure: true` in the pueue daemon config so a failing job pauses the group instead of continuing.

## Configuration

- Copy `playbooks/vars.example.yml` to `playbooks/vars.yml` and fill in the required fields.
- Add your SSH public key to `keys.pub` at the repo root for human access to devnet machines. The ephemeral `devnet-key` (repo root, auto-created on provision) is used by Terraform/Ansible alongside those keys.

Authentication happens via Google SSO:
- Via `drive.google.com`, go to the top right apps icon, click on the app called "AWS access portal".
- Choose a scope and click on "Access keys".
- Follow the steps to authenticate using `aws configure sso`.
  - The profile name should be the same as the profile in `terraform/provider.tf`.
- After initial setup, you can use `aws sso login --profile <profile>` 

## Running your devnet

Every run needs a **`RUN_ID`**: it ties together S3 log prefixes, Slack threads, and pueue job snapshots. Export it once at the start of a session and reuse it for every job in that run:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
```

The devnet name can be set via the `DEVNET_NAME` env variable (for example `DEVNET_NAME="my_net" export RUN_ID=...` before enqueuing).
By default for local test runs it is `single-region-tests` and for automatic pre-release tests it is `prerelease-devnet`.
Alternatively the TF var `devnet_name` can be edited to change it too.

All work goes through **pueue** by default (`lib/pueue.sh`). Each `scripts/bin/` entrypoint self-enqueues unless `PUEUE_DISABLED=1`. Set `PUEUE_DISABLED=1` to run inline in the current shell.


### Full run

`full_run.sh` wires `provision → setup → {N test jobs} → destroy`:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
./scripts/full_run.sh --mode=light --tests=prerelease
pueue status
```

Use `--tests=prerelease` or `--tests=t1,t2` to narrow the test list. A failed provision cancels the rest of the chain.

#### Stress Testing Manager delegation

`full_run.sh` can run on the shared [Stress Testing Manager](../../stress-testing-manager/README.md) instead of your laptop. By default it delegates over SSH to the manager using a repo-root file, `stress-testing-manager-ip.txt` (gitignored):

| Situation | Behaviour |
|-----------|-----------|
| IP file **missing** | Runs `stress-testing-manager/infrastructure/tf_stack.sh ip`, writes the IP to `stress-testing-manager-ip.txt`, then **delegates** to that host. |
| IP file **present** | Delegates immediately (same as above). |

The manager must be provisioned and set up first (`tf_stack.sh provision` + `setup`; see the manager README). `tf_stack.sh ip` must succeed when the IP file is first created.

Forwarded to the remote run: `RUN_ID`, Slack/pueue settings, `DEVNET_NAME`, `OWNER`, and related bucket/region env vars. Export anything you need **before** calling `full_run.sh`.

To run **locally** on your machine (requires pueue, or `PUEUE_DISABLED=1`):

```bash
FULL_RUN_LOCAL=1 ./scripts/full_run.sh --mode=light --tests=prerelease
```

To point at a different manager, replace the file contents or delete it and re-run so `tf_stack.sh ip` repopulates it.

### Individual jobs

Once `RUN_ID` is exported, pueue snapshots it at enqueue time — every job in the run shares the same S3 prefix. Invoke a bin script directly; it enqueues itself:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
./scripts/bin/provision.sh --mode=light
./scripts/bin/setup.sh
./scripts/bin/run-test.sh --test=prerelease_foo
./scripts/bin/run-utility.sh --utility=analyze_logs
./scripts/bin/destroy.sh
pueue status
```

Run inline (no pueue): `PUEUE_DISABLED=1 ./scripts/bin/run-test.sh --test=foo`.

### Slack notifications

Optional, best-effort job status. Export `SLACK_TOKEN` and `SLACK_CHANNEL_ID` (or `CHANNEL_ID`) **before** enqueuing; pueue snapshots them into each task. Disable with `NOTIFY_SLACK_DISABLED=1`. Notifications never fail a job.

## Monitoring

- [Grafana](https://aleostresstest.grafana.net/d/single-region-tests/single-region-tests?from=now-3h&to=now&refresh=) can be used with `devnet_name=single-region-tests`. If you change your `devnet_name`, you'll need to customize and import `grafana.json` to a new dashboard.
- You can easily access logs as follows:
  - Let `.ssh/config` know about your `devnet-key`:
```
host *.*.compute.amazonaws.com
  User ubuntu
  addkeystoagent yes
  usekeychain yes
  identityfile /path/to/snarkos-stress-testing/devnet-key
```
 - Add hosts to known hosts and connect with lnav
```
TXCANNON_SUBDOMAIN="ec2-35-90-249-139"
TXCANNON_DOMAIN="${TXCANNON_SUBDOMAIN}.us-west-2.compute.amazonaws.com"
ssh-keyscan -H ${TXCANNON_DOMAIN} >> ~/.ssh/known_hosts
lnav ubuntu@${TXCANNON_DOMAIN}:txcannon.log
```
```
NODE_SUBDOMAIN="ec2-18-236-122-120"
NODE_DOMAIN="${NODE_SUBDOMAIN}.us-west-2.compute.amazonaws.com"
ssh-keyscan -H ${NODE_DOMAIN} >> ~/.ssh/known_hosts
ssh ubuntu@${NODE_DOMAIN} "tail -n 10000 /tmp/snarkos.log > /tmp/snarkos_tail.log"
lnav ubuntu@${NODE_DOMAIN}:/tmp/snarkos_tail.log
```
- You can check out tx-cannon builds here currently: https://us-east-1.console.aws.amazon.com/ecr/repositories/private/637423331354/tx-cannon?region=us-east-1
- Elastic is not functional at this time.

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

## Log files and analysis

With local runs the log files are downloaded in `log_files`.
With remote runs the log files are zipped and uploaded to S3 (in slack the location is pointed out).

Ensure the same `RUN_ID` from the test run is still exported before enqueuing log jobs.

Example logs zip : https://us-west-2.console.aws.amazon.com/s3/object/provable-logs-results?region=us-west-2&bucketType=general&prefix=dbd34c34d70e859d93dfac56600ee18ef8f64a22/20251003T000120Z/prerelease_1_halt_byzantine_majority_ERROR/logs_ERROR.zip
You can download and unzip the log files from a auto-run in `log_files` too to use the utilities on them.

The log files are gzipped, so this action will make them in plain text format:

```
gunzip log_files/*.log.gz
```

For getting the errors out of them this can be done:

```
grep -Hn ERROR log_files/* > tmp.errors.txt
```

Run the stat analyser on downloaded logs (reuse the run's `RUN_ID`):

```bash
./scripts/bin/run-utility.sh --utility=analyze_logs
```

Stats are written to `log_files/landing_stats.json`.

Download individual log sets:

```bash
./scripts/bin/run-utility.sh --utility=download_logs_clients
./scripts/bin/run-utility.sh --utility=download_logs_provers
./scripts/bin/run-utility.sh --utility=download_logs_tx_runner
./scripts/bin/run-utility.sh --utility=download_logs_validators
```

Download all logs, analyze, and upload to S3:

```bash
./scripts/bin/collect-logs.sh
```

## Destroying the stress testing infrastructure locally

When runs are **delegated** to the Stress Testing Manager (see [Full run](#stress-testing-manager-delegation) above), cleanup is handled on the manager via the normal `destroy` job in the pipeline.

When running **locally** with `FULL_RUN_LOCAL=1`, destroy manually when ready (with the run's `RUN_ID` still exported):

```bash
./scripts/bin/destroy.sh
```
