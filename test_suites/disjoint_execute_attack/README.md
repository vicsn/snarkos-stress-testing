# Disjoint program execution - BHP 256 500

This test suite runs deploys a BHP 256 500 program (in a finalize context), and then sends 4 disjoint executions to each validator. For this, it spins up 25 validator nodes in one region, and 25 transaction cannon nodes to attack in another region. It also spins up a network driving tx cannon node.

To run the attack:

```
./run_normal_network_traffic.sh
```

The files `copy_logs_from_aws.sh`, `stop_and_restart_snarkos.yml`, `check_transaction_status.py` are not part of the normal attack execution, but may help you to debug it.