# Bootstrap validator crash attack

This folder is intended for running the bootstrap validator crashattack. For this, run the file `run_test_suite.sh`.

In the default settings, it sets up a 25 validator node network with the `v0.0.1.bootstrap_peers` build from `snarkos-staging`. Please note that if there updates to snarkos, you should rebase and rebuild the `kp/stress_test/bootstrap_val_crash` branch in snarkos-staging. This branch sets the bootstrap peers in dev mode to the trusted peers from the node startup, which is the first node address in the scope of this test.

The test operates as follows:
* it starts 24 of the 25 validators
* it waits for the first few blocks to be produced
* it crashes ca. 30% of the 24 validators
* it starts the 25th validator
* it checks if the 25th validator can catch up in block height, and outputs if snarkOS passed the test