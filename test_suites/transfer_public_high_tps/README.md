# Transfer public high TPS

This test suite tests the network with a high transfer public TPS load for one hour. In its default setting, it sends ca. ~38 TPS, but this can be adjusted.

To run the test:

```
./run_test_suite.sh
```

To adjust the TPS:
* Currently, the test uses 180 `m5.2xlarge` tx-cannons (12 regions, 15 per region) 
* One iteration of the toml file with 10 transactions takes 47 seconds
* Thus, the TPS of the tx-cannons is computed as `180*10/47 = 38.3 TPS`
* Additionally, validator 0 generates ~0.3 TPS