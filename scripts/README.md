# Aleo / Talisker Automation Scripts

This directory contains a collection of operational scripts used to manage the Aleo testing
infrastructure, snapshot ingestion pipeline, EC2 builders, ledger checkpoints, and various DevOps
automation tasks.
The scripts are written in **bash** and **Python**, and are intended to be composable, safe to run
multiple times, and resilient when interacting with AWS, snarkOS, or long-running network operations.

The scripts fall into several categories:

- **Snapshot & Ledger Operations**
  - Generating local Aleo checkpoints
  - Uploading checkpoints to S3
  - Streaming large ledger snapshots directly to S3 via multipart upload

- **Builder & Talisker Control**
  - Sending remote JSON-RPC commands to Talisker
  - Discovering EC2 builder instances dynamically

- **AWS Infrastructure Utilities**
  - Listing running EC2 instances
  - Cleaning up old S3 releases
  - Managing IAM instance profiles attached to EC2 nodes

- **Slack Integration**
  - Sending messages to configured slack channels
  - Sending messages in threads created by the script

## attach_aleo_snapshots_role.sh

Attaches the `AleoSnapshotsRole` IAM instance profile to a given EC2 instance.
The script:

### Description

1. Looks up the ARN of the `AleoSnapshotsRole` instance profile.
2. Disassociates any IAM instance profiles currently attached to the target instance.
3. Waits until the `AleoSnapshotsRole` profile is not associated with **any** instance.
4. Ensures the IAM role `AleoSnapshotsRole` is attached to the instance profile.
5. Associates the instance profile to the specified EC2 instance.
6. Attempts basic verification of credentials (metadata, STS, S3).

### Usage

```bash
./attach_aleo_snapshots_role.sh <instance-id>
```

Example:

```bash
./attach_aleo_snapshots_role.sh i-0123456789abcdef0
```

### Arguments

- `<instance-id>` – The EC2 instance ID to which the IAM instance profile should be attached.

### Environment / Configuration

These are hardcoded in the script but can be edited as needed:

- `ROLE` – IAM role name. Default: `AleoSnapshotsRole`
- `PROFILE` – IAM instance profile name. Default: `AleoSnapshotsRole`
- `REGION` – AWS region. Default: `us-west-2`

### Requirements

- AWS CLI installed and configured with sufficient permissions to:
  - Describe and modify `IamInstanceProfileAssociations`
  - Get and modify IAM instance profiles and roles
  - Associate/disassociate instance profiles from EC2 instances
- The IAM role and instance profile:
  - Role: `AleoSnapshotsRole`
  - Instance profile: `AleoSnapshotsRole`
  already exist and are correctly configured.

## checkpoint_uploader.sh

Periodically scans for Aleo checkpoint directories on disk, zips them, and uploads them to an S3 bucket.  
To be used on a machine that is creating periodical checkpoints.

### Description

1. Searches for directories named `checkpoint_<network>_*` under a base directory.
2. Sorts them by height/suffix and treats the highest one as the "latest".
3. Uploads all non-latest checkpoints unconditionally.
4. Uploads the latest checkpoint **only if it appears complete** (has `CURRENT` and at least one `MANIFEST-*`).
5. Keeps a local state file to avoid re-uploading the same checkpoints.
6. Repeats the scan every hour.

Supported networks (hardcoded): `canary`, `testnet`, `mainnet`.

### Usage

```bash
./checkpoint_uploader.sh [bucket] [base_dir]
```

Examples:

```bash
# Use defaults: bucket=aleo-snapshots, base_dir=/tmp
./checkpoint_uploader.sh

# Custom bucket and base directory
./checkpoint_uploader.sh my-checkpoint-bucket /var/aleo/checkpoints
```

### Arguments

- `bucket` (optional)  
  S3 bucket name to upload archives to.  
  **Default:** `aleo-snapshots`

- `base_dir` (optional)  
  Base directory under which checkpoint directories are located.  
  **Default:** `/tmp`

### Requirements

- `aws` CLI installed and configured with credentials that can (if on EC2 instance - its profile has to have these capabilities):
  - `s3api head-object`
  - `s3 cp` to the target bucket
- `zip` installed.
- Script is intended to run on a host that periodically produces checkpoint directories, e.g.:

  ```text
  /tmp/checkpoint_canary_12345
  /tmp/checkpoint_canary_67890
  /tmp/checkpoint_testnet_start
  /tmp/checkpoint_mainnet_100
  ...
  ```

### State Tracking

To avoid re-uploading the same checkpoint multiple times, the script keeps a state file:

- State file path: `${HOME}/.checkpoint_uploader_state`
- Each uploaded or skipped-already-on-S3 checkpoint is stored as a single line:

  ```text
  BUCKET|NETWORK|SUFFIX
  ```

- Before uploading, it checks if `BUCKET|net|suf` is already in the state file:
  - If present → logs `SKIP (state)` and does nothing.
  - If not present:
    - If the object already exists in S3 → logs `SKIP (exists on S3)` and **adds** it to the state file.
    - Otherwise → zips and uploads, then adds it to the state file.

### Temporary Files

- Temporary directory for zip files: `/tmp/checkpoint_zips`
- Per-upload archive name:

  ```text
  /tmp/checkpoint_zips/checkpoint_<net>_<suffix>.zip
  ```

- After a successful upload, the zip file is deleted.

## cleanup_old_releases.sh

Deletes old objects from an S3 bucket based on their `LastModified` timestamp.
Used to cleanup the provable-releases bucket if needed.

### Description

1. Computes a cutoff timestamp (UTC) for **20 days ago**.
2. Lists all objects in the bucket whose `LastModified` value is older than or equal to that cutoff.
3. Deletes each matching object.

### Usage

```bash
./cleanup_old_releases.sh
```

### Requirements

- AWS CLI installed and configured with permissions to:
  - `s3api list-objects-v2`
  - `s3api delete-object`
- System `date` command must support the `-v` flag (macOS/BSD variant).  
  **Note:** On Linux, this will not work; you would need GNU `date` syntax:

  ```bash
  date -d '20 days ago' -u +"%Y-%m-%dT%H:%M:%S"
  ```

### Configuration

The bucket is hardcoded:

```bash
BUCKET="provable-binaries-releases"
```

Modify as needed.

## fetch_git_authors.sh

### Description

Parses a GitHub *compare URL*, fetches all commits between the two branches, and prints a **deduplicated, sorted list of authors**.
It supports both GitHub user accounts (`author.login`) and commits without GitHub association (`commit.author.name`).

### Usage

```bash
./fetch_git_authors.sh https://github.com/ProvableHQ/snarkVM/compare/mainnet...staging
```

If the argument is missing or invalid, the script prints a usage message or an error.

### Accepted URL Format

The script requires URLs matching:

```
https://github.com/<owner>/<repo>/compare/<base>...<head>
```

Examples:

- `https://github.com/ProvableHQ/snarkVM/compare/mainnet...staging`
- `https://github.com/user/project/compare/dev...feature-x`

Captured fields:

- **owner** – GitHub organization or username  
- **repo** – repository name  
- **base** – left side of the comparison  
- **head** – right side of the comparison  

These values are echoed before querying the API:

```
Owner = ProvableHQ
Repo  = snarkVM
Base  = mainnet
Head  = staging
```

### Requirements

- `curl`
- `jq`

If GitHub rate limits unauthenticated requests, you may need to export:

```bash
export GITHUB_TOKEN=<token>
```

and modify the script to send:

```bash
-H "Authorization: token $GITHUB_TOKEN"
```

## generate_snapshots.sh

### Description

Automates the generation of **Aleo checkpoint snapshots** from a running `snarkOS` node
The script repeatedly monitors the node’s latest block height and triggers a database backup (`db_backup`) every time a height milestone is reached.

The snapshots are written to `/tmp/checkpoint_<network_name>_<height>` and are intended for later packaging/upload (e.g., by the checkpoint uploader script).

### Usage

```bash
./generate_snapshots.sh <network_id> <network_name> <port>
```

Example:

```bash
./generate_snapshots.sh 2 mainnet 3030
```

Arguments:

- **network_id** – Numerical Aleo network ID used by snarkOS.
- **network_name** – Network string used in REST endpoints (`mainnet`, `testnet`, `canary`).
- **port** – REST server port where snarkOS exposes its API.

### Requirements

- A running **snarkOS node** with:
  - REST API enabled on `127.0.0.1:<port>`
  - JWT authentication enabled for `/db_backup`
- `curl`
- Write access to `/tmp`

### Notes

- If the node becomes stuck (height does not increase), the script exits.
- Snapshots must later be zipped & uploaded by another script (e.g., `checkpoint_uploader.sh`).

## list_running_ec2s.sh

### Description

Lists all **running EC2 instances** across every AWS region whose name starts with `us` (e.g., `us-east-1`, `us-west-2`).  
For each instance, it prints:

- Region
- Instance ID
- Instance Name (from the `Name` tag, if present)

This script is useful for quick auditing of EC2 usage across all US regions.

---

### Usage

```bash
./list_running_ec2s.sh
```

No arguments are required.

### Example Output

```
Instances in region: us-east-1
Instance ID: i-0f123abcde4567890, Name: webserver-1
Instance ID: i-02468ace13579bdf0, Name: No Name tag
----------------------------------
Instances in region: us-west-2
Instance ID: i-0abcd1234ef567890, Name: snarkos-node-01
----------------------------------
```

### Requirements

- AWS CLI with permission to:
  - `ec2:DescribeRegions`
  - `ec2:DescribeInstances`
- `jq`
- `base64`
- Proper AWS credentials (env vars, config file, or instance role)

---

### Notes

- The script only lists **running** instances (`instance-state-name=running`).
- You can modify the region filter to include more regions (e.g., global scan).


## notify_slack.sh

A lightweight Bash CLI tool for sending Slack notifications directly from scripts or the terminal.
Supports threading, rich message formatting, colored blocks, and user mentions including `@here`, `@channel`, and `@everyone`.

Its idea is to notify about the start and finish of stress test runs. It is in bash, so it can be integrated in other scripts we use,
like the manual test runs, also it can be invoked by talisker with the right options for automated test runs.

### Features

-  Simple message sending.
-  Threaded replies.
-  Message formatting: plain, bold, code blocks.
-  Colored message blocks (`good`, `warning`, `danger`, or custom HEX colors).
-  User mentions and special mentions (`@here`, `@channel`, `@everyone`).
-  Automatically returns `thread_ts` for easy threading (read bellow).

### Usage

You need to export your `SLACK_TOKEN` and `CHANNEL_ID` in the terminal/env of use:

```bash
export SLACK_TOKEN="xoxb-XXXXXXXXXXXXX-XXXXXXXXXXXXX-XXXXXXXXXXXXXXXXXXXXXXXX"
export CHANNEL_ID="CXXXXXXXXXX"
```

```bash
./notify_slack.sh -m "Message text" [options]
```

###  Options

| Option  | Description                                      | Example                       |
|---------|--------------------------------------------------|-------------------------------|
| `-m`    | **(Required)** Message text                      | `-m "Hello, world!"`          |
| `-c`    | Channel ID (default set in script)               | `-c C1234567890`              |
| `-t`    | Thread timestamp for threaded reply              | `-t 1715580000.123456`        |
| `-f`    | Format: `plain`, `bold`, `code`                  | `-f bold`                     |
| `-o`    | Block color: `good`, `warning`, `danger`, or HEX | `-o danger` or `-o "#36a64f"` |
| `-n`    | Mentions: User IDs or `@here,@channel,@everyone` | `-n "@here,U12345678"`        |
| `-k`    | Slack Bot Token (override default)               | `-k xoxb-xxxxxxxx`            |
| `-h`    | Show help and usage                              | `-h`                          |


###  Examples

#### 1. Send a Simple Message

```bash
./notify_slack.sh -m "Deployment started"
```

#### 2. Send a Bold Success Message with a Green Block and Mention @here

```bash
./notify_slack.sh -m 'Deployment finished!' -f bold -o good -n "@here"
```

#### 3. Send a Message and Capture the \`thread_ts\` for Replies

```bash
thread_ts=$(./notify_slack.sh -m "🛠️ Starting batch processing..." -f bold -o warning -n "@channel")
./notify_slack.sh -m "📦 Batch 1 complete" -t "$thread_ts"
./notify_slack.sh -m "📦 Batch 2 complete" -t "$thread_ts"
```

#### 4. Send an Error Notification with a Red Block and Code Formatting

```bash
./notify_slack.sh -m '🔥 Critical error!\nCheck logs:\n/var/log/app/error.log' -f code -o danger -n "@everyone"
```

#### 5. Reply in an Existing Thread

```bash
./notify_slack.sh -m '✅ All services restarted successfully.' -t 1715580000.123456
```

### Notes

- The Slack Bot Token (`SLACK_TOKEN`) and default channel (`CHANNEL_ID`) can be set directly in the terminal or passed using `-k` and `-c`.
- To mention users, provide their Slack User IDs (Go to the profile of the user in slack, the row that starts with the "message" button ends with three vertical dots, click on them, click "Copy member ID"). Special mentions like `@here`, `@channel`, and `@everyone` are automatically handled.
- If no `-t` is provided, the script returns the `thread_ts` of the posted message for easy chaining. For example when Talisker is running its tests, it opens a new thread on a new test run, keeps the `thread_ts` and adds updates to that thread.


## store_latest_snapshot.py

### Description

Streams **huge Aleo ledger snapshots** from HTTP directly into **Amazon S3** using multipart uploads, with:

- HTTP Range downloads and resumable state
- Per-part retries, stall detection, and optional throughput thresholds
- Strict resume semantics tied to the original source snapshot URL
- Optional HTTP keep‑alive session
- Fallback path when the origin does not support Range/Content-Length

Typical usage:

```bash
cd scripts
. .venv_store_latest_snapshot/bin/activate
python store_latest_snapshot.py --network canary
```

---

### High-Level Flow

1. Determine the **source snapshot URL**:
   - Default: fetches `https://ledger.aleo.network/<network>/snapshot/latest.txt`
   - Parses the first URL ending in `.tar.zst`, `.tar.gz`, `.tar.xz`, or `.zip`
   - Or uses `--url` if explicitly provided

2. Determine the **S3 bucket & key**:
   - Bucket:
     - `--bucket` argument, or
     - `INGEST_BUCKET` env, or
     - Default: `aleo-snapshots`
   - Key:
     - `--key` argument, or
     - `<network prefix><basename(real-url)>`
       - Prefix mapping (override via env):
         - `main`    → `INGEST_PREFIX_MAIN`    (default: `main/`)
         - `testnet` → `INGEST_PREFIX_TESTNET` (default: `testnet/`)
         - `canary`  → `INGEST_PREFIX_CANARY`  (default: `canary/`)

3. Probe origin with HTTP **HEAD**:
   - Reads `Content-Length` and `Accept-Ranges`
   - If `Accept-Ranges=bytes` and size known → uses **Range-based multipart download**
   - Otherwise → falls back to download into a temp file, then multipart upload from disk

4. Manage **multipart upload** to S3:
   - Configurable part size (MiB)
   - Tracks parts and ETags in a local **state file** for resume
   - On success, calls `CompleteMultipartUpload` and deletes the state file

5. Robust **resume logic**:
   - Strictly tied to:
     - `Bucket`
     - `Key`
     - `SourceURL`
     - `Size`
   - Refuses to resume if:
     - URL is no longer rangeable
     - Content-Length has changed
   - Does **not** automatically switch to a newer snapshot if the source changes

---

### CLI Usage

```bash
python store_latest_snapshot.py --network {main,testnet,canary} [options...]
```

#### Required

- `--network {main,testnet,canary}`  
  Which network’s snapshot to ingest.

#### Optional

- `--url URL`  
  Override the source snapshot URL (skips `latest.txt` parsing).

- `--bucket BUCKET`  
  Destination S3 bucket. Overrides `INGEST_BUCKET` / default.

- `--key KEY`  
  Destination S3 key. If omitted:
  - Uses `<network prefix><basename(real-url)>` (see mapping above).

- `--part-size-mib N` (default: `256`)  
  Multipart part size in MiB.

- `--state-dir DIR` (default: `.upload_state`)  
  Directory to store state JSON for resumable uploads.

- `--checksum {none,sha256}` (default: `none`)  
  Include `ChecksumSHA256` header per part.

- `--region REGION`  
  Explicit AWS region. If omitted:
  - Calls `get_bucket_location` to detect bucket region, defaulting to `us-west-2` on failure.

- `--user-agent-suffix SUFFIX` (default: `http-to-s3-multipart/2.2`)  
  Appended to the HTTP `User-Agent` header.

- `--fallback-tempdir DIR`  
  Directory for temporary file when origin lacks Range/Content-Length.

- `--stall-timeout SECONDS` (default: `20`)  
  If no bytes are received for this many seconds, restart the part (with retries).

- `--force-new`  
  Ignore existing state and start a **new** multipart upload (old state kept).

- `--http-session {off,on}` (default: `off`)  
  Use a persistent `requests.Session` with keep‑alive pools when `on`.

- `--min-mibps FLOAT` (default: `0.0`)  
  If >0, enforces a minimum instantaneous throughput (MiB/s) for each part.

- `--min-mibps-seconds SECONDS` (default: `20`)  
  How long throughput must stay below `--min-mibps` before the part is retried.

- `--recycle-session-every N` (default: `0`)  
  When `--http-session on`, recycle the HTTP session after every N parts (0=disabled).

### Environment Variables

- `INGEST_BUCKET`  
  Default S3 bucket when `--bucket` is not provided.

- `INGEST_PREFIX_MAIN` / `INGEST_PREFIX_TESTNET` / `INGEST_PREFIX_CANARY`  
  Override the S3 key prefixes for each network.

- `LEDGER_BASE`  
  Base URL for `latest.txt`. Default: `https://ledger.aleo.network`.

### Resume & State Files

State files are stored under `--state-dir` (default `.upload_state`) and named from:

```text
<bucket>__<key>.json   # with '/' replaced by '__'
```

The state JSON contains:

```json
{
  "Bucket": "my-bucket",
  "Key": "canary/snapshot.tar.zst",
  "UploadId": "...",
  "Size": 1234567890,
  "PartSize": 268435456,
  "Parts": [
    {"PartNumber": 1, "ETag": ""...""},
    {"PartNumber": 2, "ETag": ""...""}
  ],
  "SourceURL": "https://ledger.aleo.network/canary/..."
}
```

On resume:

- Picks the most recent state for:
  - Given `Bucket`
  - Given network prefix (`main/`, `testnet/`, `canary/`)
- Validates:
  - `Key` basename == `SourceURL` basename
  - `Size` > 0
  - HEAD to `SourceURL`:
    - `Accept-Ranges == bytes`
    - `Content-Length` unchanged

If checks fail, it refuses to resume and exits with a non‑zero code (131).

### Ctrl+C Handling

- **First Ctrl+C**:
  - Sets soft cancel mode: finish the current part, then stop
  - Leaves upload incomplete and keeps state to allow resume

- **Second Ctrl+C**:
  - Hard abort: raises `KeyboardInterrupt` immediately
  - In `multipart_upload_range_mode`:
    - Prints a message and deletes the state file (abort call to S3 is commented out)

Top-level `main()` catches `KeyboardInterrupt` and exits with code `130`.

### Requirements

- Python 3
- `boto3` and `botocore`
- `requests`, `urllib3`
- AWS credentials with permission to:
  - `s3:GetBucketLocation`
  - `s3:CreateMultipartUpload`
  - `s3:UploadPart`
  - `s3:CompleteMultipartUpload`
  - (optional) `s3:AbortMultipartUpload`
- Network access to:
  - `ledger.aleo.network` (or your custom `LEDGER_BASE`)
  - S3 endpoint for the target bucket/region

---

### Example

```bash
# In a prepared venv with dependencies installed:
python store_latest_snapshot.py \
  --network canary \
  --bucket aleo-snapshots \
  --part-size-mib 512 \
  --http-session on \
  --min-mibps 5.0 \
  --min-mibps-seconds 30
```

This will:

- Discover the latest canary snapshot URL
- Upload it to `s3://aleo-snapshots/canary/<basename>` using 512 MiB parts
- Maintain at least ~5 MiB/s per part (or retry)
- Use a keep‑alive HTTP session for better performance


## talisker_control.sh

Thin CLI wrapper around the **Talisker** JSON-RPC API, executed remotely on an **STM** EC2 instance.

### Description

1. Resolves the Builder EC2 public IP (with a local cache in `.builder_ip`).
2. Builds a JSON-RPC payload from a method name and `key=value` arguments.
3. SSH-es into the Builder instance.
4. Runs a `curl` POST against `http://localhost:$PORT/rpc` with the payload.
5. Prints the JSON response via `jq`.

If the cached IP is invalid/unreachable, it clears the cache, discovers the IP again, and retries once.

### Usage

```bash
./talisker_control.sh <method> [key1=value1 key2=value2 ...]
```

Examples:

```bash
# Simple ping (no params)
./talisker_control.sh ping

# Run a test suite with named params
./talisker_control.sh run_test_suite name=pre_release_all ref=HEAD branch=staging

# Cancel tests
./talisker_control.sh cancel_tests reason=manual_stop
```

`TALISKER_API_PORT` can be set to override the default JSON-RPC port.

### Arguments

- `<method>` (required)  
  JSON-RPC method name, e.g. `ping`, `run_test_suite`, `cancel_tests`.

- `key=value` (optional, repeated)  
  Becomes JSON fields inside the `params` object.  
  For example:

  ```bash
  ./talisker_control.sh run_test_suite name=foo ref=HEAD branch=main
  ```

  Produces:

  ```json
  {
    "jsonrpc": "2.0",
    "method": "run_test_suite",
    "params": {
      "name": "foo",
      "ref": "HEAD",
      "branch": "main"
    },
    "id": 1
  }
  ```

### Environment

- `TALISKER_API_PORT` – Optional.  
  Port on which the Talisker JSON-RPC server listens on the Builder machine.  
  Default: `3030`.

- Local AWS credentials – used by `aws ec2 describe-instances` to look up the Builder instance IP.

### Builder IP Resolution

`get_ip()` implements IP discovery and caching:

1. If `.builder_ip` exists → read and use that IP.
2. Otherwise, call:

   ```bash
   aws ec2 describe-instances      --filters "Name=tag:Name,Values=Aleo Builder" "Name=instance-state-name,Values=running"      --query "Reservations[].Instances[].PublicIpAddress"      --output text
   ```

3. Write the result to `.builder_ip` and echo it.

If the initial SSH call fails, the script:

- Deletes `.builder_ip`.
- Re-queries AWS for the Builder IP.
- Tries **once more**.

If no running instance is found, it prints:

```text
ERROR: Could not get Builder IP from AWS.
```

and exits non-zero.

### Requirements

- Local:
  - `aws` CLI configured with IAM permissions:
    - `ec2:DescribeInstances` (to discover Builder IP)
  - `ssh` client
- Remote (Builder instance):
  - Talisker JSON-RPC service listening on `localhost:$PORT` (`/rpc` endpoint)
  - `curl`
  - `jq`

All are available on the STM instance.
