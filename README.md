# Stress Observability

The intention of this repo is to be an alternative to
the [.devnet folder](https://github.com/AleoHQ/snarkOS/tree/testnet3/.devnet)
of snarkOS with an infrastructure as code (IaC) approach to allow for faster iterations on stress testing.

It also contains extra tools to set up better observability and infrastructure related to stress testing specifically.

## Devnet IaC

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
    - `brew tap hashicorp/tap`
    - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
    - `brew install awscli`

## 1. Variable Configuration

Make sure you make a copy of the `.env/example` file in the home directory as just `.env`, and fill the values in for Elastic and Grafana cloud as well as the desired devnet name.

Fill in the variables for single or multi region regions and instance counts (or both, it doesnt matter) and these will automatically populate in the terraform folders for you when running the startup scripts.

## 2. Spinning up a Devnet


**Single Region Devnet**
```bash
./run_single_region_devnet.sh
```
**Multi Region Devnet**
```bash
./run_multi_region_devnet.sh
```


### **Congratulations!**
 You have now started the instances, installed snarkOS, and started your network.

-----

# Viewing Logs in Elastic Cloud

The Elastic cloud setup is a faster way to search logs of every node on your dev network. To set it up, run the below command in the main directory:

By default, the above scripts ship logs to the [Elastic Cloud server](https://stress-test.kb.us-east-2.aws.elastic-cloud.com:9243/app/discover) by giving it a cloud ID and API key.

If you want to see only **your** devnet logs, type this filter in the top query bar:

```
_index: "snarkos-logs-$DEVNET_NAME*"
```

e.g. if the configured devnet name is `howard_devnet`, you would query:

```
_index: "snarkos-logs-howard_devnet*"
```


[logstash.conf](templates%2Flogstash.conf) can be edited to ship the logs anywhere else.

-------
# Viewing Metrics on Grafana
Once these steps are complete, you should be able to access your metrics [here](https://aleostresstest.grafana.net/explore?schemaVersion=1&panes=%7B%22_Tc%22%3A%7B%22datasource%22%3A%22grafanacloud-prom%22%2C%22queries%22%3A%5B%7B%22refId%22%3A%22A%22%2C%22expr%22%3A%22%22%2C%22range%22%3Atrue%2C%22instant%22%3Atrue%2C%22datasource%22%3A%7B%22type%22%3A%22prometheus%22%2C%22uid%22%3A%22grafanacloud-prom%22%7D%7D%5D%2C%22range%22%3A%7B%22from%22%3A%22now-6h%22%2C%22to%22%3A%22now%22%7D%7D%7D&orgId=1)

You can filter to select only nodes in your network using the `Label Filters`, click `origin_prometheus` as the filter and then the name of your devnet.

-------

# Utility Scripts

All in the `ansible_commands` directory:

```bash
ansible-playbook snarkos_height.yml
```

```bash
ansible-playbook snarkos_status.yml
```

```bash
ansible-playbook snarkos_stop.yml
```

```bash
ansible-playbook snarkos_start.yml
```

### Teardown

```bash
terraform destroy
```

### Useful Debug Commands

```bash
# Check inventory
ansible-inventory -i dynamic_inventory.aws_ec2.yml --graph
```

