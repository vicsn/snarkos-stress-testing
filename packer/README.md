# Packer — Base Image Builder

Builds pre-configured machine images with all dependencies for stress-test instances.

## Template

| Template | Cloud | Arch | Builder Instance | Source Image | Output |
|----------|-------|------|-----------------|--------------|--------|
| `stress-test-base.pkr.hcl` | GCP | x86_64 | `c3d-standard-8` | Ubuntu 22.04 (`ubuntu-os-cloud`) | Image family `stress-test-base` |

## What Gets Installed (`playbooks/dependencies.yml`)

The Ansible provisioner playbook installs all runtime dependencies onto the base image.
Roles are shared from `test_suites/snarkos-p2p-tests/playbooks/roles/` via `ansible.cfg`.

| Category | Components |
|----------|-----------|
| **GitHub** | GitHub CLI (`gh`) |
| **Docker** | docker.io, Docker Compose v2.24.6 |
| **Monitoring** | Node Exporter, Process Exporter (Docker containers via shared roles) |
| **Logging/Metrics** | Google Cloud Ops Agent — binary + default `config.yaml` baked in; Ansible role `google_ops_agent_setup` re-renders with runtime `commit_id`/`branch_name`/`test_suite` labels at setup time (logs → Cloud Logging, metrics → Cloud Monitoring) |
| **Cloud CLI** | Google Cloud CLI (`gcloud`) |
| **Python** | python3, pip3 |
| **Build tools** | libclang-dev |
| **Utilities** | zip, unzip |
| **Cleanup** | Purge `unattended-upgrades` (blocks apt) |

> The default ops-agent config baked into the image lives at `packer/playbooks/files/ops_agent_config.yaml`.
> Keep it in sync with `test_suites/snarkos-p2p-tests/playbooks/roles/google_ops_agent_setup/templates/config.yaml.j2` — the Ansible role re-renders the same pipeline structure with runtime labels at setup time.

> **Note:** snarkOS itself is **not** baked into the image. The binary is compiled separately
> (ephemeral builder or local build), cached in GCS (`provable-binaries-releases`), and
> distributed to nodes at runtime by `setup.yml` → `snarkos_install_s3` role.

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) — `brew install hashicorp/tap/packer`
- GCP: `gcloud auth application-default login`

## Building the GCP Image

```bash
cd packer

# Install plugins
packer init stress-test-base.pkr.hcl

# Build (must specify network — no default VPC in the project)
packer build \
  -var 'network=<your-vpc-name>' \
  -var 'subnetwork=<your-subnet-name>' \
  stress-test-base.pkr.hcl
```

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `gcp_project` | `protocol-development-sandbox` | GCP project for the image |
| `gcp_zone` | `us-central1-b` | Zone for the builder instance |
| `machine_type` | `c3d-standard-8` | Builder instance type |
| `image_family` | `stress-test-base` | Output image family name |
| `network` | *(empty)* | VPC network for the builder — **required** (no default VPC) |
| `subnetwork` | *(empty)* | Subnet for the builder — **required** |

### Example

The VPC is owned by the Stress Testing Manager and is prefixed with the current STM workspace: `<workspace>-stress-testing-manager-vpc`. For the default workspace:

```bash
packer build \
  -var 'network=default-stress-testing-manager-vpc' \
  -var 'subnetwork=protocol-development-sandbox-subnet-us-central1' \
  stress-test-base.pkr.hcl
```

To discover the current VPC name (useful when running against a non-default STM workspace):

```bash
(cd ../stress-testing-manager/infrastructure && ./tf_stack.sh output | grep vpc_name)
```

Build takes ~10 minutes. Output: image in family `stress-test-base` in project `protocol-development-sandbox`.

## Using the Custom Image in Terraform

By default, the `snarkos-p2p-tests` Terraform uses stock Ubuntu 22.04. To use the Packer-built image:

```bash
cd test_suites/snarkos-p2p-tests/terraform

# Use Packer-built image
terraform apply \
  -var 'image_family=stress-test-base' \
  -var 'image_project=protocol-development-sandbox' \
  ...

# Or revert to stock Ubuntu (default)
terraform apply \
  -var 'image_family=ubuntu-2204-lts' \
  -var 'image_project=ubuntu-os-cloud' \
  ...
```

### Trade-offs

| Approach | Provision Time | Image Maintenance | Dependencies |
|----------|---------------|-------------------|-------------|
| **Stock Ubuntu** (default) | ~5 min longer (installs at runtime via `setup.yml`) | None | Always latest packages |
| **Packer image** | Fast (pre-baked) | Rebuild periodically | Packages frozen at build time |

## Ansible Roles

Shared from `test_suites/snarkos-p2p-tests/playbooks/roles/` via `ansible.cfg`:

```
roles_path = ../common/roles/:../test_suites/snarkos-p2p-tests/playbooks/roles/
```

Roles used: `process_exporter_setup`, `node_exporter_setup`.
