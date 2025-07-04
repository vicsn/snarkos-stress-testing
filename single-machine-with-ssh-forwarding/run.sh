#!/bin/bash

set -euo pipefail

: "${SSH_KEY_PATH:?Environment variable SSH_KEY_PATH is required}"
: "${SSH_KEY_PATH_PUB:?Environment variable SSH_KEY_PATH_PUB is required}"

export SSH_KEY_PATH="$SSH_KEY_PATH"
export TF_VAR_PUBLIC_KEY_PATH="$SSH_KEY_PATH_PUB"

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "❌ SSH key not found at $SSH_KEY_PATH"
  exit 1
fi

command="${1:-usage}"

usage() {
  echo "----------"
  echo -e "Usage:\n" 1>&2
  echo -e "Set up:\n"  1>&2
  echo "  $0 setup" 1>&2
  echo -e "\n  Sets up the infrastructure." 1>&2
  echo -e "\nClean up:\n"  1>&2
  echo -e "  $0 cleanup" 1>&2
  echo -e "\n  Cleans up the infrastructure. Basically runs terraform destroy." 1>&2
  echo "----------"
  exit 0
}

setup() {
  cd terraform

  terraform init
  terraform apply -auto-approve

  INSTANCE_IP=$(terraform output -raw public_ip)

  echo "[*] Waiting for SSH to become available on $INSTANCE_IP..."
  for i in {1..30}; do
    if nc -z "$INSTANCE_IP" 22 >/dev/null 2>&1; then
      echo "[+] SSH is available."
      break
    fi
    echo "  ...still waiting ($i)"
    sleep 5
  done

  # If not reachable after timeout
  if ! nc -z "$INSTANCE_IP" 22 >/dev/null 2>&1; then
    echo "❌ SSH not reachable after timeout"
    exit 1
  fi

  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)"
  fi

  # Add key to ssh-agent if not already added
  if ! ssh-add -l | grep -q "$SSH_KEY_PATH"; then
    ssh-add "$SSH_KEY_PATH"
  fi

  SSH_CONFIG_FILE="$HOME/.ssh/config"
  if ! grep -q "Host single-machine-with-ssh-forwarding" "$SSH_CONFIG_FILE" 2>/dev/null; then
    echo "Adding Host config for single-machine-with-ssh-forwarding"
    {
      echo ""
      echo "Host single-machine-with-ssh-forwarding"
      echo "  HostName $INSTANCE_IP"
      echo "  User ubuntu"
      echo "  ForwardAgent yes"
      echo "  IdentityFile $SSH_KEY_PATH"
    } >> "$SSH_CONFIG_FILE"
  fi

  cd ..

cat > inventory.ini <<EOF
[github_forwarded]
single-machine-with-ssh-forwarding ansible_host=$INSTANCE_IP ansible_user=ubuntu ansible_ssh_common_args='-o ForwardAgent=yes'
EOF

  ansible-playbook -i inventory.ini -u ubuntu playbook.yml
}

cleanup() {
  cd terraform

  terraform destroy -auto-approve

  # Remove SSH config entry for single-machine-with-ssh-forwarding
  SSH_CONFIG_FILE="$HOME/.ssh/config"
  if grep -q "Host single-machine-with-ssh-forwarding" "$SSH_CONFIG_FILE" 2>/dev/null; then
    echo "Removing SSH config entry for single-machine-with-ssh-forwarding"
    # Remove the block from "Host single-machine-with-ssh-forwarding" to the next empty line or end
    awk '
      BEGIN { skip=0 }
      /^Host single-machine-with-ssh-forwarding$/ { skip=1; next }
      skip && /^$/ { skip=0; next }
      !skip
    ' "$SSH_CONFIG_FILE" > "$SSH_CONFIG_FILE.tmp" && mv "$SSH_CONFIG_FILE.tmp" "$SSH_CONFIG_FILE"
  fi

  rm -f ../inventory.ini
}

case $command in
  setup)
    echo "Infrastructure setup initiated."

    setup
    exit 0
    ;;
  cleanup)
    echo "Infrastructure cleanup initiated."
    cleanup
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
