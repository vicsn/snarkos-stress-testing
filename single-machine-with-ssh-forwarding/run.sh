#!/bin/bash

set -euo pipefail

# SSH_KEY_PATH is the *forwarded* key: it never leaves the laptop, it is only
# exposed to the instance through the ssh-agent so git can reach private repos.
: "${SSH_KEY_PATH:?Environment variable SSH_KEY_PATH is required}"

export SSH_KEY_PATH="$SSH_KEY_PATH"

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "❌ SSH key not found at $SSH_KEY_PATH"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Login to the instance uses a throwaway pair created here, so no long-lived
# personal key is ever registered with AWS. Reused across repeated `setup`
# runs: AWS only injects the key pair at first boot, so rotating it would
# lock us out of an already-running instance. `cleanup` deletes it.
EPHEMERAL_KEY="$SCRIPT_DIR/ephemeral-key"
EPHEMERAL_KEY_PUB="$EPHEMERAL_KEY.pub"
export TF_VAR_PUBLIC_KEY_PATH="$EPHEMERAL_KEY_PUB"

ensure_ephemeral_key() {
  if [ -f "$EPHEMERAL_KEY" ] && [ -f "$EPHEMERAL_KEY_PUB" ]; then
    echo "[*] Reusing ephemeral SSH key at $EPHEMERAL_KEY"
    return
  fi

  echo "[*] Creating ephemeral SSH key at $EPHEMERAL_KEY"
  rm -f "$EPHEMERAL_KEY" "$EPHEMERAL_KEY_PUB"
  ssh-keygen -t ed25519 -f "$EPHEMERAL_KEY" -N '' -C "single-machine-with-ssh-forwarding-$USER" >/dev/null
  chmod 400 "$EPHEMERAL_KEY"
}

command="${1:-usage}"

usage() {
  echo "----------"
  echo -e "Usage:\n" 1>&2
  echo -e "Set up:\n"  1>&2
  echo "  $0 setup" 1>&2
  echo -e "\n  Sets up the infrastructure." 1>&2
  echo -e "\nClean up:\n"  1>&2
  echo -e "  $0 cleanup" 1>&2
  echo -e "  $0 destroy" 1>&2
  echo -e "\n  Cleans up the infrastructure. Basically runs terraform destroy." 1>&2
  echo "----------"
  exit 0
}

setup() {
  ensure_ephemeral_key

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

  # Only the forwarded key belongs in the agent; the ephemeral key is used
  # directly via IdentityFile so it is never exposed to the instance.
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
      echo "  IdentityFile $EPHEMERAL_KEY"
      echo "  IdentitiesOnly yes"
    } >> "$SSH_CONFIG_FILE"
  fi

  cd ..

cat > inventory.ini <<EOF
[github_forwarded]
single-machine-with-ssh-forwarding ansible_host=$INSTANCE_IP ansible_user=ubuntu ansible_ssh_private_key_file=$EPHEMERAL_KEY ansible_ssh_common_args='-o ForwardAgent=yes -o IdentitiesOnly=yes'
EOF

  # JSON form, not key=value: the latter splits on whitespace, which would
  # mangle any path containing spaces.
  ansible-playbook -i inventory.ini -u ubuntu playbook.yml \
    --extra-vars "{\"ephemeral_public_key_path\": \"$EPHEMERAL_KEY_PUB\"}"

  echo "[+] Connect with: ssh single-machine-with-ssh-forwarding"
  echo "    or: ssh -A -i $EPHEMERAL_KEY ubuntu@$INSTANCE_IP"
}

cleanup() {
  # terraform still needs the public key to resolve aws_key_pair before it can
  # destroy it, so the key is only deleted after the destroy succeeds.
  ensure_ephemeral_key

  cd terraform

  INSTANCE_IP=$(terraform output -raw public_ip 2>/dev/null || true)

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
  rm -f "$EPHEMERAL_KEY" "$EPHEMERAL_KEY_PUB"

  # Stale entry would break the next setup: the host key changes with the new
  # instance while the IP can be recycled by AWS.
  if [ -n "$INSTANCE_IP" ]; then
    ssh-keygen -R "$INSTANCE_IP" >/dev/null 2>&1 || true
  fi
}

case $command in
  setup)
    echo "Infrastructure setup initiated."

    setup
    exit 0
    ;;
  cleanup|destroy)
    echo "Infrastructure cleanup initiated."
    cleanup
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
