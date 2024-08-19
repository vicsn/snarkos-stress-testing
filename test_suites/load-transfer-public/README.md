## Required Configuration

- Copy `playbook/vars.example.yml` to `playbook/vars.yml` and fill in the required fields

## Optional Configuration

These configurations have defaults and are optional to set.

- Default region is `us-east-1`
- Set region in `inventory/dynamic_inventory.aws_ec2.yml` and `terraform/provider.tf`
    - Region can be left blank in `dynamic_inventory.aws_ec2.yml` to scan all regions but will be significantly slower
- Set instance type and count in `terraform/variables.yml`

## Running

`./run_test_suite.sh` will attempt to run test end to end, but this is only recommended for stable and complete tests.

## Running fake transactions

This will attempt to run the test with fake transactions end to end for 10 minutes, then stop snarkos and download the logs and ledger folders.

- Ensure the `snarkos_binary_tag` in the `vars.yml` supports fake transactions
- Potentially adjust the number of validators or tx-cannons in `variables.tf`
- Run `./run_test_suite_fake_tx.sh`
- From the `analysis_scripts` folder, run `analysis_01_prepare_logfile.py` and `analysis_02_analyze_logfile.py`

## Running steps individually

### Create infrastructure

Terraform is used to manage and create the infrastructure (e.g. EC2 instances, Security Groups, etc.).

```bash
cd terraform
terraform init # Only required once
terraform apply
```

When modifying the infrastructure, you can run `terraform apply` to update the infrastructure without destroying it.

```terraform plan``` can be used to see what changes will be made before applying them.

### Run ansible

Ansible is used to install dependencies and run the tests.

#### Run all ansible steps

```bash
cd playbooks
ansible-playbook main.yml
```

`playbooks/main.yml` is the main playbook that runs all the steps to prepare the testing environment and start the 
network.
These steps can come from the `common` folder or be specific to the test suite.

```bash
cd playbooks
ansible-playbook test.yml
```

`playbook/test.yml` sets up and executes the actual tests like the tx-cannon.

#### Skip specific ansible steps

During development or repeated runs, you may want to skip certain steps. This can be done with the `--skip-tags` flag.

```bash
cd playbooks
ansible-playbook main.yml --skip-tags "deps"
```

You can also run only specific steps with the `--tags` flag.

```bash
cd playbooks
ansible-playbook main.yml --tags "snarkos"
```

This can be useful for running only the steps you are working on, re-running a failed step, or updating a specific part 
of the environment.
For example, maybe there's a new snarkOS binary to test but you don't want to re-run the entire 
setup).

### Destroy infrastructure

Make sure to destroy the infrastructure when you are done to avoid unnecessary costs.

```bash
cd terraform
terraform destroy
```

Parallelism can be used to speed up the process of creating and destroying infrastructure.

```bash
cd terraform
terraform destroy -parallelism=200
```