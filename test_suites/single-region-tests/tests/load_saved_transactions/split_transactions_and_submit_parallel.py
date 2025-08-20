import boto3
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import re
import requests
import zipfile

from concurrent.futures import ThreadPoolExecutor, as_completed

LOG_PATH = "confirmed_txs.log"
_LOG_LOCK = threading.Lock()

def logf(msg: str):
    ts = time.strftime('%F %T')
    line = f"[{ts}] {msg}"
    # Console
    print(line, flush=True)
    # File (thread-safe)
    with _LOG_LOCK:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")

# ----------------------------
# Helpers
# ----------------------------

def get_consensus_version(ip_address: str, network: str, timeout: float = 3.0) -> int:
    """
    GET http://{ip}:3030/{network}/consensus_version
    Returns an integer (e.g., 10).
    """
    url = f"http://{ip_address}:3030/{network}/consensus_version"
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return int(r.text.strip())

def wait_until_consensus_version(ip_address: str,
                                 network: str,
                                 target_consensus_version: int,
                                 poll_interval: float = 2.0,
                                 timeout_seconds: float = 600.0):
    """
    Wait until network consensus_version >= target_consensus_version.
    Fail if not reached within timeout_seconds (default 10 minutes).
    """
    logf(f"Waiting for consensus_version >= {target_consensus_version} (timeout {int(timeout_seconds)}s)")
    start = time.monotonic()

    while True:
        try:
            v = get_consensus_version(ip_address, network)
            logf(f"consensus_version={v} / target={target_consensus_version}")
            if v >= target_consensus_version:
                logf("Target consensus version reached.")
                return
        except Exception as e:
            logf(f"Consensus version check error: {e}")

        if time.monotonic() - start >= timeout_seconds:
            raise TimeoutError(
                f"Consensus version did not reach {target_consensus_version} within {int(timeout_seconds)} seconds."
            )

        time.sleep(poll_interval)

def get_latest_height(ip_address, network, timeout=3):
    url = f"http://{ip_address}:3030/{network}/block/height/latest"
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return int(r.text.strip())

def tx_seen_in_range(ip_address, network, tx_id, start_h, end_h, timeout=5):
    if start_h is None or end_h is None or end_h < start_h:
        return False
    start_h = max(1, start_h)
    for h in range(start_h, end_h + 1):
        url = f"http://{ip_address}:3030/{network}/block/{h}"
        resp = requests.get(url, timeout=timeout)
        if resp.status_code != 200:
            continue
        block = resp.json()
        ids = {tx["transaction"]["id"] for tx in block.get("transactions", [])}
        if tx_id in ids:
            return True
    return False

# ----------------------------
# S3 download
# ----------------------------

def download_transaction_files_from_s3(bucket_name, prefix, destination_folder, network, num_validators,
                                       pregeneration_execution_tx_count, pregeneration_deployment_tx_count,
                                       target_consensus_version: int, target_height: int):
    """
    Downloads the newest (by LastModified) archive whose name matches the given target_height:
      transactions-<network>-<N>val-<target_consensus_version>-<target_height>-<release>-<exec>-<deploy>.zip
    Extracts it into destination_folder and removes the .zip.
    """
    s3 = boto3.client("s3")
    os.makedirs(destination_folder, exist_ok=True)

    want_prefix = f"{prefix}/transactions-{network}-{num_validators}val-{target_consensus_version}-{target_height}-"
    want_suffix = f"-{pregeneration_execution_tx_count}-{pregeneration_deployment_tx_count}.zip"

    candidates = []  # list of dicts: {"Key": ..., "LastModified": ..., "Size": ...}

    logf(f"S3 search in s3://{bucket_name}/{prefix} for height={target_height}")
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket_name, Prefix=f"{prefix}/transactions-{network}-{num_validators}val-"):
        for obj in page.get("Contents", []) or []:
            key = obj["Key"]
            if key.startswith(want_prefix) and key.endswith(want_suffix):
                candidates.append({
                    "Key": key,
                    "LastModified": obj.get("LastModified"),
                    "Size": obj.get("Size"),
                })

    if not candidates:
        msg = (f"No zip matched height={target_height}: "
               f"prefix='{want_prefix}*' suffix='{want_suffix}'")
        logf(msg)
        raise RuntimeError(msg)

    # Pick newest by LastModified
    newest = max(candidates, key=lambda x: x["LastModified"])
    if len(candidates) > 1:
        logf("Multiple zips matched; selecting newest by LastModified:")
        for c in sorted(candidates, key=lambda x: x["LastModified"], reverse=True):
            lm = c["LastModified"]
            sz = c["Size"]
            logf(f"  {c['Key']}  (LastModified={lm}, Size={sz})")
        logf(f"Chosen: {newest['Key']}")

    key = newest["Key"]
    filename = os.path.basename(key)
    dest_path = os.path.join(destination_folder, filename)

    logf(f"Downloading s3://{bucket_name}/{key} -> {dest_path}")
    s3.download_file(bucket_name, key, dest_path)

    with zipfile.ZipFile(dest_path, 'r') as zip_ref:
        members = zip_ref.namelist()
        logf(f"Extracting {len(members)} file(s) from {filename} into {destination_folder}")
        zip_ref.extractall(destination_folder)
    os.remove(dest_path)
    logf(f"Removed archive {dest_path}")

# ----------------------------
# Scanner
# ----------------------------

def block_scanner(ip_address, network, expected_tx_count, tx_ids_sent, tx_ids_lock,
                  start_height=1, poll_interval=2, max_idle_blocks=20,
                  log_path=LOG_PATH, start_event=None):
    checked_height = start_height
    matched_tx_ids = set()
    blocks_since_last_expected = 0  # consecutive blocks without confirming an expected TX

    logf(f"Scanner starting at height={start_height} "
         f"(expected_tx_count={expected_tx_count}, max_idle_blocks={max_idle_blocks})")

    while True:
        try:
            latest_height = get_latest_height(ip_address, network, timeout=3)
            if checked_height > latest_height:
                logf(f"No new blocks yet. Latest height={latest_height}")
                time.sleep(poll_interval)
                continue

            # Process blocks up to latest_height
            while checked_height <= latest_height:
                block_url = f"http://{ip_address}:3030/{network}/block/{checked_height}"
                block_resp = requests.get(block_url, timeout=5)
                if block_resp.status_code != 200:
                    logf(f"Failed to fetch block {checked_height}: {block_resp.text}")
                    # skip this height to avoid stalling
                    checked_height += 1
                    continue

                block_data = block_resp.json()
                block_height = block_data.get("header", {}).get("metadata", {}).get("height", checked_height)
                transactions = block_data.get("transactions", [])
                logf(f"Block {block_height}: {len(transactions)} tx(s)")

                new_tx_ids = {tx["transaction"]["id"] for tx in transactions}

                # Did this block confirm any expected TXs?
                matched_this_block = False
                with tx_ids_lock:
                    newly_matched = new_tx_ids.intersection(tx_ids_sent) - matched_tx_ids
                    have_expected = len(tx_ids_sent) > 0

                if newly_matched:
                    matched_this_block = True
                    for tx_id in newly_matched:
                        logf(f"CONFIRMED tx={tx_id} in block {block_height}")
                    matched_tx_ids.update(newly_matched)

                # Update the consecutive-blocks-without-expected counter.
                should_count = (start_event.is_set() if start_event else have_expected)
                if should_count:
                    if matched_this_block:
                        blocks_since_last_expected = 0
                    else:
                        blocks_since_last_expected += 1

                # Progress log
                with tx_ids_lock:
                    remaining_count = len(tx_ids_sent - matched_tx_ids)
                logf(f"Progress: confirmed={expected_tx_count - remaining_count}/{expected_tx_count} "
                     f"(remaining={remaining_count})")

                checked_height += 1

                # Early-exit checks after processing this block
                if len(matched_tx_ids) >= expected_tx_count:
                    logf("All expected transactions confirmed. Scanner exiting.")
                    return

                if have_expected and blocks_since_last_expected >= max_idle_blocks:
                    logf(f"Scanner stopping: {max_idle_blocks} consecutive blocks without expected confirmations.")
                    with tx_ids_lock:
                        remaining = sorted(tx_ids_sent - matched_tx_ids)
                    logf("Unconfirmed TX list (truncated to 200 lines below if huge):")
                    for i, tx_id in enumerate(remaining):
                        if i >= 200:
                            logf(f"... ({len(remaining) - 200} more)")
                            break
                        logf(f"  {tx_id}")
                    return

            time.sleep(poll_interval)

        except requests.exceptions.RequestException as e:
            logf(f"Scanner warning (temporary): {e}")
            time.sleep(poll_interval)
            continue
        except Exception as e:
            logf(f"Scanner fatal error: {e}")
            with tx_ids_lock:
                remaining = sorted(tx_ids_sent - matched_tx_ids)
            logf("Unconfirmed TX list after fatal error (truncated to 200):")
            for i, tx_id in enumerate(remaining):
                if i >= 200:
                    logf(f"... ({len(remaining) - 200} more)")
                    break
                logf(f"  {tx_id}")
            return

# ----------------------------
# Broadcasting
# ----------------------------

def extract_tx_id_from_payload(s: str) -> str:
    obj = json.loads(s)
    txid = obj.get("id")
    if not (isinstance(txid, str) and txid.startswith("at1")):
        raise ValueError(f"Bad or missing tx id: {txid!r}")
    return txid

def send_transactions(transactions_path, ip_address, network, tx_ids_sent, tx_ids_lock, start_event=None):
    logf(f"[Exec @ {ip_address}] Starting broadcast from {transactions_path}")
    results = []
    event_set = False
    sent_count = 0

    with open(transactions_path, "r") as f:
        for i, tx in enumerate(f.readlines()):
            if i and i % 20 == 0:
                time.sleep(1)

            if start_event and not event_set:
                start_event.set()
                event_set = True
                logf("[Exec] start_event set (execution)")

            cmd = f"curl http://{ip_address}:3030/{network}/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()

            echoed_id = output.strip().strip('"')
            try:
                exp_id = extract_tx_id_from_payload(tx)
            except Exception as e:
                logf(f"[Exec] Invalid payload (cannot extract id): {e}")
                exp_id = "unknown"

            if echoed_id.startswith("at1"):
                if exp_id != "unknown" and echoed_id != exp_id:
                    logf(f"[Exec] Warning: echoed {echoed_id} != expected {exp_id}")
                else:
                    logf(f"[Exec] TX sent : {echoed_id}")
            else:
                logf(f"[Exec] Unrecognized output: '{output}' (stderr: '{error[:200]}')")

            results.append(f"Executed {cmd}\nOutput: {output}\nError: {error}")
            sent_count += 1

    logf(f"[Exec @ {ip_address}] Finished sending {sent_count} tx(s)")
    return results

def send_deployment_transactions(deploy_paths, expected_deploy_ids, ip_addresses, network,
                                 blocks_before_retry=10, max_retries=5, poll_interval=2, start_event=None):
    logf(f"[Deploy] Sending {len(deploy_paths)} deployment tx(s) with retries "
         f"(retry after {blocks_before_retry} blocks, max {max_retries})")

    num_validators = len(ip_addresses)
    first_ip = ip_addresses[0].strip()
    first_sent = False

    # Build per-TX state
    states = []
    for i, path in enumerate(deploy_paths):
        with open(path, "r") as f:
            payload = f.read().strip()
        states.append({
            "idx": i,
            "path": path,
            "payload": payload,
            "txid": expected_deploy_ids[i],  # fixed, deterministic
            "last_sent_height": None,
            "last_checked_height": None,
            "retries": 0,
            "confirmed": False,
            "ip_index": i % num_validators,
        })

    def broadcast(state):
        nonlocal first_sent
        ip = ip_addresses[state["ip_index"]].strip()
        cmd = (
            f"curl http://{ip}:3030/{network}/transaction/broadcast "
            f"-X POST -H \"Content-Type: application/json\" -d '{state['payload']}'"
        )
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode().strip()
        err = result.stderr.decode().strip()

        echoed = output.strip().strip('"')
        if echoed.startswith("at1") and echoed != state["txid"]:
            logf(f"[Deploy] Warning: echoed {echoed} != expected {state['txid']} (idx {state['idx']})")

        logf(f"[Deploy] TX {state['txid']} sent to {ip}")

        # Start counting idle blocks only after the very first actual send
        if start_event and not first_sent:
            start_event.set()
            first_sent = True
            logf("[Deploy] start_event set (deployment)")

        try:
            state["last_sent_height"] = get_latest_height(first_ip, network)
        except Exception as e:
            logf(f"[Deploy] Warning: cannot fetch latest height after send: {e}")
            state["last_sent_height"] = state["last_sent_height"] or 1
        state["last_checked_height"] = state["last_sent_height"]

        # round-robin next attempt
        state["ip_index"] = (state["ip_index"] + 1) % num_validators

    # Initial broadcast
    for st in states:
        broadcast(st)
        time.sleep(2)

    # Manage retries until all confirmed or exhausted
    while True:
        try:
            latest = get_latest_height(first_ip, network)
        except Exception as e:
            logf(f"[Deploy] Warning: failed to get latest height: {e}")
            time.sleep(poll_interval)
            continue

        pending = 0
        for st in states:
            if st["confirmed"]:
                continue

            start_h = (st["last_checked_height"] or 0) + 1
            seen = tx_seen_in_range(first_ip, network, st["txid"], start_h, latest)
            st["last_checked_height"] = latest

            if seen:
                st["confirmed"] = True
                logf(f"[Deploy] Confirmed {st['txid']} (idx {st['idx']})")
                continue

            # Not seen; retry if enough blocks passed since last send
            if st["last_sent_height"] is not None and latest - st["last_sent_height"] >= blocks_before_retry:
                if st["retries"] < max_retries:
                    st["retries"] += 1
                    logf(f"[Deploy] Retry {st['retries']}/{max_retries} for {st['txid']} "
                         f"(no detection in {blocks_before_retry} blocks since {st['last_sent_height']})")
                    broadcast(st)
                    time.sleep(2)
                else:
                    logf(f"[Deploy] Gave up after {max_retries} retries for {st['txid']} (idx {st['idx']})")

            if not st["confirmed"] and st["retries"] < max_retries:
                pending += 1

        if pending == 0:
            logf("[Deploy] All deployment TXs are either confirmed or exhausted retries.")
            break

        time.sleep(poll_interval)

# ----------------------------
# TX preparation
# ----------------------------

def prepare_transactions(txs_folder, tx_files, base_folder):
    tx_paths = []
    txs = []
    for file in tx_files:
        tx_path = os.path.join(txs_folder, file)
        with open(tx_path, "r") as f:
            lines = f.readlines()
            for i, line in enumerate(lines):
                individual_tx_path = os.path.join(base_folder, f"{file.replace('.txt', '')}_tx_{i}.txt")
                with open(individual_tx_path, "w") as out_f:
                    out_f.write(line)
                tx_paths.append(individual_tx_path)
                txs.append(line)
    return tx_paths, txs

def collect_expected_ids(paths):
    ids = []
    for p in paths:
        with open(p, "r") as f:
            payload = f.read().strip()   # each file contains one TX JSON
        ids.append(extract_tx_id_from_payload(payload))
    return ids

# ----------------------------
# Main
# ----------------------------

def main():
    if len(sys.argv) < 8:
        print("Usage: script.py <network> <s3_bucket> <s3_prefix> <exec_cnt> <deploy_cnt> <target_consensus_version> <target_height>")
        sys.exit(1)

    network = sys.argv[1]
    s3_bucket = sys.argv[2]
    s3_prefix = sys.argv[3]
    pregeneration_execution_tx_count = sys.argv[4]
    pregeneration_deployment_tx_count = sys.argv[5]
    txs_target_consensus_version = int(sys.argv[6])
    txs_target_consensus_version_height = int(sys.argv[7])

    logf("=== TX Runner starting ===")
    logf(f"Args: network={network}, bucket={s3_bucket}, prefix={s3_prefix}, "
         f"exec_cnt={pregeneration_execution_tx_count}, deploy_cnt={pregeneration_deployment_tx_count}, "
         f"target_height={txs_target_consensus_version}, "
         f"target_height={txs_target_consensus_version_height}")

    ip_addresses_path = os.path.join(os.getcwd(), "..", "..", "ip_addresses.txt")
    if not os.path.exists(ip_addresses_path):
        msg = "Missing ip_addresses.txt file, make sure to run terraform..."
        logf(msg)
        print(msg)
        sys.exit(1)

    with open(ip_addresses_path, "r") as f:
        ip_addresses = f.readlines()
    num_validators = len(ip_addresses)
    first_ip = ip_addresses[0].strip()
    logf(f"Loaded {num_validators} validator IP(s). First IP: {first_ip}")

    # 1) Wait for consensus version
    try:
        wait_until_consensus_version(first_ip, network, txs_target_consensus_version,
                                     poll_interval=2.0, timeout_seconds=600.0)
    except TimeoutError as e:
        logf(str(e))
        sys.exit(1)

    # 2) Download the exact zip for that height
    txs_folder = os.path.join(os.getcwd(), "..", "..", "transaction_files")
    download_transaction_files_from_s3(
        s3_bucket, s3_prefix, txs_folder, network, num_validators,
        pregeneration_execution_tx_count, pregeneration_deployment_tx_count,
        txs_target_consensus_version,
        txs_target_consensus_version_height
    )

    # 3) Discover tx files
    pattern_deploys = re.compile(rf"^deploys-{network}-\d+val-\d+-\d+\.txt$")
    pattern_executions = re.compile(rf"^executions-{network}-\d+val-\d+-\d+\.txt$")

    deploy_files = [f for f in os.listdir(txs_folder) if pattern_deploys.match(f)]
    exec_files = [f for f in os.listdir(txs_folder) if pattern_executions.match(f)]
    deploy_files.sort()
    exec_files.sort()
    logf(f"Found deploy files: {len(deploy_files)}, execution files: {len(exec_files)}")

    # 4) Split into single-tx files
    transactions_split_folder_path = os.path.join(os.getcwd(), "transactions_to_send")
    os.makedirs(transactions_split_folder_path, exist_ok=True)

    deploy_paths, deploy_txs = prepare_transactions(txs_folder, deploy_files, transactions_split_folder_path)
    exec_paths, exec_txs = prepare_transactions(txs_folder, exec_files, transactions_split_folder_path)
    logf(f"Prepared single-tx files: deploy={len(deploy_paths)}, exec={len(exec_paths)}")

    expected_tx_count = len(deploy_txs) + len(exec_txs)
    expected_deploy_ids = collect_expected_ids(deploy_paths)
    expected_exec_ids   = collect_expected_ids(exec_paths)
    logf(f"Expected TX count total={expected_tx_count} (deploy={len(expected_deploy_ids)}, exec={len(expected_exec_ids)})")

    tx_ids_sent = set()
    tx_ids_lock = threading.Lock()
    with tx_ids_lock:
        tx_ids_sent.update(expected_deploy_ids)
        tx_ids_sent.update(expected_exec_ids)

    # 5) Latest height baseline (for scanner start)
    try:
        latest_height = get_latest_height(first_ip, network)
    except Exception as e:
        logf(f"Failed to fetch latest block height, defaulting to 1: {e}")
        latest_height = 1
    logf(f"Scanner baseline latest_height={latest_height}")

    start = time.time()
    logf("Starting block scanner thread...")

    broadcast_started = threading.Event()

    scanner_thread = threading.Thread(
        target=block_scanner,
        args=(first_ip, network, expected_tx_count, tx_ids_sent, tx_ids_lock, latest_height),
        kwargs={"max_idle_blocks": 20, "log_path": LOG_PATH, "start_event": broadcast_started},
        daemon=True,
    )
    scanner_thread.start()

    logf("Starting deployment broadcaster thread...")
    deploy_thread = threading.Thread(
        target=send_deployment_transactions,
        args=(deploy_paths, expected_deploy_ids, ip_addresses, network),
        kwargs={"blocks_before_retry": 10, "max_retries": 5, "poll_interval": 2, "start_event": broadcast_started},
        daemon=True,
    )
    deploy_thread.start()

    # 6) Execution TXs (parallel)
    logf(f"Starting execution broadcasters for {len(exec_paths)} file(s) across {num_validators} validator(s)...")
    with ThreadPoolExecutor(max_workers=num_validators) as exec_pool:
        exec_futures = {
            exec_pool.submit(
                send_transactions,
                exec_paths[i],
                ip_addresses[i % num_validators].strip(),
                network,
                tx_ids_sent,
                tx_ids_lock,
                broadcast_started,  # pass event
            ): i for i in range(len(exec_paths))
        }
        for future in as_completed(exec_futures):
            i = exec_futures[future]
            try:
                _ = future.result()
            except Exception as exc:
                logf(f"[Execution] Exception: {exc}")
            else:
                logf(f"[Execution] Validator {i % num_validators} worker completed")

    # 7) Join threads
    logf("Waiting for deployment and scanner threads to finish...")
    deploy_thread.join()
    scanner_thread.join()

    # 8) Cleanup
    end = time.time()
    elapsed = end - start
    logf(f"Time elapsed: {elapsed:.2f} seconds")

    if os.path.isdir(txs_folder):
        try:
            shutil.rmtree(txs_folder)
            logf(f"Removed folder {txs_folder}")
        except Exception as e:
            logf(f"Cleanup warning (txs_folder): {e}")

    if os.path.isdir(transactions_split_folder_path):
        try:
            shutil.rmtree(transactions_split_folder_path, ignore_errors=True)
            logf(f"Removed folder {transactions_split_folder_path}")
        except Exception as e:
            logf(f"Cleanup warning (transactions_split_folder_path): {e}")

    logf("Block scanning finished.")
    logf("=== TX Runner done ===")

# ----------------------------
# Entrypoint
# ----------------------------

if __name__ == '__main__':
    main()
