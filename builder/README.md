# Aleo SnarkOS Builder and stress tests Tester

A machine that can react to new SnarkOS releases and can build a SnarkOS binary which than can be used and reused
to run the stress tests.

## Creating the Builder

### Base AMI dependency

The Builder uses its own base AMI image (can be build using the scripts int he `packer` folder).
The image is based on Ubuntu 22 and includes a lot of tools for debugging and building SnarkOS.
It contains Rust/Cargo, AWS cli, git, Ansible and Terraform.

It is prebuild in the Foundation AWS snadbox (`eu-central-1`, `148761683502`), but that can be modified to be built in
another region and account. Just modify the region in `packer/image.json.pkr.hcl`, export your `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` in the current terminnal and navigate to the `packer` folder. Run:

```
packer build image.json.pkr.hcl
```

Then add your account to the list in `infrastructure/base_ami.tf` on line `4`. Now the image will be available for your
account too.

### Running terraform

Navigate to `infrastructure` and run:

```
terraform apply
```

This will create the Builder using the base image from the previous section as base.
What does that include?
1. A machine of type `t2.medium` (the minimum that can build SnarkOS) with 100GB of storage (to store logs and binaries).
2. A profile giving the machine a lot of rights in AWS - to create and destroy instances, access S3, create and destroy networks, etc. This is needed so stress tests can be ran from it and these tests create instances and a network, read things from S3, etc. The whole list of accesses can be viewd in `infrastructure/ec2_profile.tf`, line `19`.
3. A small VPC that gives us access to the builder via ssh. It can be expanded to include some simple web interface and static IP for it.

Keep in mind that in order to create the Builder, first you need to export `TF_VAR_AWS_ACCESS_KEY` and `TF_VAR_AWS_SECRET_KEY`.
Additionally you need a github token with read access to this repository (so the builder can download the tests). Export it with `TF_VAR_github_token`.

### Provisioning with Ansible

You don't need to run Ansible yourself. The provisioning automatically kicks in via the `terraform apply` command.
The playbook is defined in `infrastructure/ansible/playbook.yml`.
It does:

1. Downloads the stress tests from `github.com/ProvableHQ/stress-testing.git` and puts them in the folder `stress_testing` (the `ubuntu` user home is the base for all of these resources).
2. Installs python (needed for Ansible and AWS cli/S3 access). It is in the base image, but that will update it to newest.
3. Downloads the `talisker` release from the `snarkos-releases-for-testing` S3 bucket. (We will make it possible to install it from somewhere else soon).
4. Runs `talisker` as a service (this is the software that detects new releases, kicks the builds, puts the binaries at accessible places, manages the test runs and retries and uploads the logs from them).
5. Sets up the right test vars that are specific for the automated runs.

## Removing the Builder

The builder is stateless, so it can be removed and created whenever we decide to do so.
Just run:

```
terraform destroy
```

in the `infrastructure` folder.


## Updating the Builder

Just run again:

```
terraform apply
```

in the `infrastructure` folder.

This will evaluate the ansible playbook again in addition to any infrastructure changes, meaning the newest Talisker
will get intalled and the newest version of the tests will get pulled.

