variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "vpc_name" {
  description = "Name for the VPC network"
  type        = string
}

variable "subnets" {
  description = "Map of region to subnet config. Key = region, value = { cidr, zones }."
  type = map(object({
    cidr  = string
    zones = list(string)
  }))
}

# ------------------------------------------------
# Ops Agent Service Account (optional)

variable "enable_ops_agent_sa" {
  description = "Whether to create an Ops Agent service account and IAM bindings"
  type        = bool
  default     = false
}

variable "ops_agent_service_account_email" {
  description = "Existing Ops Agent SA email. If empty and enable_ops_agent_sa=true, a new SA is created."
  type        = string
  default     = ""
}

variable "ops_agent_service_account_id" {
  description = "Account ID for the Ops Agent SA (only used when creating a new SA)"
  type        = string
  default     = "ops-agent-sa"
}

variable "ops_agent_enable_traces" {
  description = "Whether to grant the Ops Agent SA the cloudtrace.agent role"
  type        = bool
  default     = false
}
