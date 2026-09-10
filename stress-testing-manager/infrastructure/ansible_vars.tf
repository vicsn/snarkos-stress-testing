# Terraform → shared keys.pub bridge.
# Writes <repo-root>/keys.pub from var.external_ssh_users so the
# common/roles/shared_ssh_keys role installs the same key list on
# every host that runs the role (STM + snarkos-p2p-tests).
#
# The role filters lines matching ^ssh-, so this resource writes
# each public_key on its own line with a trailing newline. Entry
# order matches tfvars declaration order.
#
# No `directory_permission` is set because the repo root always
# exists (`${path.module}/../../keys.pub` writes to the repo root,
# not to a subdirectory).
#
# OPERATOR NOTE: keys.pub is committed at the repo root so STM sync/artifact
# deploys have it without a local terraform apply. `terraform apply` still
# refreshes this file from var.external_ssh_users (see local_file below).
#
# If you edit external_ssh_users.auto.tfvars, either update keys.pub in git
# or run `tf_stack.sh provision` then commit the regenerated keys.pub.
resource "local_file" "shared_keys_pub" {
  filename        = "${path.module}/../../keys.pub"
  content         = "${join("\n", [for u in var.external_ssh_users : u.public_key])}\n"
  file_permission = "0644"
}
