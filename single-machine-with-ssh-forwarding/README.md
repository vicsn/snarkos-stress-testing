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
export SSH_KEY_PATH_PUB=<absolute-path-to-the-public-counterpart-of-the-key-so-the-instance-can-be-created-with-it>

./run.sh setup
```

This will do the key forwarding and create an instance for testing, also check the ssh forwarding.
It also will print the IP of the instance. Now:

```
ssh -A -i <path-to-the-same-private-key> ubuntu@<the-public-ip-printed>
```

For example it can be done with:

```
ssh -A -i ~/.ssh/id_rsa ubuntu@52.12.101.154
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
