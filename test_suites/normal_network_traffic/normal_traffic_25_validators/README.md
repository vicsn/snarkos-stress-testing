### Description
The test is designed to stress test the network's ability to handle a very large number of concurrent finalize transactions
using compute-heavy hash opcodes.

### Usage

## To Deploy:

```
tx-cannon batch-deploy --manifest tests/ridiculous_finalize_hash/ridiculous_finalize_hash.txt -k APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH -e http://<your_node>:3033
```

## To Execute: 

```
tx-cannon batch-execute --test tests/ridiculous_finalize_hash/ridiculous_finalize_hash.toml -e http://<your_node>:3033
```