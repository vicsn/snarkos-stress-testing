# 1 Million constraint program deployment attack

This folder is intended for running the 1 Million constraint program deployment attack. For this, run the file `run_test_suite.sh`. Please note that this code attacks the network from your local computer, as such, it requires an installation of `Python` (only standard libraries are required) and the `tx-cannon`.

In the default settings, it sets up a 10 validator node network with the `mainnet-staging-latest` branch. Please note that if you change these parameters (or use a newer branch that has a changed genesis block), you may need to pre-generate new transactions, see the `stress-observability/test_suites/tx_generator` folder.