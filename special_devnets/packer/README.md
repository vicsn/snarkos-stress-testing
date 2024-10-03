## Using

Latest built by Brent can automatically be pulled via `stress_base_ami` module found at `common/terraform_modules/stress_base_ami/main.tf`

```terraform
module "stress_base_ami" {
    # source = "../../../common/terraform_modules/stress_base_ami"
    source = "../../../common/terraform_modules/ubuntu_ami"
}
```

## Prerequisites

- [packer](https://developer.hashicorp.com/packer/install)

## Building and publishing

```bash
packer init tress-test-base.json.pkr.hcl 
packer build stress-test-base.json.pkr.hcl 
```

## Other notes

Currently available for `["us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-north-1"]`

You have to run `disable-image-block-public-access` in each region you want the AMI published to.

For example: `aws ec2 disable-image-block-public-access --region us-east-1`

