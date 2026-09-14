# snarkos-p2p-tests

Orchestrates the full stress test lifecycle: provision GCP infra, build snarkOS binary, configure nodes, run tests, collect logs, destroy.

## Architecture

The test suite uses a **decomposed script architecture** under `scripts/`:

```
scripts/
├── full_run.sh           # Master orchestrator — composes all steps
├── bin/                  # Pipeline entrypoints (one pueue job each)
│   ├── provision.sh      # Terraform apply
│   ├── setup.sh          # Build binary + Ansible setup
│   ├── run-test.sh       # Run one test + collect logs
│   ├── run-utility.sh    # Run one utility
│   ├── collect-logs.sh   # Standalone log download + GCS upload
│   ├── destroy.sh        # Terraform destroy
│   └── fetch-job-log.sh  # Save one pueue task's output to a temp file
└── lib/                  # Shared libraries + supporting scripts
    ├── common.sh         # Paths, helpers, Ansible wrappers, terraform
    ├── notify.sh         # Slack notifications (best-effort)
    ├── stm.sh            # Delegation to the manager; also runnable directly
    ├── pueue.sh          # pueue job queue dispatch
    ├── slack_config.sh   # Load Slack creds from vars.yml / profile
    ├── select-test.sh    # Interactive test menu
    └── unlock-state.sh   # Release a stale terraform state lock
```

`bin/` holds the phases a run is made of; `lib/` holds the shared code plus the
standalone helpers that are not part of a run.

Every entrypoint that runs a phase — `full_run.sh` and each `bin/*.sh` except
`fetch-job-log.sh` — shares the same preamble: parse args, **delegate to the
stress-testing-manager** (`lib/stm.sh`), then **enqueue in pueue**
(`lib/pueue.sh`), then do the work. So a command typed on your laptop is the
same command that runs on the manager; the only difference is where it executes.

Delegation resolves the manager from `stress-testing-manager-ip.txt` at the repo
root and runs the identical command over SSH. It is skipped when already on the
manager (GCE metadata `role=stress-testing-manager`) or when `STM_LOCAL=1` is
set. Ansible targets private IPs, so a laptop run needs `STM_LOCAL=1` **and**
VPC access — delegation is the normal path.

Jobs run via **pueue** by default (parallel pipeline with dependency DAG). Set `PUEUE_DISABLED=1` to run sequentially in the current shell — that also makes a delegated command block until the remote job finishes.

---

## Usage

### Full Pipeline (recommended)

```bash
# Provision + setup + run tests + destroy (all via pueue)
scripts/full_run.sh --mode=light --tests=swap_ledgers

# Run all tests
scripts/full_run.sh --mode=heavy --tests=all

# Run prerelease tests only
scripts/full_run.sh --mode=prerelease --tests=prerelease

# Run multiple tests
scripts/full_run.sh --mode=light --tests=swap_ledgers,unbond_validators

# Custom vars file
scripts/full_run.sh --mode=light --vars=vars --tests=prerelease

# Include a utility
scripts/full_run.sh --mode=light --tests=none --utility=pregenerate_transactions \
  --execution-tx-count=40 --deployment-tx-count=20 --num-validators=5

# Load pregenerated transactions
scripts/full_run.sh --mode=light --tests=load_saved_transactions \
  --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions

# Run sequentially (no pueue)
PUEUE_DISABLED=1 scripts/full_run.sh --mode=light --tests=swap_ledgers

# Force local execution (skip SSH delegation)
STM_LOCAL=1 scripts/full_run.sh --mode=light --tests=swap_ledgers
```

### `full_run.sh` Options

| Option | Description |
|---|---|
| `--mode=MODE` | Provision mode: `light`, `heavy`, or `prerelease` |
| `--vars=NAME` | Ansible vars file basename without extension (default: `vars`) |
| `--tests=SPEC` | Test(s) to run: `<name>`, `a,b,c`, `all`, or `prerelease` |
| `--utility=NAME` | Run a utility after tests |
| `--execution-tx-count=N` | Required for `pregenerate_transactions` and `load_saved_transactions` |
| `--deployment-tx-count=N` | Required for `pregenerate_transactions` and `load_saved_transactions` |
| `--num-validators=N` | Required for `pregenerate_transactions` (5 or 40). `load_saved_transactions` infers this from live validator IPs |
| `--tx-type=TYPE` | Required for `load_saved_transactions`: `executions`, `deployments`, or `all` |

### Individual Entrypoints

Each phase script under `scripts/bin/` handles one step. Invoke them exactly as you
would `full_run.sh` — from your laptop, from the repo root of your checkout —
and each one delegates itself to the manager. When pueue is enabled there, the
job is **enqueued** and the call returns immediately; add `PUEUE_DISABLED=1` to
block until it finishes.

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)

# Provision infrastructure
scripts/bin/provision.sh --mode=light

# Build binary + run Ansible setup
scripts/bin/setup.sh --vars=vars

# Run a single test (collects logs by default)
scripts/bin/run-test.sh --test=swap_ledgers
scripts/bin/run-test.sh --test=swap_ledgers --no-collect
scripts/bin/run-test.sh --test=load_saved_transactions \
  --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions

# Run a utility
scripts/bin/run-utility.sh --utility=pregenerate_transactions \
  --execution-tx-count=40 --deployment-tx-count=20 --num-validators=5

# Collect logs standalone
scripts/bin/collect-logs.sh --label=my_run

# Destroy infrastructure
scripts/bin/destroy.sh

# Interactive test selection menu (menu is local; each test delegates)
scripts/lib/select-test.sh
```

All entrypoints accept `--vars=NAME` to override the Ansible vars file.

This is how you keep one devnet alive across several runs of the same test:
`provision.sh` once, `setup.sh` once, then `run-test.sh` as often as you like,
and `destroy.sh` when you are done. (`full_run.sh` always destroys at the end,
so it is the wrong tool for that.)

### Inspecting a run

`scripts/lib/stm.sh` — the delegation library, also runnable on its own — takes
one command to the manager, or opens a shell there. Use it to inspect a run,
never to start one:

```bash
scripts/lib/stm.sh pueue status
scripts/lib/stm.sh systemctl status pueued
scripts/lib/stm.sh                  # interactive shell, cwd = this suite
```

A finished job's output is usually too long to read in the terminal, so
`fetch-job-log.sh` saves it to a temp file and prints the path (task ids come
from `pueue status`, and each enqueue echoes its own):

```bash
scripts/bin/fetch-job-log.sh --job=7          # prints e.g. /tmp/pueue-job-7-….log
less "$(scripts/bin/fetch-job-log.sh --job=7)"
```

### Stuck state lock

A run killed mid-apply (dropped SSH, cancelled job) leaves the GCS backend
locked, and the next provision fails with `Error acquiring the state lock`.
`scripts/lib/unlock-state.sh` releases it:

```bash
scripts/lib/unlock-state.sh         # inspect the holder, confirm, unlock
scripts/lib/unlock-state.sh --force # no prompt (non-interactive)
```

Do not run `terraform force-unlock` by hand with the `ID:` from the error — the
GCS backend wants the lock object's **generation number**, so the UUID fails
with `Lock ID should be numerical value`. The script looks the generation up,
prints who has held the lock and for how long, and refuses while a terraform
process is still alive. Like every other entrypoint it delegates to the
manager; `STM_LOCAL=1` runs it on your machine when SSH is down.

---

## Execution Flow

### `full_run.sh` Pipeline

```
1. Parse --mode, --vars, --tests, --utility
2. Delegate to the manager over SSH (unless already there / STM_LOCAL=1)
3. Discover tests from tests/*/
4. Send Slack banner notification
5. Enqueue pipeline via pueue:
   provision:$MODE
     └─> setup
           └─> run-test:test1, run-test:test2, ... (parallel)
                 └─> destroy
```

Steps 3-5 always happen on the manager. Each phase script follows the same
shape: parse args → delegate → enqueue → work.

### `provision.sh`
1. Select `.tfvars` profile based on `--mode`
2. `terraform init` + `terraform apply -auto-approve -var-file={mode}.tfvars`
3. Write LB URL to `lb_url.txt`
4. Wait for GCP label propagation (inventory discovery)
5. Run `ips.yml` playbook to record node IPs

### `setup.sh`
1. Check if snarkOS binary exists in GCS (`gs://provable-binaries-releases/<hash>[_<features>]`)
2. If missing: spin up ephemeral GCE builder (`terraform apply -target=google_compute_instance.snarkos_builder`), run `build_binary.yml`, destroy builder
3. Run `setup.yml` playbook (distribute binary via `gcloud storage cp`, configure systemd, keys, Ops Agent)

### `run-test.sh`
1. Run `pre-test.sh` hook (if exists)
2. Set network vars from terraform state
3. Run `run_test.yml` Ansible playbook with `test_name=$SELECTED`
4. Run `check.sh` hook (if exists, receives `$NETWORK`)
5. Run `post-test.sh` hook (if exists)
6. Download + upload logs to GCS

On failure at any step, the EXIT trap collects logs automatically.

---

## Provision Modes

Each mode uses a corresponding `.tfvars` profile:

| Mode | Shortcut | Tfvars file | Validators | Clients | Provers |
|---|---|---|---|---|---|
| `light` | `l` | `light.tfvars` | 5 | 0 | 1 |
| `heavy` | `h` | `heavy.tfvars` | 40 | 0 | 0 |
| `prerelease` | `pr` | `prerelease.tfvars` | 40 | 0 | 1 |

`default.auto.tfvars` is always loaded automatically by Terraform (sets project, region, owner, network config).

---

## Test Selection

`--tests` accepts:

| Value | Behaviour |
|---|---|
| `<name>` | Single named test from `tests/` |
| `a,b,c` | Comma-separated list |
| `all` | All tests in `tests/` alphabetically; skips dirs prefixed with `_` |
| `prerelease` | Only tests prefixed `prerelease_` |

### Available Tests

| Test | Description |
|---|---|
| `load_saved_transactions` | Submit pre-generated transactions (Rust tx_submitter). Requires `--execution-tx-count`, `--deployment-tx-count`, `--tx-type`. Validator count is inferred from live IPs. |
| `malicious_certificates` | Malicious certificate injection (has check.sh) |
| `malicious_flood` | Flood attack simulation (has check.sh) |
| `malicious_peer_response` | Malicious peer response handling |
| `malicious_resend_confirmed` | Resend confirmed transactions (has check.sh) |
| `malicious_round_attack` | Round-based attack simulation |
| `prerelease_1_halt_byzantine_majority` | Halt with byzantine majority (has restart.yml) |
| `prerelease_2_reset_client_ledgers` | Reset client ledgers mid-run |
| `prerelease_3_reset_validator_ledgers` | Reset validator ledgers mid-run |
| `swap_ledgers` | Hot-swap ledger snapshots (has swap.yml) |
| `unbond_validators` | Unbond validators from consensus |

Test directories live in `tests/<name>/`. Each may provide:
- `pre-test.sh` — runs before the Ansible playbook
- `run_test.yml` — main test playbook (required)
- `check.sh` — runs after the playbook; receives `$NETWORK` as argument
- `post-test.sh` — runs after check

Tests are **auto-discovered** by scanning `tests/*/` directories. No registration needed.

---

## Utilities

`--utility` accepts any directory name under `utils/`.

### Available Utilities

| Utility | Description |
|---|---|
| `analyze_logs` | Python log analysis (generates landing stats) |
| `check_network_is_advancing` | Verify block height is progressing |
| `download_flamegraph` | Download perf flamegraph SVG |
| `download_logs_clients` | Download logs from client nodes |
| `download_logs_provers` | Download logs from prover nodes |
| `download_logs_tx_runner` | Download logs from TX runner |
| `download_logs_validators` | Download logs from validator nodes |
| `download_prometheus_snapshot` | Download Prometheus data snapshot |
| `pregenerate_transactions` | Pre-generate TX batches (deployment + execution). Requires `--execution-tx-count`, `--deployment-tx-count`, `--num-validators`. |
| `reset_all` | Reset all nodes (stop + wipe state) |
| `reset_clients` | Reset client nodes only |
| `stop_all` | Stop all snarkOS services |

Utility directories may provide:
- `pre-utility.sh` — runs before the Ansible playbook
- `run_utility.yml` — main utility playbook (required)
- `check.sh` — runs after the playbook
- `post-utility.sh` — runs after check

Special utility names:
| Name | Behaviour |
|---|---|
| `upload_logs_to_gcs` | Downloads logs from all nodes then uploads to GCS |
| `download_*` | Creates `log_files/` directory for output |

Utilities are **auto-discovered** by scanning `utils/*/` directories.

---

## Prerequisites

- `terraform` >= 1.10
- `ansible` with `google.cloud` collection (`ansible-galaxy collection install google.cloud`)
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- `pueue` installed and daemon running (`pueued -d` or `PUEUE_DISABLED=1`)
- GCP project access: `protocol-development-sandbox`
- Ansible vars file at `playbooks/vars.yml` (copy from `playbooks/vars.example.yml`)
- SSH key at `../../devnet-key` (auto-created by `scripts/ensure_devnet_key.sh`)

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `OWNER` | `$USER` | Scopes Ansible inventory + Terraform resources to your instances |
| `DEVNET_NAME` | `snarkos-p2p-tests` | Devnet name for resource naming + Ansible targeting |
| `RUN_ID` | `YYYYMMDDTHHMMSSZ` | Unique run identifier (auto-generated, shared across pipeline) |
| `RESULTS_AND_LOGS_BUCKET` | `provable-logs-results` | GCS bucket for log uploads |
| `RELEASE_BUCKET` | `provable-binaries-releases` | GCS bucket for snarkOS binaries |
| `VARS` | `vars` | Ansible vars file basename |
| `PUEUE_DISABLED` | _(unset)_ | Set to `1` to run jobs inline (no pueue) |
| `STM_LOCAL` | _(unset)_ | Set to `1` to skip SSH delegation and run here instead |
| `RUNNER_MANAGES_LOGS` | _(unset)_ | Set to `1` to skip automatic log collection |
| `SLACK_TOKEN` | _(unset)_ | Slack bot token for notifications |
| `SLACK_CHANNEL_ID` | _(unset)_ | Slack channel for notifications |
| `NOTIFY_SLACK_DISABLED` | _(unset)_ | Set to `1` to disable Slack notifications |

---

## Log Collection

Logs upload to:
```
s3://provable-logs-results/manual_test_runs/<user>/<RUN_ID>/<test_name>/
```

Log collection runs automatically:
- After each test (unless `--no-collect`)
- On any error exit (EXIT trap)

Downloads logs from: validators, clients, provers, tx_runner.
Runs `analyze_logs` utility for landing stats.

Manual trigger: `scripts/bin/collect-logs.sh --label=my_label`

---

## Slack Notifications

When `SLACK_TOKEN` and `SLACK_CHANNEL_ID` are set:
- Run banner on pipeline start
- Thread per job: begin/end status with exit code
- Color-coded: green for success, red for failure

Slack credentials load from (in priority order):
1. Environment variables
2. `~/.config/snarkos-stress-testing/slack_env.sh` (manager profile)
3. `stress-testing-manager/infrastructure/vars.yml`

---

## Infrastructure Teardown

```bash
# Via pipeline (enqueued after tests)
scripts/bin/destroy.sh

# Or via full_run.sh (automatic at end of pipeline)
```

Delegates to `destroy_infra.sh`. Always runs after testing to avoid ongoing GCP costs.
