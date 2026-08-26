# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source        = "./modules/stress_base_ami"
  image_family  = var.image_family
  image_project = var.image_project
}

module "fwrule" {
  source             = "./modules/firewall_rule"
  target_network_tag = local.network_tag_prefix
  project            = var.gcp_project
  vpc                = local.resolved_vpc_id
  # SRT reuses the STM subnet, so the "internal" allow list IS the STM subnet CIDR set.
  # stm_source_cidrs is intentionally omitted (defaults to []) — it would produce a
  # duplicate firewall rule with identical source_ranges now that both suites share the subnet.
  allow_cidr_ranges = values(data.terraform_remote_state.stm.outputs.subnet_cidrs)
  # Bidirectional STM<>SRT all-protocols connectivity. STM's mirror rule
  # (stm_allow_srt_internal in stress-testing-manager/infrastructure/network.tf)
  # opens SRT→STM the same way. Sources cover STM VMs (tag), VPC-internal STM
  # traffic (subnet CIDRs), and external tunnels via STM (public static IP).
  allow_all_source_tags = [local.stm_network_tag]
  allow_all_source_cidrs = concat(
    ["${data.terraform_remote_state.stm.outputs.stm_public_ip}/32"],
    values(data.terraform_remote_state.stm.outputs.subnet_cidrs),
  )
}

module "tx-cannon" {
  source                   = "./modules/tx-cannon"
  count                    = var.add_tx_cannons ? 1 : 0
  image_self_link          = module.stress_base_ami.image_self_link
  network_tag              = module.fwrule.network_tag
  devnet_name              = var.devnet_name
  owner                    = var.owner
  project                  = var.gcp_project
  region                   = var.gcp_region
  zones                    = local.zones
  vpc_id                   = local.resolved_vpc_id
  subnet_self_link         = local.resolved_subnet_self_link
  tx_cannon_instance_count = var.tx_cannon_instance_count
  tx_cannon_instance_type  = var.tx_cannon_instance_type
  ssh_metadata             = local.ssh_metadata
}

# ------------------------------------------------
# snarkOS validators

resource "google_compute_instance" "snarkos_validator" {
  count        = var.validator_instance_count
  name         = "${var.owner}-${var.devnet_name}-snarkos-validator-${count.index}"
  machine_type = var.validator_instance_type
  zone         = local.zones[count.index % length(local.zones)]

  tags = [module.fwrule.network_tag]

  labels = {
    name   = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-validator-${count.index}"
    role   = "snarkos-validator"
    dev    = count.index
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }

  metadata = local.ssh_metadata

  boot_disk {
    initialize_params {
      image = module.stress_base_ami.image_self_link
      size  = var.validator_disk_size
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

# ------------------------------------------------
# snarkOS clients

resource "google_compute_instance" "snarkos_client" {
  count        = var.client_instance_count
  name         = "${var.owner}-${var.devnet_name}-snarkos-client-${count.index}"
  machine_type = var.client_instance_type
  zone         = local.zones[count.index % length(local.zones)]

  tags = [module.fwrule.network_tag]

  labels = {
    name   = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-client-${count.index}"
    role   = "snarkos-client"
    dev    = count.index
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }

  metadata = local.ssh_metadata

  boot_disk {
    initialize_params {
      image = module.stress_base_ami.image_self_link
      size  = var.client_disk_size
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

# ------------------------------------------------
# snarkOS provers

resource "google_compute_instance" "snarkos_prover" {
  count        = var.prover_instance_count
  name         = "${var.owner}-${var.devnet_name}-snarkos-prover-${count.index}"
  machine_type = var.prover_instance_type
  zone         = local.zones[count.index % length(local.zones)]

  tags = [module.fwrule.network_tag]

  labels = {
    name   = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-prover-${count.index}"
    role   = "snarkos-prover"
    dev    = count.index
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }

  metadata = local.ssh_metadata

  boot_disk {
    initialize_params {
      image = module.stress_base_ami.image_self_link
      size  = var.prover_disk_size
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

# ------------------------------------------------
# Load Balancer (TCP target pool + forwarding rule for port 3030)

resource "google_compute_http_health_check" "snarkos_health" {
  name               = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-hc"
  port               = 3030
  request_path       = "/${local.snarkos_network}/block/height/latest"
  check_interval_sec = 30
  timeout_sec        = 3
}

resource "google_compute_target_pool" "snarkos_validators" {
  name             = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-tp"
  region           = var.gcp_region
  instances        = [for i in google_compute_instance.snarkos_validator : i.self_link]
  health_checks    = [google_compute_http_health_check.snarkos_health.self_link]
  session_affinity = "NONE"
}

resource "google_compute_forwarding_rule" "snarkos_lb" {
  name        = "${local.sanitized_owner}-${local.sanitized_devnet_name}-snarkos-lb"
  region      = var.gcp_region
  target      = google_compute_target_pool.snarkos_validators.self_link
  port_range  = "3030"
  ip_protocol = "TCP"

  labels = {
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }
}

# ------------------------------------------------
# Prometheus Server

resource "google_compute_instance" "prometheus_server" {
  count        = var.prometheus_enabled ? 1 : 0
  name         = "${var.owner}-${var.devnet_name}-prometheus-server"
  machine_type = var.client_instance_type
  zone         = local.zones[0]

  tags = [module.fwrule.network_tag]

  labels = {
    name   = "${local.sanitized_owner}-${local.sanitized_devnet_name}-prometheus-server"
    role   = "prometheus-server"
    owner  = local.sanitized_owner
    devnet = local.sanitized_devnet_name
  }

  metadata = local.ssh_metadata

  boot_disk {
    initialize_params {
      image = module.stress_base_ami.image_self_link
      size  = var.prometheus_disk_size
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

# ------------------------------------------------
# Ephemeral builder (optional)

resource "google_compute_instance" "snarkos_builder" {
  count        = var.add_builder ? 1 : 0
  name         = "${var.owner}-${var.devnet_name}-snarkos-builder"
  machine_type = var.builder_instance_type
  zone         = local.zones[0]

  tags = [module.fwrule.network_tag]

  labels = {
    role   = "builder"
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

# ------------------------------------------------
# Outputs

output "snarkos_lb_ip" {
  value       = google_compute_forwarding_rule.snarkos_lb.ip_address
  description = "External IP of the TCP load balancer (port 3030)"
}

output "validator_ips" {
  value       = google_compute_instance.snarkos_validator[*].network_interface[0].network_ip
  description = "Private IPs for all validator instances"
}

output "validator_public_ips" {
  value       = google_compute_instance.snarkos_validator[*].network_interface[0].access_config[0].nat_ip
  description = "Public IPs for all validator instances"
}

output "snarkos_network" {
  value       = local.snarkos_network
  description = "The snarkos network name"
}

output "devnet_name" {
  value       = var.devnet_name
  description = "The devnet name"
}

output "snarkos_builder_ip" {
  value       = length(google_compute_instance.snarkos_builder) > 0 ? google_compute_instance.snarkos_builder[0].network_interface[0].network_ip : ""
  description = "Private IP of the ephemeral builder (empty when not provisioned)"
}

output "snarkos_builder_public_ip" {
  value       = length(google_compute_instance.snarkos_builder) > 0 ? google_compute_instance.snarkos_builder[0].network_interface[0].access_config[0].nat_ip : ""
  description = "Public IP of the ephemeral builder (empty when not provisioned)"
}
