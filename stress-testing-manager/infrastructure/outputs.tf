output "stm_private_ip" {
  description = "Internal IP of the Stress Testing Manager"
  value       = google_compute_instance.stm.network_interface[0].network_ip
}

output "stm_public_ip" {
  description = "External static IP of the Stress Testing Manager"
  value       = google_compute_address.stm_ip.address
}

output "stm_instance_name" {
  description = "GCE instance name (feed to `gcloud compute ssh`)"
  value       = google_compute_instance.stm.name
}

output "stm_zone" {
  description = "GCE zone of the STM (feed to `gcloud compute ssh --zone`)"
  value       = google_compute_instance.stm.zone
}

output "stm_sa_email" {
  description = "Service Account email attached to the STM"
  value       = google_service_account.stm_sa.email
}

output "vpc_id" {
  description = "STM VPC self-link (referenced by test suites when consolidated)"
  value       = module.network.vpc_id
}

output "vpc_name" {
  description = "STM VPC name for test suites to reference via data source"
  value       = local.vpc_name
}

output "subnet_self_links" {
  description = "Map of STM subnet self-links keyed by region"
  value       = module.network.subnet_self_links
}

output "external_ssh_users" {
  description = "List of external users authorized to SSH into the STM as the ubuntu account (name + source IP + public key). Empty when no external access is granted."
  value       = var.external_ssh_users
}

output "subnet_cidrs" {
  description = "Map of region to subnet CIDR for STM subnets; consumed by snarkos-p2p-tests via terraform_remote_state"
  value       = { (var.gcp_region) = local.stm_subnet_cidr }
}

output "results_bucket_name" {
  value       = google_storage_bucket.results.name
  description = "GCS bucket for test logs and results (owned by STM stack; consumed by SRT via terraform_remote_state and by upload scripts)."
}
