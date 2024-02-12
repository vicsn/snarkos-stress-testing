# 1 Million constraint program deployment attack

This folder is intended for running the 1 Million constraint program deployment attack. For this, run the file `run_test_suite.sh`. Please note that this code attacks the network from your local computer, as such, it requires an installation of `Python` (only standard libraries are required) and the `tx-cannon`.

In the default settings, it sets up an 8 validator node network with the `vicsn/stress_test_2` branch. Please note that if you change these parameters, you may need to pre-generate new transactions, as described [here](https://github.com/AleoHQ/tx-cannon/tree/testnet3/tests/1M_constraint_deployment_100_programs_50_nodes/01_pregenerate_transactions).