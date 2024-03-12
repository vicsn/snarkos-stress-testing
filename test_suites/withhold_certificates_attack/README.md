# Malicious validator certificate withholding attack

This folder is intended for running the malicious validator certificate withholding attack. For this, run the file `run_test_suite.sh`. It also automatically analyzes if a fork occured. If no fork occured, the network passes the test.

To run the test, you need to have `jq` installed: `brew install jq`

In the default settings, the test suite sets up a 25 validator node network. 24 of them run the latest `mainnet-latest` build from `snarkOS-staging`, 1 validator runs the `v0.0.1.withhold_leader_certificates` build. Please note: if there are updates to the mainnet branch, you should rebase the branch `kp/stress_test/withhold_leader_certificates` in `snarkOS-staging` and rebuild it.