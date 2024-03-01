# Unbond 30% of validators, then rebond

This folder is intended for running the unbonding 30% of validators, waiting 2 hours, and rebonding test.

This should all happen in the regular snarkos_setup.yml ansible script, but I left an extra playbook- `rebond_nodes.yml` in case there is a reason to try manually rebonding if something fails.

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
