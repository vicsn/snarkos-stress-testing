output "vpc_id" {
  description = "The id of the vpc"
  value       = google_compute_network.vpc.id
}

output "subnet_self_links" {
  description = "Map of subnet self-links keyed by region"
  value       = { for region, subnet in google_compute_subnetwork.subnets : region => subnet.self_link }
}

output "ops_agent_serivce_account_email" {
  description = "Email address for the ops agent service account"
  value       = local.ops_agent_sa_email
}