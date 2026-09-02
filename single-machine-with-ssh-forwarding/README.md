# Single Machine With SSH Forwarding

A machine to run tools in AWS forwarding keys, so access to private github repositories is possible.

## Prerequisite

### Install SSH Agent

On macOS, the SSH agent is built-in and runs by default as part of the system. You don’t need to install it — but you may need to configure it correctly to forward your key.
Run this to start it:

```
eval "$(ssh-agent -s)"
```

### Install Terraform

```
brew update

brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify here:
terraform version
```

Or manual install:

Go to https://www.terraform.io/downloads.html, grab the macOS (amd64 or arm64) archive, then:

```
unzip terraform_<VERSION>_darwin_amd64.zip      # or arm64 if on Apple Silicon
sudo mv terraform /usr/local/bin/
sudo chmod +x /usr/local/bin/terraform

# Verify here:
terraform version

echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Install Ansible

Here is how to do it with brew:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew update
brew install ansible

# verify here:
ansible --version
```

Can be done with python to isolate Ansible per project:

```
python3 -m venv venv
source venv/bin/activate
pip install ansible
ansible --version
```

## AWS authentication

Authentication happens via Google SSO:
- Via `drive.google.com`, go to the top right apps icon, click on the app called "AWS access portal".
- Choose a scope and click on "Access keys".
- Follow the steps to authenticate using `aws configure sso`.
  - The profile name should be the same as the profile in `terraform/main.tf`.
- After initial setup, you can use `aws sso login --profile <profile>` 

## Setup

Before running you can edit `terraform/main.tf` to optionally change attributes of the instance like its `instance_type`.

Now you can run:

```
export SSH_KEY_PATH=<absolute-path-to-your-private-key-to-be-forwarded>

./run.sh setup
```

`SSH_KEY_PATH` is only forwarded through the ssh-agent so the instance can reach private
GitHub repositories — it is never installed on the machine.

Login to the machine uses a separate ephemeral key pair that `run.sh` generates at
`ephemeral-key` in this directory. Its public half is registered as the AWS key pair and
installed into `~ubuntu/.ssh/authorized_keys` by the playbook. It is reused across repeated
`setup` runs (rotating it would force instance replacement) and deleted by `./run.sh cleanup`.

`run.sh` also writes an SSH config entry, so after setup you can connect with:

```
ssh single-machine-with-ssh-forwarding
```

Or explicitly, using the printed IP:

```
ssh -A -i ephemeral-key ubuntu@52.12.101.154
```

Now you can use the machine and will have full access to github private repositories.

To quickly get started with snarkVM projects, you may want to:

```
git clone git@github.com:ProvableHQ/snarkOS.git
cd snarkOS && ./build_ubuntu.sh
```

## Cleanup

Run:

```
./run.sh cleanup
```

This will remove the instance and remove it from the ssh config too.
