# 1 Million constraint program deployment attack

This folder is intended for running the 1 Million constraint program deployment attack. For this, run the file `run_test_suite.sh`. Please note that this code attacks the network from your local computer, as such, it requires an installation of `Python` (only standard libraries are required) and the `tx-cannon`.

In the default settings, it sets up an 25 validator node network with the `mainnet_no_tx_generation` branch. Please note that if you change these parameters (or use a newer branch that has a changed genesis block), you may need to pre-generate new transactions, as described [here](https://github.com/AleoHQ/tx-cannon/tree/testnet3/tests/1M_constraint_deployment_100_programs_50_nodes/01_pregenerate_transactions).

When running the test suite, nodes may get stuck in the step `Build snarkOS using build_ubuntu.sh`. In this case, double `CTRL+C` (meaning exit the test suite without destroying the infrastructure), and run the test suite again, then that build step should be quickly executed.