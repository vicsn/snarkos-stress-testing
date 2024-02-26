# Bootstrap validator crash attack

This folder is intended for running the bootstrap validator crashattack. For this, run the file `run_test_suite.sh`.

In the default settings, it sets up a 25 validator node network with the `kp/stress_test/bootstrap_peers` branch, which is based of the `mainnet` branch. Thsi branch sets the bootstrap peers in dev mode to the trusted peers from the node startup, which is the first node address in the scope of this test. Please note that if there are significant changes to the `mainnet` branch, it makes sense to rebase the `kp/stress_test/bootstrap_peers` branch and run the test again.

The test operates as follows:
* it starts 24 of the 25 validators
* it waits for the first few blocks to be produced
* it crashes ca. 30% of the 24 validators
* it starts the 25th validator
* it checks if the 25th validator can catch up in block height, and outputs if snarkOS passed the test

When running the test suite, nodes may get stuck in the step `Build snarkOS using build_ubuntu.sh`. In this case, double `CTRL+C` (meaning exit the test suite without destroying the infrastructure), and run the test suite again, then that build step should be quickly executed.