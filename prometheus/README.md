# Adding a standalone Promethueus server to your network

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

*Check that* you have the vars changed to suit your needs, this usually means (in the `main.tf` file that you change the name of your pem private key, as well as whatever region you are set to)

You can then plug this endpoint into Grafana cloud (pending setup) to query your devnet metrics in a central place and everyone (with the correct creds) can observe them.


