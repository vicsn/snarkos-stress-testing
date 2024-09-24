# Sync client test case

This test suite tests client syncing through the following steps:
* Set up 10 validators
* Set up 28 network-driving tx-cannons to achieve 10 TPS
* Wait for 1 hour
* Sync 100 clients, 10 to each validator
* Wait for 40 minutes
* Check if clients are synced
* Sync 900 new clients with the existing clients
* Wait for 40 minutes
* Check if the new clients are synced

To run the test:

```
./run_test_suite.sh
```

Running the test requires a strong machine that is not otherwise used (especially regarding internet traffic) and a stable internet connection, due to the large amounts of clients it interacts with. As such, it can make sense to run the test from a separate EC2 instance on AWS. Running the test is also relatively expensive, as such, it can make sense to automatically destroy the infrastructure after running the test. For both cases, this command can help to start the test, destroy the infrastructure after running it, and to write the test output into a log file:

```
yes "" | ./run_test_suite.sh | tee test_suite_output.log
```