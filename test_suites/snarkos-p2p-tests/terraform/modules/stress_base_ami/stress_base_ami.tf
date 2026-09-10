variable "image_family" {
  description = "GCP image family to use for base OS"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "image_project" {
  description = "GCP project that owns the image family"
  type        = string
  default     = "ubuntu-os-cloud"
}

data "google_compute_image" "stress_base" {
  family  = var.image_family
  project = var.image_project
}

output "image_self_link" {
  value       = data.google_compute_image.stress_base.self_link
  description = "Self-link of the latest image in the family"
}

output "image_id" {
  value       = data.google_compute_image.stress_base.image_id
  description = "ID of the latest image in the family"
}
