# Base image lookup — the Packer-built family "stress-test-base" in
# ${var.image_project}. Same image used by test-suite validator/client
# instances; STM-specific tooling (pueue, sccache config, artifact
# fetch) is layered on via Ansible.

data "google_compute_image" "base" {
  family  = var.image_family
  project = var.image_project
}
