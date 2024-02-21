# Aleo Network Stress Tests

This folder contains several folders with scripts that construct the infrastructure needed to run specific stress test
cases on the Aleo Network and execute the tests. 

## Organization
Each stress test folder will have the following:
* Setup scripts for setting up the SnarkOS testnet + metrics
* A script for running the stress test
* A readme with instructions on how to run the stress test

The tests may differ in their needs, but will be organized similar to the following:

```
test_suites
│ └─ hello_hello # Example test suite
│   └─ templates # SnarkOS systemd service + logstash config
│   │   └─ logstash.conf
│   │   └─ snarkos.service # Change this file if you need a custom SnarkOS start command
│   └─ ansible.cfg
│   └─ docker-compose.yml
│   └─ dynamic_inventory.aws_ec2.yml
│   └─ main.tf # Edit this file to change the number & type of AWS instances
│   └─ prometheus.tf
│   └─ run_test_suite.sh
│   └─ snarkos_setup.yml # Edit this file to setup your custom test code
```

## Steps Prior to Executing Tests

### 1. Copy `.env.example` to `.env` and fill the environment variables.
```txt
## Make a github token with repo access and paste it here
GITHUB_TOKEN=your_github_token_here

## ASK YOUR ADMINS FOR THESE:
ELASTIC_CLOUD_ID=your_elastic_cloud_id
ELASTIC_API_KEY=your_elastic_api_key
GRAFANA_CLOUD_API_KEY=your_grafana_api_key

## Name this whatever you want
DEVNET_NAME=your_devnet_name
```

### 2. Edit your main.tf file
Edit your main.tf file to change the number & type of AWS instances you need for the test.
```terraform
variable "aws_region" {
default     = "us-west-2"
}
```

```terraform
variable "instance_type" {
  description = "Instance type for client nodes"
  default     = "m5.4xlarge"
}

variable "instance_count" {
  description = "Number of client nodes"
  default     = 5
}
```

### 3. Modify your `snarkos_setup.yml` file to include your test steps
Your test likely requires some custom setup steps. You can add these steps to the `snarkos_setup.yml` file.


## Transaction Cannon Tests

Prior to running a transaction cannon test, a tx-cannon test needs to be created:

[A full guide on creating a tx-cannon test can be found here](https://github.com/AleoHQ/tx-cannon/blob/feat/save-deployments-to-file/CREATING_NEW_TESTS.md)

## Running the tests

From the folder where your `.env` file is written, change directory and run your preferred test suite:

```
cd hello_hello && ./run_test_suite.sh
```

## Using Pre-built Binaries

You can add pre-built binaries to your test suite to speed up testing. [A full guide is here](PREBUILD.md)