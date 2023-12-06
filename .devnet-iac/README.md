# Devnet IaC

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
  - `brew tap hashicorp/tap`
  - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
  - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
  - `brew install awscli`

## 0. Key Configuration

Create a `.pem` file in your desired AWS region under `EC2 > Network & Security > Key Pairs`. Download the `.pem` file and place it in your `~/.ssh` directory.

Add the key to your authentication agent and configure AWS.

```bash
ssh-add ~/.ssh/your-key.pem
aws configure
```

Change `your-key` in `variables.tf` to the name of the key you created.

## 1. Variable Configuration

Edit `variables.tf` to set your `region`, `instance type`, and `number of instances`.

Edit `snarkos.aws_ec2.yml` to the same `region` you set in `variables.tf`.

## 2. Spinning up a Devnet

```bash
terraform init
terraform apply
ansible-playbook snarkos_setup.yml
```

These commands will create the instances, install snarkOS, and start the network.

### Utility Scripts
```bash
ansible-playbook snarkos_height.yml
ansible-playbook snarkos_status.yml
ansible-playbook snarkos_stop.yml
ansible-playbook snarkos_start.yml
```

### Teardown

```bash
terraform destroy
```

### Useful Debug Commands

```bash
# Check inventory
ansible-inventory -i snarkos.aws_ec2.yml --graph
```

## 3. (Optional) Log Analytics

In the `opensearch` directory run Terraform to set up a serverless OpenSearch collection.

```bash
cd opensearch
terraform init
terraform apply
```

Copy the `collection_endpoint` and `dashboard_endpoint` from the Terraform outputs for later.

Go back to the main directory and run the `logstash_setup.yml` playbook. It will prompt you for the `collection_endpoint` and AWS access keys.

If you don't want to use your root access keys, you'll need the access keys to at least have access to the `AmazonOpenSearchIngestionFullAccess` permission.

```bash
cd ..
ansible-playbook logstash_setup.yml
```

Once this is complete, Logstash will immediately start sending logs to the OpenSearch collection. You can view the logs by navigating to the `dashboard_endpoint`.

The indices are automatically created, but you will need to [create an index pattern](https://opensearch.org/docs/latest/dashboards/management/index-patterns/) to search them in the `Discover` tab.

For more information on using OpenSearch Dashboards, check the documentation [here](https://opensearch.org/docs/latest/dashboards/index/).

Run `terraform destroy` in the `opensearch` directory to tear down the logging analytic resources. You can reuse and persist the OpenSearch collection across multiple devnets, so you should only need to do this if you are done testing.

If you need to adjust the Logstash template, it can be found at `templates/logstash.config`.

## 4. (Optional) tx-cannon ECS "botnet" cluster

In the `ecs-botnet-cluster` directory run Terraform to set up an ECS cluster and task definition for running scaled [tx-cannon](https://github.com/AleoHQ/tx-cannon) stress tests.

```bash
cd ecs-botnet-cluster
terraform init
terraform apply
```