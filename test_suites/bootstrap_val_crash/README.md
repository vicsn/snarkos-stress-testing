# Bootstrap validator crash attack

This folder is intended for running the bootstrap validator crashattack. For this, run the file `run_test_suite.sh`.

In the default settings, it sets up a 10 validator node network with the `malice-latest` build from `snarkos-staging`. Thereby, it uses the malice mode `UseBootstrapPeers` to set the bootstrap peers to the first node.

The test operates as follows:
* it starts 9 of the 10 validators
* it waits for the first few blocks to be produced
* it crashes ca. 30% of the 9 validators
* it starts the 10th validator
* it checks if the 10th validator can catch up in block height, and outputs if snarkOS passed the test