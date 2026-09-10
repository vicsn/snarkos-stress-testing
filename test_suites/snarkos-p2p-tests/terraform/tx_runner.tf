resource "google_compute_instance" "tx_runner" {
  name         = "${var.owner}-${var.devnet_name}-tx-runner"
  machine_type = var.tx_runner_instance_type
  zone         = local.zones[0]

  tags = [module.fwrule.network_tag]

  labels = {
    role   = "tx-runner"
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }

  metadata = local.ssh_metadata

  boot_disk {
    initialize_params {
      image = module.stress_base_ami.image_self_link
      size  = 128
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = local.resolved_vpc_id
    subnetwork = local.resolved_subnet_self_link
    access_config {}
  }

  service_account {
    email  = google_service_account.snarkos_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
