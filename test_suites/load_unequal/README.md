# Load unequal attack

This test suite:
* Starts a devnet with 10 validators of type `c6a.8xlarge`, val 0 does not generate txs
* Starts and connects 10 clients of type `c6a.8xlarge`, 1 to each validator
* Starts a network-driving tx-cannon that, in an infinite loop, randomly selects a client and sends a single tx to the client
* Starts 165 attacking tx cannons, which, in an infinite loop, target `f+1` (4) clients with 1M constraint program deployment txs

To run the attack:

```
./run_test_suite.sh
```

The file `copy_logs_from_aws.sh` is not part of the normal attack execution, but may help you to debug it.