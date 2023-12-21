## Stress Observability

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

## 0. Key Configuration

Create a `.pem` file in your desired AWS region under `EC2 > Network & Security > Key Pairs`. Download the `.pem` file
and place it in your `~/.ssh` directory.

Add the key to your authentication agent.

```bash
chmod 400 ~/.ssh/your-key.pem
ssh-add ~/.ssh/your-key.pem
```

Configure and authenticate your AWS account.

```bash
aws configure
```

## 1. Variable Configuration

Copy `terraform.tfvars.example` as `terraform.tfvars` and set your desired `region`, `instance type`,
and `number of instances`.

Set `key_pair_name` to the name of the key you created.

Edit `dynamic_inventory.aws_ec2.yml` to the same `region` you set in `terraform.tfvars`.

## 2. Spinning up a Devnet

```bash
terraform init
```

```bash
terraform apply
```

```bash
ansible-playbook snarkos_setup.yml
```

These commands will create the instances, install snarkOS, and start the network.

### Utility Scripts

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

