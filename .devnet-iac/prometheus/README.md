# Adding a standalone Promethueus server to your network

If you want to spin up a Prometheus server to scrape metrics from all nodes in your network, run these commands (basically the same as for the entire devnet):

```
terraform init
terrafrom apply
```

And then once your resources are up, run:

```
ansible-playbook prometheus_server.yml
```

*Make sure* you have the vars changed to suit your needs, this usually means (in the `main.tf` file that you change the name of your pem private key, as well as whatever region you are set to)

You can then plug this endpoint into Grafana cloud (pending setup) to query your devnet metrics in a central place and everyone (with the correct creds) can observe them.


