# Refactor scaffold

Splits the monolithic `run_test_suite.sh` into a sourced library + one
executable per phase, so each phase can be enqueued independently (e.g. pueue).

Lives under `single-region-tests/scripts/`; the project root one level above it
(`single-region-tests/`) holds `terraform/`, `playbooks/`, `inventory/`,
`tests/`, `utils/`, and `destroy_infra.sh`.

```
single-region-tests/
├── terraform/  playbooks/  inventory/  tests/  utils/   # project resources
├── destroy_infra.sh                                     # sourced by bin/destroy.sh
└── scripts/
    ├── notify_slack.sh     # the Slack notifier (../../scripts from bin/)
    ├── full_run.sh         # compose phases: sequential, or --queue into pueue
    ├── lib/
    │   ├── common.sh       # sourced by everything: env, paths, helpers, trap
    │   └── notify.sh        # best-effort Slack helpers
    └── bin/
        ├── provision.sh    # terraform apply   --mode=light|heavy|prerelease
        ├── setup.sh        # build-if-missing + ansible setup
        ├── run-test.sh     # ONE test + its log collection   --test=NAME
        ├── run-utility.sh  # ONE utility                      --utility=NAME
        ├── collect-logs.sh # standalone log pull/upload
        └── destroy.sh      # teardown
```

`common.sh` derives `SCRIPTS_DIR=<project>/scripts` and `REPO_ROOT=<project>`
from its own `BASH_SOURCE`, so the scripts work regardless of where the repo is
checked out — no hardcoded paths.

## Invariants every entrypoint upholds
- Sets its own `set -euo pipefail` and installs the EXIT trap.
- Takes all input as flags; **never prompts** in non-interactive runs (a headless job would hang).
- Re-derives shared state (network/devnet/LB) from terraform + `lb_url.txt`.
- Honours `RUN_ID` so all jobs of one run share the same S3 prefix.

## pueue usage

pueue snapshots the environment at `pueue add` time and only runs a task once
its `--after` dependencies have *succeeded*, so:

```bash
export RUN_ID=$(date -u +%Y%m%dT%H%M%SZ) # one id for the whole run
./full_run.sh --mode=heavy --tests=all --queue --group=devnet --parallel=4
pueue status --group devnet
```

`RUN_ID` determines the S3 key, and the Slack and log references.

`full_run.sh --queue` wires: `provision -> setup -> {N test jobs}`. A failed
provision cancels the chain. Set `pause_on_failure: true` in the pueue daemon
config so a failing test pauses the group instead of charging ahead.

Enqueue ad-hoc single jobs once infra is up:

```bash
RUN_ID=$RUN_ID pueue add -- ./scripts/bin/run-test.sh --test=prerelease_foo
RUN_ID=$RUN_ID pueue add -- ./scripts/bin/run-utility.sh --utility=analyze_logs
```

## Slack notifications

`lib/notify.sh` wraps `notify_slack.sh` (in the `scripts/` dir, i.e.
`../../scripts/notify_slack.sh` from `bin/`) and fires around every job. They
are **best-effort**: disabled automatically unless `SLACK_TOKEN` and a channel
are set, never fail a job, and never write to stdout (so pueue task-id capture
stays clean).

Enable by exporting `SLACK_TOKEN` and `SLACK_CHANNEL_ID` (or `CHANNEL_ID`) — they
must be **exported**, not just set, since each step runs as a child process.
Disable explicitly with `NOTIFY_SLACK_DISABLED=1`. Override the notifier path
with `NOTIFY_SLACK=/abs/path/notify_slack.sh`; otherwise it is auto-located in
`snarkos-stress-testing/scripts/`.
When the vars are set but the notifier is missing, or the Slack API returns an
error, the reason is printed to stderr (never silently swallowed).

Self-test without touching infra:

```bash
export SLACK_TOKEN=... SLACK_CHANNEL_ID=C...
NOTIFY_DEBUG=1 bash -c 'source scripts/lib/common.sh; notify_run_banner "notify self-test"'
```

`NOTIFY_DEBUG=1` prints the resolved notifier path and each decision.

Each job gets its own thread:

```
⏳ Enqueuing job: run-test:foo (run R1)     <- thread root (orchestrator, at enqueue)
  ▶️ Starting job: run-test:foo (run R1)    <- reply (the task, when it runs)
  ✅ Finished job run-test:foo with status 0 <- reply (EXIT trap, true rc)
```

The thread is held together by `SLACK_THREAD_TS`: the orchestrator opens it at
enqueue time and prefixes `SLACK_THREAD_TS=<ts> pueue add ...`; pueue snapshots
that env, so the task — running later, in another process — threads its start
and finish messages into the same thread. Run a step standalone (no
`SLACK_THREAD_TS` in env) and it simply opens its own thread.
