# Transaction Generator

By running this test suite, machines are spun up which pregenerate a large number of transactions. At the time of writing, only deployments are supported. Note that transctions are only valid for a particular number of validators and a genesis block. As such, these are the main variables which you may want to tweak in `snarkos_setup.yml`:
- `num_validators`
- `snarkos_commit`
- `num_deployments`
