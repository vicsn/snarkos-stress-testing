# Profiling Test 1 - Client Sync-To-Tip Speed - Small Blocks

**Description**
This test will measure the client sync speed with “small” blocks with a low volume of transactions and solutions to establish a baseline syncing speed.

**Node Configuration**
10 validators with 3 core clients connected to each validator. 

**Test Specification**
Validators should first be started with 2 clients with the validators producing blocks over a period of 60 minutes. 
During this period under 5 TPS should be sent directly the 2 available clients for the first 10 minutes. For the remaining 50 minutes, 1 Unconfirmed SPS via the tx-cannon should be added to this traffic. 
After the first 60 minutes. A third client should then be started and tx-cannons should send the load to all clients.

To run the test:

```
./run_test_suite.sh
```

To adjust the client node type, adjust it in the `/terraform/variables.tf` file.