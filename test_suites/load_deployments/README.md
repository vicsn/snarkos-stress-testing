# Load deployments extension attack

This test suite runs different deployments:
* 300,000 constraints through 50% of the attacker tx-cannons
* slightly below 1 million constraints through 25% of the attacker tx-cannons
* more than 1 million (1,002,981) constraints but underreporting the number of constraints by 10 through 25% of the attacker tx-cannons

For this, it spins up 10 validator nodes in one region, and transaction cannon nodes to attack in other regions (total: 168 attacker tx-cannons). It does not use any network driving tx cannon node by default.

To run the attack:

```
./run_test_suite.sh
```

The file `copy_logs_from_aws.sh` is not part of the normal attack execution, but may help you to debug it.