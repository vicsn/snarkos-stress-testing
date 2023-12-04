# Devnet IaC

- [Install Terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
  - `brew tap hashicorp/tap`
  - `brew install hashicorp/tap/terraform`
- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
  - `brew install ansible`
- [Install AWS CLI](https://aws.amazon.com/cli/)
  - `brew install awscli`

## 1. Set Up AWS Credentials

```bash
aws configure
```

Enter your AWS Access Key, Secret Key, and default region when prompted.

## 2. Terraform Initialization and Apply

```bash
terraform init
terraform apply
```

Review the plan and type `yes` to proceed.

## 3. Generate Ansible Inventory

After Terraform successfully applies, use the output to create or update the Ansible inventory file.

## 4. Run Ansible Playbook

```bash
ansible-playbook -i snarkos.aws_ec2.yml snarkos_setup.yml
ansible-playbook snarkos_run.yml
```

```bash
ssh-add ~/.ssh/snarkos-testnet.pem
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

