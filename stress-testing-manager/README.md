# Aleo SnarkOS Stress Testing Manager

A machine that can react to new SnarkOS releases and can build a SnarkOS binary which then can be used and reused
to run the stress tests.

## Creating the Stress Testing Manager

### Base AMI dependency

The Stress Testing Manager uses its own base AMI image (can be built using the scripts in the `packer` folder).
The image is based on Ubuntu 22 and includes a lot of tools for debugging and building SnarkOS.
It contains Rust/Cargo, AWS CLI, git, Ansible and Terraform.

It is prebuilt in the AWS sandbox (`us-east-1`, `099720109477`), but that can be modified to be built in
another region and account. Just modify the region in `packer/image.json.pkr.hcl`, export your `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` in the current terminal and navigate to the `packer` folder. Run:

```
export AWS_REGION=us-west-2
packer init image.json.pkr.hcl
packer build image.json.pkr.hcl
```

Then add your account to the list in `infrastructure/base_ami.tf` on line `4`. Now the image will be available for your
account too.

### Preparations

The terraform run will require environment variables. It is recommended to keep a `.env` file in the infrastructure folder like:

```
export TF_VAR_SLACK_CHANNEL_ID="<value>"
export TF_VAR_SLACK_TOKEN="<value>"

export TF_VAR_github_token="<value>"

export TF_VAR_ELASTIC_CLOUD_ID="<value>"
export TF_VAR_ELASTIC_API_KEY="<value>"
export TF_VAR_GRAFANA_CLOUD_API_KEY="<value>"

export TF_VAR_DEVNET_NAME="<value>"
```

Just source it before the run:

```
source .env
```

There is a file with public keys that will be added to the `authorized_keys` of the new server, if yours is not there,
add it to it, the logic is written in a way it won't duplicate a key. The key has to be added in:

```
stress-testing-manager/infrastructure/ansible/templates/extra_keys.pub
```

Can be done like in this example:

```
echo `cat ~/.ssh/id_rsa.pub` >> stress-testing-manager/infrastructure/ansible/templates/extra_keys.pub
```

### Using tf_stack.sh

Before running anything modify the `env-default` or `env-staging` with the right environemnt variable values and source it:

```
cd infrastructure

cp env-default .env # or "cp env-staging .env-staging"
vim .env # modify values

source .env
```

Navigate to `infrastructure` and run:

```
# Plan stress test manager setup (not staging)
./tf_stack.sh plan

# Apply stress test manager infrastructure (no staging)
./tf_stack.sh apply --auto-approve
```

This will create the Stress Testing Manager using the base image from the previous section as base.
What does that include?
1. A machine of type `t2.xlarge` with 100GB of storage (to store logs and binaries).
2. A profile giving the machine a lot of rights in AWS - to create and destroy instances, access S3, create and destroy networks, etc. This is needed so stress tests can be run from it and these tests create instances and a network, read things from S3, etc. The whole list of accesses can be viewed in `infrastructure/ec2_profile.tf`, line `19`.

Keep in mind that in order to create the Stress Testing Manager, first you need to export `TF_VAR_AWS_ACCESS_KEY` and `TF_VAR_AWS_SECRET_KEY`.
Additionally you need a github token with read access to this repository (so the stress-testing-manager can download the tests). Export it with `TF_VAR_github_token`.

By default, the setup uses the ssh key `id_ed25519.pub` in `~/.ssh/`. You can overwrite this with `TF_VAR_PUBLIC_KEY_PATH=...`.

#### Creating a staging copy (parallel environment)

This creates a second, isolated copy of the stack in the same AWS account/region:

```
./tf_stack.sh plan --staging
./tf_stack.sh apply --staging --auto-approve
```

Staging uses a separate Terraform workspace (staging) and resource names are suffixed so it does not collide with the main (default) Stress Testing Manager.

### Provisioning with Ansible

Before running anything modify the `env-default` or `env-staging` with the right environemnt variable values and source it:

```
cd infrastructure

cp env-default .env # or "cp env-staging .env-staging"
vim .env # modify values

source .env
```

Provisioning is done by Ansible (infrastructure/ansible/playbook.yml) and is triggered via the wrapper script.
To (re)run provisioning against the existing manager instance:

```
./tf_stack.sh provision
```

or for staging:

```
./tf_stack.sh provision --staging
```

It does:

1. Downloads the stress tests from `github.com/ProvableHQ/snarkos-stress-testing.git` and puts them in the folder `stress_testing` (the `ubuntu` user home is the base for all of these resources).
2. Installs python (needed for Ansible and AWS cli/S3 access). It is in the base image, but that will update it to newest.
3. Downloads the `talisker` source from `https://github.com/ProvableHQ/talisker` and compiles it, releases it, installs it in `/home/ubuntu/bin/talisker`.
4. Runs `talisker` as a service (this is the software that detects new releases, kicks the builds, puts the binaries at accessible places, manages the test runs and retries and uploads the logs from them).
5. Sets up the right test vars that are specific for the automated runs.
6. By default a local API is ran at port `3030` for talisker its documentation can be found [here](https://github.com/ProvableHQ/talisker/blob/master/README.md#using-the-internal-api)

### Choosing Talisker / stress-testing branches (staging only)

By default:
* Talisker branch: master
* Stress-testing branch: main

To deploy staging using specific branches:

```
./tf_stack.sh apply --staging --auto-approve \
  --talisker-branch your-talisker-branch \
  --stress-testing-branch your-stress-testing-branch

# then provision (or just provision if infra already exists)
./tf_stack.sh provision --staging \
  --talisker-branch your-talisker-branch \
  --stress-testing-branch your-stress-testing-branch
```

For safety, branch overrides are blocked on the default workspace.

## Removing the Stress Testing Manager

The stress-testing-manager is stateless, so it can be removed and created whenever we decide to do so.
For destroying the main stress test manager instance (blocked by default, so use --force), just run:

```
./tf_stack.sh destroy --force --auto-approve
```

in the `infrastructure` folder.

For staging, in similar fashion:

```
./tf_stack.sh destroy --staging --auto-approve
```

## Updating the Stress Testing Manager

Just run:

```
./tf_stack.sh provision
```

or for staging

```
./tf_stack.sh provision --staging
```

in the `infrastructure` folder.

This will re-run the Ansible playbook against the existing instance.
No infrastructure changes are applied unless explicitly requested via apply.

## The stress-testing-manager logic

![alt text](images/diagram.svg "Diagram")<!-- SVG can be modified with app.diagrams.net -->

The Stress Testing Manager machine is running a service called Talisker, a systemd service that can be controlled with (for example):

```
sudo service talisker stop
sudo service talisker start
```

A way to check its logs is:

```
journalctl -efu talisker
```

### Listening to new branches/tags

Talisker uses a mechanism to ping repositories that were configured to be pinged and if there are new new branches or tags to react to them.
It only reacts to specific naming of these tags/branches (configured with regex).

### Building SnarkOS

The stress-tests/network sync test logic builds and stores built versions of SnarkOS, Talisker just provides the right env variables, features and tags/git hashes.

### Testing a version

For every repository a list of tests can be configured. This tests are run in the following manner:

1. Talisker uses the auto script to create the infrastructure for the tests.
2. Every test is ran by talisker, if the test fails, Talisker retries it a few times (configurable how many) and uploads the run log and all the node logs to the test results bucket. Talisker also keeps where it is in the test runs in a file DB, so if something kills it, it can continue from where it was left off.
3. The uploaded test if it didn't pass with 0 return code is marked as `FAILED` in the results.
4. After all the tests, Talisker cleans up the infrastructure using the auto script.

To cancel a Talisker run, just:
1. Stop talisker `sudo service talisker stop`
2. Remove the current run log file, as it can be added to in a next run, resulting in dirty log (and also it is used as a lock to not try and run another test).
3. Do a manual cleanup `cd stress_testing/test_suites/single-region-tests/` and then `./auto_run_test_suite.sh cleanup`
4. After you are done with manually running tests or other things, start Talisker.
