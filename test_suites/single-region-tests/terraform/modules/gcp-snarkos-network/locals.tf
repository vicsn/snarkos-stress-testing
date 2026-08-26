# ------------------------------------------------
# Define common locals
locals {
  # Email of the Ops Agent service account to attach to instances when enabled
  ops_agent_sa_email = var.enable_ops_agent_sa ? (
    var.ops_agent_service_account_email != "" ? var.ops_agent_service_account_email : google_service_account.ops_agent[0].email
  ) : ""

}