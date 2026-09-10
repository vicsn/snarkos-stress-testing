# High-Level Deployment Patterns

## Overview

### NOTE: this document may be outdated since deprecation of Talisker

snarkos-stress-testing is a sophisticated four-layer stress testing framework for SnarkOS (Aleo blockchain). It automates infrastructure provisioning, node configuration, test execution, and log analysis across multiple cloud providers.

---

## 1. Two-Tier Cloud Strategy

| Purpose | Cloud | Primary Suite | Node Types |
|---|---|---|---|
| **P2P network** | GCP | `snarkos-p2p-tests` | Validators, Clients, Provers, TX Runner |
| **CDN / ledger / sync** | AWS | `snarkos-cdn-tests` | Single machine: load ledger or sync |

Each cloud is independently managed but follows identical deployment patterns.

---

## 2. Three-Phase Deployment Flow

```
┌──────────────────────────────────────────────┐
│ PROVISION (Terraform)                        │
│ • Create compute instances                   │
│ • Configure firewall rules                   │
│ • Set up load balancers, IAM, networking    │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ CONFIGURE (Ansible)                          │
│ • Install SnarkOS binaries                   │
│ • Start systemd services                     │
│ • Configure monitoring & logging             │
│ • Set up SSH keys, peers                     │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ EXECUTE (Test Suite)                         │
│ • Run named test (swap_ledgers, etc.)        │
│ • Collect metrics & logs                     │
│ • Validate results                           │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ ANALYZE (Log Analysis Scripts)               │
│ • Parse sync speeds, consensus timing        │
│ • Generate flamegraphs, performance charts   │
│ • Archive to S3 & Grafana Cloud              │
└──────────────────────────────────────────────┘
```

Each phase is **modular and re-runnable**:
- Provision without running tests
- Configure without re-provisioning  
- Re-run tests on existing infrastructure
- Collect/re-analyze logs

---

## 3. Infrastructure-as-Code Stacking

```
┌─────────────────────────────────────────────────┐
│ Layer 1: Packer (Base Image)                    │
│ • Builds Ubuntu 22.04 + Docker + tools          │
│ • Stores as GCP/AWS machine images              │
└──────────────┬──────────────────────────────────┘
               │ (builds)
               ▼
┌─────────────────────────────────────────────────┐
│ Layer 2: Terraform (Cloud Resources)            │
│ • Provisions compute instances                  │
│ • Configures firewall, load balancers, IAM     │
│ • Outputs: instance IPs, service endpoints      │
└──────────────┬──────────────────────────────────┘
               │ (outputs: inventory)
               ▼
┌─────────────────────────────────────────────────┐
│ Layer 3: Ansible (Configuration Management)     │
│ • Installs SnarkOS binaries                     │
│ • Configures systemd, peers, monitoring         │
│ • Deploys test harness, scripts                 │
└──────────────┬──────────────────────────────────┘
               │ (configures)
               ▼
┌─────────────────────────────────────────────────┐
│ Layer 4: Test Suite Scripts (Orchestration)     │
│ • run_test_suite.sh (GCP master orchestrator)   │
│ • run_*.sh (AWS test runners)                   │
│ • Dispatch named tests, collect results         │
└─────────────────────────────────────────────────┘
```

**Key benefit:** Each layer is independent yet composable. Packer builds once, both clouds reuse. Terraform can be torn down + re-provisioned without rebuilding images. Ansible is idempotent — safe to re-run.

---

## 4. Naming & Tagging Convention

All resources follow a consistent naming pattern:

```
${owner}-${devnet_name}-<role>
```

**Applied consistently across:**
- GCP instance names: `mike-testnet-v123-validator-0`
- AWS instance names
- Terraform labels: `role`, `owner`, `devnet`
- Ansible host groups: `snarkos_validator`, `snarkos_client`, etc.
- Firewall rule tags: `validator`, `client`, `prover`
- S3 bucket prefixes: logs/`${owner}/${devnet_name}/`
- Slack notification threads

**Example:**
```
owner=mike, devnet=testnet-v123, role=validator
↓
GCP instance name: mike-testnet-v123-validator-0
Terraform labels: {role: validator, owner: mike, devnet: testnet-v123}
Ansible group: snarkos_validator
Firewall tag: validator
```

---

## 5. Dynamic Inventory Pattern

```
Terraform
  └─ Outputs compute instance details
       └─ IP, labels, tags, roles
              │
              ▼
    Ansible Dynamic Inventory
      └─ Parses Terraform labels + Ansible tags
           └─ Auto-populates host groups
                  │
                  ▼
    Ansible Playbooks
      └─ Target groups, not individual hosts
           └─ snarkos_validator, snarkos_client, etc.
```

**Benefit:** Playbooks are **scale-agnostic** — same `setup.yml` configures 3 validators or 300. Groups are populated dynamically from cloud resource labels.

---

## 6. Test Suite Abstraction

```
run_test_suite.sh (master orchestrator)
│
├─ Interactive Mode
│  ├─ Prompt for tfvars profile (light, heavy, prerelease)
│  ├─ Prompt for test name (swap_ledgers, unbond_bond_validators, etc.)
│  └─ Confirm + execute
│
└─ Headless Mode
   └─ ./run_test_suite.sh --test <name> --tfvars <profile>
       └─ Auto-provision, configure, run, archive logs

Each test is modular:
  tests/<test-name>/
  ├─ run_test.yml              (Ansible playbook)
  ├─ pre-test.sh (optional)    (setup before test)
  └─ post-test.sh (optional)   (validation/cleanup after)
```

**Adding a new test:** Drop a YAML playbook + optional hooks into `tests/<name>/` — no changes to orchestrator needed.

---

## 7. Variable & Configuration Precedence

Configuration flows through multiple layers, each overriding the previous:

```
┌─ tfvars profiles (light.tfvars, heavy.tfvars, prerelease.tfvars)
│  └─ Count/type of instances, GCP project, regions
│
└─▶ Terraform variables.tf (defaults)
   └─ Fallback values for unspecified vars
   
   └─▶ Ansible vars.yml (generated by STM)
      └─ Generated from ansible_vars.yml.j2 template
      └─ SnarkOS version, test parameters, monitoring config
      
      └─▶ Playbook-level vars + host_vars
         └─ Per-host customization, environment overrides
```

**Example precedence:**
```
light.tfvars specifies: validator_instance_count=3
  ↓
Terraform provisions: 3 validators
  ↓
vars.yml specifies: snarkos_version=0.13.5
  ↓
Ansible configures: all validators to run 0.13.5
  ↓
host_vars/validator-0.yml specifies: extra_flags="--log-level debug"
  ↓
Only validator-0 runs with debug logging
```

---

## 8. Firewall & Network Security Pattern

```
┌─ module "fwrule" (centralized firewall config)
│  └─ Manages ALL firewall rules:
│     ├─ SSH (port 22)
│     ├─ HTTPS (port 443)
│     ├─ SnarkOS ports (3030, 4130, 4130-4230, 9090, 9100)
│     └─ Ingress/egress policies
│  └─ Outputs: network_tag (e.g., "snarkos-firewall")
│
└─▶ Applied to instances via network_tags:
   └─ validator instances: [module.fwrule.network_tag, "validator"]
   └─ client instances: [module.fwrule.network_tag, "client"]
   └─ prover instances: [module.fwrule.network_tag, "prover"]
```

**Key property:** Single source of truth. All firewall rules centralized in one module. Instance roles use consistent tags.

**Role-based access:**
- `validator` → accept inbound SnarkOS consensus (3030, 4130)
- `client` → accept inbound from validators
- `prover` → query port (9090), metrics port (9100)
- `prometheus` → scrape metrics (9100 across all nodes)

---

## 9. Log Collection & S3 Archival

```
During Test Execution:
┌──────────────────────────────┐
│ snarkOS nodes                │
│ (validator, client, prover)  │
└────────┬─────────────────────┘
         │ (systemd logs)
         ▼
┌──────────────────────────────┐
│ Filebeat / Grafana Agent     │
│ (on each node)               │
└────────┬─────────────────────┘
         │ (stream)
         ▼
┌──────────────────────────────────────────┐
│ Grafana Cloud / Elasticsearch Stack      │
│ (real-time monitoring)                   │
└──────────────────────────────────────────┘

After Test Completion:
┌──────────────────────────────┐
│ All nodes (via Ansible)      │
└────────┬─────────────────────┘
         │ fetch_and_zip_snarkos_logs.yml
         ▼
┌──────────────────────────────┐
│ Collect + zip logs           │
└────────┬─────────────────────┘
         │ (upload)
         ▼
┌──────────────────────────────────────────┐
│ S3: provable-logs-results                │
│ Path: logs/${owner}/${devnet}/${run_id}   │
└──────────────────────────────────────────┘
         │ (permanent archive)
         ▼
┌──────────────────────────────────────────┐
│ Log Analysis Scripts (Python/Rust)       │
│ • Parse sync speeds                      │
│ • Plot consensus timing                  │
│ • Generate flamegraphs                   │
│ • Upload results to S3 + Grafana         │
└──────────────────────────────────────────┘
```

**Result:** Ephemeral compute destroyed, logs retained forever in S3.

---

## 10. Automation Daemon (Talisker)

The Stress Testing Manager (STM) runs a Talisker daemon for hands-off automation:

```
Talisker Daemon (STM EC2, t3a.large)
│
├─ Poll GitHub for new SnarkOS releases
│  └─ Watches tags (v0.13.5) and branches (main)
│
├─ Trigger test suites via JSON-RPC (:3030)
│  └─ POST to localhost:3030/test with suite name
│
├─ Provision infrastructure (Terraform)
├─ Configure nodes (Ansible)
├─ Execute tests (test suite runner)
└─ Collect + archive logs (S3)
     │
     └─▶ Notify Slack on completion
```

**Control interface:**
```bash
scripts/talisker_control.sh status           # Check daemon
scripts/talisker_control.sh trigger --branch main
scripts/talisker_control.sh stop
```

---

## 11. Shared S3 Buckets

| Bucket | Purpose | Typical Contents |
|---|---|---|
| `provable-binaries-releases` | SnarkOS binaries built by Talisker | `aleo-testnet-v0.13.5` binary, release notes |
| `provable-logs-results` | Test logs, results, analysis reports | `logs/mike/testnet-v123/2024-06-16T12-34-56/` |
| `aleo-snapshots` | Ledger checkpoints for sync tests | `testnet/ledger_block_123456.zip` |
| `snarkos-compiler-cache` | sccache build cache (S3-backed) | Compiled objects, incremental cache |
| `ephnet-terraform-state-bucket-eq` | Terraform remote state (AWS backend) | `.tfstate` files for infrastructure state |

---

## 12. Base Image (Packer)

Built once, reused across all test runs:

```
packer/stress-test-base.json.pkr.hcl (x86_64)
packer/stress-test-base-arm.json.pkr.hcl (ARM64)
  │
  └─ Run Ansible provisioner: dependencies.yml
      └─ Install:
         ├─ Docker + Docker Compose
         ├─ Logstash, Filebeat, Metricbeat
         ├─ Grafana Agent
         ├─ Prometheus Node Exporter + Process Exporter
         ├─ Python 3.12+, boto3
         └─ sccache (S3-backed compiler cache)
  │
  └─ Export as GCP machine image
  └─ Export as AWS AMI
```

**Result:** Both clouds use identical software stack. New SnarkOS releases compiled once into binary, distributed via S3.

---

## Key Patterns Summary

| Pattern | Benefit |
|---|---|
| **Cloud-agnostic IaC** | Same Ansible playbooks work on GCP and AWS |
| **Modular provisioning** | Tear down + re-provision in minutes without rebuilding base images |
| **Dynamic inventory** | Scale to 10x nodes without touching playbooks |
| **Pluggable tests** | Add new tests without modifying orchestrator |
| **Variable precedence** | Global defaults → cloud-specific profiles → host customizations |
| **Centralized firewall** | Single module manages all network rules across roles |
| **S3 as permanent record** | Ephemeral compute, eternal logs |
| **Hands-off automation** | Talisker daemon triggers full pipeline on GitHub release |

---

## Technology Stack

| Layer | Tools |
|---|---|
| **IaC** | Terraform (GCP ≥7.32.0, AWS) |
| **Config Mgmt** | Ansible (amazon.aws, ansible.posix, community.general) |
| **Image Build** | HashiCorp Packer (amazon-ebs, Ansible provisioner) |
| **Cloud — GCP** | Compute Engine, Cloud LB, Firewall, IAM, OS Login |
| **Cloud — AWS** | EC2, ELB, S3, IAM, CloudWatch Logs |
| **Monitoring** | Grafana Cloud, Prometheus, Node/Process Exporter, Elastic Stack |
| **Languages** | Bash, Python 3.12+, Rust (2021 edition) |
| **Blockchain** | SnarkOS (Aleo node), snarkVM, tx-cannon (Docker/ECR) |
| **CI/Lint** | GitHub Actions, ansible-lint, shellcheck, pre-commit |

---

## Next Steps

See related documentation:
- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — detailed infrastructure breakdown
- [`COMMON_WORKFLOWS.md`](./COMMON_WORKFLOWS.md) — step-by-step operational procedures
- [`TEST_SUITES.md`](./TEST_SUITES.md) — test suite structure and capabilities
