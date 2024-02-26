# Pause and resume validators

This folder is intended for running the kill_validators test.

Make sure your control node is set up to control tests
as instructed by [../../README.md](../../README.md).


For this and other test suites, set up your `../.env`
as instructed by [../README.md](../README.md).  

Additionally, in `../.env`, set `INSTANCES` to the number of validators you want to start with.
Otherwise it will default to 25 instances.

Then run
```
  ./run_test_suite.sh
```
