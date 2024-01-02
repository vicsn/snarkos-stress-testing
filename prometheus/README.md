# Adding a standalone Promethueus server to your network & Grafana Cloud viewing capabilities

If you want to spin up a Prometheus server to scrape metrics from all nodes in your network, first start your devnet. **Make sure** you add a metrics flag to [this](https://github.com/AleoHQ/stress-observability/blob/main/.devnet-iac/templates/snarkos.service#L12) `snarkos` command to run snarkos on your devnet using the metrics crate. 

Then, run these commands (basically the same as for the entire devnet):

```
terraform init
terrafrom apply
```

And then once your resources are up, run:

```
ansible-playbook prometheus_server.yml
```

This will ask for an input of your name, this is for remote forwarding of metrics to our Grafana Cloud server such that we can identify the unique nodes for each network

*Check that* you have the vars changed to suit your needs, this usually means (in the `main.tf` file that you change the name of your pem private key, as well as whatever region you are set to)

You can then plug this endpoint into Grafana cloud (pending setup) to query your devnet metrics in a central place and everyone (with the correct creds) can observe them.

# Viewing Metrics on Grafana
Once these steps are complete, you should be able to access your metrics [here](https://aleostresstest.grafana.net/explore?schemaVersion=1&panes=%7B%22_Tc%22%3A%7B%22datasource%22%3A%22grafanacloud-prom%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22expr%22%3A%22%22%2C%22range%22%3Atrue%2C%22instant%22%3Atrue%2C%22datasource%22%3A%7B%22type%22%3A%22prometheus%22%2C%22uid%22%3A%22grafanacloud-prom%22%7D%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-6h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1)

You can filter to select only nodes in your network using the `Label Filters` and then the name of your devnet, which is simply the name you input earlier with the `_devnet` suffix


