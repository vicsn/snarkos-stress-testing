# Profiling Test 2 - Client Sync-To-Tip Speed - Large Blocks

**Description**
This test will measure the client sync speed with “large” blocks with a high volume of transactions and solutions.

**Node Configuration**
10 validators with 3 core clients connected to each validator. 

**Test Specification**
Validators should first be started with 2 clients with the validators producing blocks over a period of 35 minutes. 
During this period of 35 minutes - the following load should be sent:
* 15 TPS of transfer_publics
* 2 Unconfirmed SPS via the tx-cannon should be added to this traffic with valid solutions. 
* 2 Unconfirmed SPS via the tx-cannon should be added to this traffic with invalid solutions. 
* 5 tx-cannons sending rejected and aborted transactions should be started
* 3 tx-cannons running deploys of 300K constraints
* 5 tx-cannons running bond.
After the first 35 minutes. A third client should then be started on each validator and tx-cannons should send the load to all clients. The speed of the clients syncing to tip should then be measured.


To run the test:

```
./run_test_suite.sh
```

To adjust the client node type, adjust it in the `/terraform/variables.tf` file.