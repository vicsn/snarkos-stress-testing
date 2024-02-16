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
stress-tests
│ └─ flood-attack
│   └─ run_test_suite.sh
│   └─ ansible.cfg
│   └─ dynamic_inventory.aws_ec2.yml
│   └─ main.tf
│   └─ snarkos_setup.yml
```

## Steps Prior to Executing Tests

First perform the setup in the [top level README](../README.md).

Copy `.env.example` to `.env` and fill the environment variables.

## Transaction Cannon Tests

Prior to running a transaction cannon test, a tx-cannon test needs to be created:

[A full guide on creating a tx-cannon test can be found here](https://github.com/AleoHQ/tx-cannon/blob/feat/save-deployments-to-file/CREATING_NEW_TESTS.md)

## Running the tests

From the folder where your `.env` file is written, change directory and run your preferred test suite:

```
cd flood-attack && ./run_test_suite.sh
```

## Building new binaries

To speed up testing, you can use pre-built binaries for the `binaries_tag` environment variable. Here are the instructions to making new ones manually.

First, create machine(s) of your choice.

To build snarkOS:
```
ssh ubuntu@<machine_ip>
git clone https://github.com/AleoHQ/snarkOS.git
cd snarkOS
git checkout origin/mainnet_no_tx_generation
./build_ubuntu.sh
exit
scp ubuntu@${machine_ip}:snarkOS/target/release/snarkos .
```

To build tx-cannon:
```
git clone https://${personal_access_token}@github.com/aleoHQ/tx-cannon.git
cd tx-cannon
git checkout origin/mainnet
./build_ubuntu.sh
exit
scp ubuntu@${machine_ip}:tx-cannon/target/release/tx-cannon .
```

Then you can make a new release following the [initial example](https://github.com/AleoHQ/stress-observability/releases/tag/v0.0.1), incrementing the version number.