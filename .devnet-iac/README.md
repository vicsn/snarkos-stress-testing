# Devnet IaC

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
  - `brew tap hashicorp/tap`
  - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
  - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
  - `brew install awscli`

## Running

```bash
aws configure
terraform init
terraform apply
ssh-add ~/.ssh/your-key.pem
ansible-playbook snarkos_setup.yml
```

## Utility Scripts
```bash
ansible-playbook snarkos_height.yml
ansible-playbook snarkos_status.yml
ansible-playbook snarkos_stop.yml
ansible-playbook snarkos_start.yml
```

## Teardown

```bash
terraform destroy
```

## Useful Commands

```bash
# Check inventory
ansible-inventory -i snarkos.aws_ec2.yml --graph
```
TODO logstash setup

TODO creating SSH key to be added on instances

TDOD edit tf variables to liking

update region in snarkos.aws_ec2.yml

todo run opensearch then save endpoint and run logstash setup
