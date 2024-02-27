Copy vars.example.yml to vars.yml and fill in your variables

Set same region in `dynamic_inventory.aws_ec2.yml` and `main.tf`

```bash
ssh-keygen -t rsa -b 4096 -f "tx-cannon" -N ''
chmod 400 "devnet-key"
```

```bash
terraform init
```

```bash
terraform apply
```

```bash
ansible-playbook tx-cannon_setup.yml
```

```bash
terraform destroy
```
