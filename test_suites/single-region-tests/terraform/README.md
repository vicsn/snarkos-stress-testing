# GCP Migration

This module was refactored from AWS to GCP. All AWS resources removed. GCP equivalents in place.

---

## AWS → GCP mapping

| AWS | GCP |
|---|---|
| `aws_instance` | `google_compute_instance` |
| `aws_key_pair` | OS Login (IAM-based SSH, no key files) |
| `aws_elb` | `google_compute_target_pool` + `google_compute_forwarding_rule` |
| `aws_security_group` | `google_compute_firewall` rules + network tags |
| `aws_iam_role` + `aws_iam_instance_profile` | `google_service_account` |
| `aws_iam_policy` (S3) | `google_project_iam_member` (GCS IAM bindings) |
| `data.aws_ami` | `data.google_compute_image` |
| `data.aws_availability_zones` | `data.google_compute_zones` |
| `ebs_block_device` | `boot_disk.initialize_params` (`pd-ssd`) |
| S3 bucket ARNs | GCS bucket names via `var.release_bucket` |
| `provider "aws"` profile `ephnet` | `provider "google"` with `var.gcp_project` |

---

## Instance type mapping

| Role | AWS (old) | GCP (new) |
|---|---|---|
| Validator (light) | `m7i.8xlarge` (32 vCPU) | `c3d-standard-30` (30 vCPU) |
| Validator (heavy) | `m7i.16xlarge` (64 vCPU) | `c3d-standard-60` (60 vCPU) |
| Client (light) | `m7i.2xlarge` (8 vCPU) | `c3d-standard-8` (8 vCPU) |
| Client (heavy) | `m7i.8xlarge` (32 vCPU) | `c3d-standard-30` (30 vCPU) |
| Client (prerelease) | `m7i.4xlarge` (16 vCPU) | `c3d-standard-16` (16 vCPU) |
| Prover | `m7i.2xlarge` (8 vCPU) | `c3d-standard-8` (8 vCPU) |
| TX Runner | `c7i.8xlarge` (32 vCPU) | `c3d-standard-30` (30 vCPU) |
| TX Cannon | `m5.2xlarge` (8 vCPU) | `c3d-standard-30` (30 vCPU) |

All boot disks use `pd-ssd`. Sizes unchanged (validators/clients/provers: 1000 GB; tx_runner: 128 GB; prometheus: 80 GB; tx_cannon: 20 GB).

---

## Prerequisites

- GCP project with billing enabled
- APIs enabled: `compute.googleapis.com`, `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`
- `gcloud` CLI authenticated: `gcloud auth application-default login`
- Terraform >= 1.3

Enable APIs if needed:

```bash
gcloud services enable compute.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

---

## SSH access

OS Login replaces key-pair files. To SSH into any node:

1. Grant yourself OS Login access:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="user:you@example.com" \
  --role="roles/compute.osLogin"
```

2. SSH using `gcloud`:

```bash
gcloud compute ssh INSTANCE_NAME --zone=ZONE --project=YOUR_PROJECT_ID
```

Or with standard `ssh` after adding your key via OS Login:

```bash
gcloud compute os-login ssh-keys add --key-file=~/.ssh/id_ed25519.pub
ssh -i ~/.ssh/google_compute_engine USERNAME_example_com@EXTERNAL_IP
```

---

## Usage

### Deployment profiles

Three profiles are available as `.tfvars` files:

| File | Validators | Validator type | Notes |
|---|---|---|---|
| `light.tfvars` | 5 | `c3d-standard-30` | Minimum for prerelease tests |
| `heavy.tfvars` | 40 | `c3d-standard-60` | Large-scale stress tests |
| `prerelease-default.auto.tfvars` | 40 | `c3d-standard-30` | Auto-loaded; prerelease devnet |

`prerelease-default.auto.tfvars` is loaded automatically by Terraform. To use `light` or `heavy`, pass it explicitly with `-var-file`.

### Init

```bash
terraform init
```

### Apply — prerelease (auto-loaded)

```bash
terraform apply \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="owner=yourname"
```

### Apply — light or heavy profile

```bash
# Light
terraform apply \
  -var-file="light.tfvars" \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="owner=yourname"

# Heavy
terraform apply \
  -var-file="heavy.tfvars" \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="owner=yourname"
```

### Optional overrides

```bash
terraform apply \
  -var-file="light.tfvars" \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="gcp_region=us-east4" \
  -var="owner=yourname" \
  -var="devnet_name=my-devnet" \
  -var="validator_instance_count=10"
```

### Enable TX cannons

```bash
terraform apply \
  -var-file="light.tfvars" \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="owner=yourname" \
  -var="add_tx_cannons=true" \
  -var="tx_cannon_instance_count=4"
```

### Destroy

```bash
terraform destroy \
  -var-file="light.tfvars" \
  -var="gcp_project=YOUR_PROJECT_ID" \
  -var="owner=yourname"
```

---

## Outputs

| Output | Description |
|---|---|
| `snarkos_lb_ip` | External IP of the TCP load balancer (port 3030) |
| `validator_ips` | List of external IPs for all validator instances |
| `snarkos_network` | Network name (`testnet`) |
| `devnet_name` | The devnet name used |

---

## Architecture

```
GCP Project
├── google_compute_firewall (4 rules via module "sg")
│   ├── allow-ssh (22)
│   ├── allow-https (443)
│   ├── allow-snarkos (3030, 4130, 4130-4230, 5000, 5601, 9000-9256)
│   └── allow-egress (all)
│
├── google_service_account  snarkos-sa
│   └── IAM bindings: storage.objectViewer + objectCreator
│       on: release_bucket, snarkos-compiler-cache, provable-pregenerated-transactions
│
├── google_compute_instance  snarkos_validator × N
├── google_compute_instance  snarkos_client × M
├── google_compute_instance  snarkos_prover × P
├── google_compute_instance  prometheus_server
├── google_compute_instance  tx_runner
│
├── google_compute_target_pool  (validators)
├── google_compute_http_health_check  (/testnet/block/height/latest:3030)
├── google_compute_forwarding_rule  (port 3030 → target pool)
│
└── module "tx-cannon" (optional, add_tx_cannons=true)
    ├── google_service_account  txcannon-sa
    │   └── IAM: storage.objectViewer on provable-binaries-releases only
    └── google_compute_instance  tx_cannon_node × tx_cannon_instance_count
```

Instances spread across available zones in `var.gcp_region` via round-robin (`count.index % length(zones)`).

---

## GCS bucket note

`var.release_bucket` (default `provable-binaries-releases`) and `snarkos-compiler-cache`, `provable-pregenerated-transactions` must exist as GCS buckets. If migrating from AWS S3, recreate them in GCS before applying.

---

## Admin Configuration

Admin users can be configured with read-only compute, logging, and monitoring access:

```hcl
admin_users = [
  "group:gcp-engineering-viewer@provable.com",  # Default engineering group
  "user:admin@company.com",                     # Individual user
  "admin2@company.com"                          # User without prefix
]
```

### Admin Permissions

Admin users receive the following IAM roles:

| Role | Permissions | Purpose |
|------|-------------|---------|
| `roles/compute.viewer` | Read-only compute access, includes `compute.zones.list` | View instances, networks, zones |
| `roles/logging.viewer` | View logs and log configuration | Debug and troubleshoot |
| `roles/monitoring.viewer` | View metrics, dashboards, alerts | Monitor system health |
| `roles/compute.osLogin` | SSH access to instances | Direct instance access |

### Configuration Examples

**Minimal (default)**:
```hcl
admin_users = ["group:gcp-engineering-viewer@provable.com"]
```

**Multiple admins**:
```hcl
admin_users = [
  "group:gcp-engineering-viewer@provable.com",
  "user:admin1@company.com",
  "user:admin2@company.com"
]
```

**Per-environment**:
- `light.tfvars`: Development team access
- `heavy.tfvars`: Full operations team access

### Email Format

Supports both explicit prefixes and auto-detection:
- `user:email@domain.com` - Individual user
- `group:email@domain.com` - Google Group
- `email@domain.com` - Auto-detected as individual user

### Security Notes

- All roles are read-only except `compute.osLogin` (SSH access)
- No create/modify/delete permissions on compute resources
- Project-wide access scope (cannot restrict to specific instances)
- Users must exist in Google Cloud Identity/Workspace
