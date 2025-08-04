## Data used for validator testing

The data.json files contains accounts and state roots used for stress testing the validators.

The accounts can be retrieved manually by simply starting a local devnet and retrieving them by looking at the values printed to stdout.

The state roots can be retrieved by runnig a devnet with N validators (exampe: 5) and doing:

```
curl http://localhost:3030/<network>/stateRoot/0
```
