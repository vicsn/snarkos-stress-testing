output "state_bucket" {
  value       = data.google_storage_bucket.tfstate.name
  description = "GCS bucket name for Terraform remote state (pre-existing)"
}

output "state_prefix" {
  value       = var.state_prefix
  description = "Object prefix for state files inside the bucket"
}

output "service_account_email" {
  value       = data.google_service_account.terraform.email
  description = "Service account email for Terraform operations (pre-existing)"
}

output "release_bucket" {
  value       = google_storage_bucket.releases.name
  description = "GCS bucket for snarkOS release binaries"
}

output "backend_config" {
  value       = <<-EOT
    # Add this to terraform/provider.tf after bootstrap:
    terraform {
      backend "gcs" {
        bucket = "${data.google_storage_bucket.tfstate.name}"
        prefix = "${var.state_prefix}"
      }
    }
  EOT
  description = "Backend configuration snippet to paste into terraform/provider.tf"
}
