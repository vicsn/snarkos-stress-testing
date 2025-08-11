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

def download_transaction_files_from_s3(bucket_name, prefix, destination_folder, network, num_validators, pregeneration_execution_tx_count, pregeneration_deployment_tx_count):
    s3 = boto3.client("s3")
    os.makedirs(destination_folder, exist_ok=True)

    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.startswith(f"{prefix}/transactions-{network}-{num_validators}val"):
                continue
            if not key.endswith(f"{pregeneration_execution_tx_count}-{pregeneration_deployment_tx_count}.zip"):
                continue

            filename = os.path.basename(key)
            dest_path = os.path.join(destination_folder, filename)

            print(f"Downloading {key} -> {dest_path}")
            s3.download_file(bucket_name, key, dest_path)

            with zipfile.ZipFile(dest_path, 'r') as zip_ref:
                zip_ref.extractall(destination_folder)
                os.remove(dest_path)

def block_scanner(ip_address, network, expected_tx_count, tx_ids_sent, tx_ids_lock,
                  start_height=1, poll_interval=2, max_idle_blocks=20,
                  log_path="confirmed_txs.log", start_event=None):
    checked_height = start_height
    matched_tx_ids = set()
    blocks_since_last_expected = 0  # consecutive blocks without confirming an expected TX

    def log_unconfirmed_summary(reason, log):
        with tx_ids_lock:
            remaining = tx_ids_sent - matched_tx_ids
        num_missing = len(remaining)
        percent_missing = (num_missing / expected_tx_count) * 100 if expected_tx_count > 0 else 0

        log.write(f"\n\n=== Block scanning terminated: {reason} ===\n")
        log.write(f"Unconfirmed TXs ({num_missing}/{expected_tx_count}, {percent_missing:.2f}%):\n")
        for tx_id in sorted(remaining):
            log.write(f"  {tx_id}\n")
        log.write("==========================================\n\n")
        log.flush()

    with open(log_path, "a") as log:
        log.write(f"\n\nStarting scanning blocks from {start_height}...\n\n")
        log.flush()

        while True:
            try:
                latest_url = f"http://{ip_address}:3030/{network}/block/height/latest"
                latest_resp = requests.get(latest_url, timeout=3)
                if latest_resp.status_code != 200:
                    print(f"Failed to get latest height: {latest_resp.text}")
                    time.sleep(poll_interval)
                    continue

                latest_height = int(latest_resp.text.strip())

                if checked_height > latest_height:
                    msg = f"No new blocks yet. Still at height {latest_height}"
                    print(msg)
                    log.write(msg + "\n")
                    log.flush()
                    time.sleep(poll_interval)
                    continue

                # Process blocks up to latest_height
                while checked_height <= latest_height:
                    block_url = f"http://{ip_address}:3030/{network}/block/{checked_height}"
                    block_resp = requests.get(block_url, timeout=5)
                    if block_resp.status_code != 200:
                        print(f"Failed to fetch block {checked_height}: {block_resp.text}")
                        break

                    block_data = block_resp.json()
                    block_height = block_data.get("header", {}).get("metadata", {}).get("height", checked_height)
                    transactions = block_data.get("transactions", [])

                    log_line = f"Block {block_height} with {len(transactions)} transaction(s)"
                    print(log_line)
                    log.write(log_line + "\n")
                    log.flush()

                    new_tx_ids = {tx["transaction"]["id"] for tx in transactions}

                    # Did this block confirm any expected TXs?
                    matched_this_block = False
                    with tx_ids_lock:
                        newly_matched = new_tx_ids.intersection(tx_ids_sent) - matched_tx_ids
                    if newly_matched:
                        matched_this_block = True
                        for tx_id in newly_matched:
                            msg = f"TX {tx_id} confirmed in block {block_height}"
                            print(msg)
                            log.write(msg + "\n")
                        log.flush()
                        matched_tx_ids.update(newly_matched)

                    # Update the consecutive-blocks-without-expected counter.
                    with tx_ids_lock:
                        have_expected = len(tx_ids_sent) > 0
                    should_count = (start_event.is_set() if start_event else have_expected)

                    if should_count:
                        if matched_this_block:
                            blocks_since_last_expected = 0
                        else:
                            blocks_since_last_expected += 1

                    checked_height += 1

                    # Early-exit checks after processing this block
                    if len(matched_tx_ids) >= expected_tx_count:
                        print("All expected transactions confirmed.")
                        log.write("\nAll expected transactions confirmed.\n")
                        log.flush()
                        return

                    if have_expected and blocks_since_last_expected >= max_idle_blocks:
                        print(f"Stopped scanning after {max_idle_blocks} consecutive blocks without confirming an expected TX.")
                        log.write(f"\nStopped after {max_idle_blocks} blocks without expected confirmations.\n")
                        log_unconfirmed_summary("no_expected_confirmations_for_N_blocks", log)
                        return

                time.sleep(poll_interval)

            except requests.exceptions.RequestException as e:
                print(f"Warning: temporary error in block scanner: {e}")
                log.write(f"\nWarning: temporary error during block scanning: {e}\n")
                log.flush()
                time.sleep(poll_interval)
                continue
            except Exception as e:
                print(f"Fatal error in block scanner: {e}")
                log.write(f"\nFatal error during block scanning: {e}\n")
                log_unconfirmed_summary("fatal_exception", log)
                return

def send_transactions(transactions_path, ip_address, network, tx_ids_sent, tx_ids_lock, start_event=None):
    print(f"[Validator @ {ip_address}] Starting transaction broadcast from {transactions_path}")
    results = []
    event_set = False

    with open(transactions_path, "r") as f:
        for i, tx in enumerate(f.readlines()):
            if i and i % 20 == 0:
                time.sleep(1)

            if start_event and not event_set:
                start_event.set()
                event_set = True

            cmd = f"curl http://{ip_address}:3030/{network}/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()

            echoed_id = output.strip().strip('"')
            if echoed_id.startswith("at1"):
                exp_id = extract_tx_id_from_payload(tx)
                if echoed_id != exp_id:
                    print(f"[Exec] Warning: echoed id {echoed_id} != expected {exp_id}")
                else:
                    print(f"[Exec] TX sent : {echoed_id}")
            else:
                print(f"[Exec] Unrecognized TX output: {output} (stderr: {error})")

            results.append(f"Executed {cmd}\nOutput: {output}\nError: {error}")

    return results

def send_deployment_transactions(deploy_paths, expected_deploy_ids, ip_addresses, network,
                                 blocks_before_retry=10, max_retries=5, poll_interval=2, start_event=None):
    print(f"Sending {len(deploy_paths)} deployment transactions with retries "
          f"(retry after {blocks_before_retry} blocks, max {max_retries} retries)")

    num_validators = len(ip_addresses)
    first_ip = ip_addresses[0].strip()

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
        ip = ip_addresses[state["ip_index"]].strip()
        cmd = (
            f"curl http://{ip}:3030/{network}/transaction/broadcast "
            f"-X POST -H \"Content-Type: application/json\" -d '{state['payload']}'"
        )
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode().strip()
        err = result.stderr.decode().strip()

        # Server usually echoes the same id; log mismatch if any (but ID stays fixed).
        echoed = output.strip().strip('"')
        if echoed.startswith("at1") and echoed != state["txid"]:
            print(f"[Deploy] Warning: echoed id {echoed} != expected {state['txid']} (idx {state['idx']})")

        print(f"[Deploy] TX {state['txid']} sent to {ip}")

        try:
            state["last_sent_height"] = get_latest_height(first_ip, network)
        except Exception as e:
            print(f"[Deploy] Warning: cannot fetch latest height after send: {e}")
            state["last_sent_height"] = state["last_sent_height"] or 1
        state["last_checked_height"] = state["last_sent_height"]

        # round-robin next attempt
        state["ip_index"] = (state["ip_index"] + 1) % num_validators

    if start_event and not start_event.is_set():
        start_event.set()

    for st in states:
        broadcast(st)
        time.sleep(2)

    # Manage retries until all confirmed or exhausted
    while True:
        try:
            latest = get_latest_height(first_ip, network)
        except Exception as e:
            print(f"[Deploy] Warning: failed to get latest height: {e}")
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
                print(f"[Deploy] Confirmed {st['txid']} (idx {st['idx']})")
                continue

            # Not seen; retry if enough blocks passed since last send
            if st["last_sent_height"] is not None and latest - st["last_sent_height"] >= blocks_before_retry:
                if st["retries"] < max_retries:
                    st["retries"] += 1
                    print(f"[Deploy] Retry {st['retries']}/{max_retries} for {st['txid']} "
                          f"(no detection in {blocks_before_retry} blocks since {st['last_sent_height']})")
                    broadcast(st)
                    time.sleep(2)
                else:
                    print(f"[Deploy] Gave up after {max_retries} retries for {st['txid']} (idx {st['idx']})")

            if not st["confirmed"] and st["retries"] < max_retries:
                pending += 1

        if pending == 0:
            print("[Deploy] All deployment TXs are either confirmed or exhausted retries.")
            break

        time.sleep(poll_interval)

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

def extract_tx_id_from_payload(s: str) -> str:
    obj = json.loads(s)
    txid = obj.get("id")
    if not (isinstance(txid, str) and txid.startswith("at1")):
        raise ValueError(f"Bad or missing tx id: {txid!r}")
    return txid

def collect_expected_ids(paths):
    ids = []
    for p in paths:
        with open(p, "r") as f:
            payload = f.read().strip()   # each file contains one TX JSON
        ids.append(extract_tx_id_from_payload(payload))
    return ids

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

def main():
    # Error if no argument was passed.
    if len(sys.argv) < 6:
        print("Please provide the network type as 1st argument, the S3 bucket to load transactions from as 2nd and the path in it as 3rd.")
        exit()
    network = sys.argv[1]
    s3_bucket = sys.argv[2]
    s3_prefix = sys.argv[3]
    pregeneration_execution_tx_count = sys.argv[4]
    pregeneration_deployment_tx_count = sys.argv[5]

    ip_addresses_path = os.path.join(os.getcwd(), "..", "..", "ip_addresses.txt")
    if not os.path.exists(ip_addresses_path):
        print(f"Missing ip_addresses.txt file, make sure to run terraform...")
        exit()
    with open(ip_addresses_path, "r") as f:
        ip_addresses = f.readlines()
    num_validators = len(ip_addresses)

    txs_folder = os.path.join(os.getcwd(), "..", "..", "transaction_files")
    download_transaction_files_from_s3(s3_bucket, s3_prefix, txs_folder, network, num_validators, pregeneration_execution_tx_count, pregeneration_deployment_tx_count)

    txs_folder = os.path.join(os.getcwd(), "..", "..", "transaction_files")
    pattern_deploys = re.compile(rf"^deploys-{network}-\d+val-\d+-\d+\.txt$")
    pattern_executions = re.compile(rf"^executions-{network}-\d+val-\d+-\d+\.txt$")

    deploy_files = [
        f for f in os.listdir(txs_folder)
        if pattern_deploys.match(f)
    ]
    exec_files = [
        f for f in os.listdir(txs_folder)
        if pattern_executions.match(f)
    ]
    deploy_files.sort()
    exec_files.sort()

    transactions_split_folder_path = os.path.join(os.getcwd(), "transactions_to_send")
    os.makedirs(transactions_split_folder_path, exist_ok=True)

    deploy_paths, deploy_txs = prepare_transactions(txs_folder, deploy_files, transactions_split_folder_path)
    exec_paths, exec_txs = prepare_transactions(txs_folder, exec_files, transactions_split_folder_path)

    expected_tx_count = len(deploy_txs) + len(exec_txs)
    expected_deploy_ids = collect_expected_ids(deploy_paths)
    expected_exec_ids   = collect_expected_ids(exec_paths)

    tx_ids_sent = set()
    tx_ids_lock = threading.Lock()

    with tx_ids_lock:
        tx_ids_sent.update(expected_deploy_ids)
        tx_ids_sent.update(expected_exec_ids)

    try:
        latest_url = f"http://{ip_addresses[0].strip()}:3030/{network}/block/height/latest"
        latest_resp = requests.get(latest_url, timeout=3)
        latest_height = int(latest_resp.text.strip())
    except Exception as e:
        print(f"Failed to fetch latest block height, defaulting to 1: {e}")
        latest_height = 1

    start = time.time()

    print("Starting block scanner in background...")

    broadcast_started = threading.Event()

    scanner_thread = threading.Thread(
        target=block_scanner,
        args=(ip_addresses[0].strip(), network, expected_tx_count, tx_ids_sent, tx_ids_lock, latest_height),
        kwargs={"max_idle_blocks": 20, "log_path": "confirmed_txs.log", "start_event": broadcast_started},
    )
    scanner_thread.start()

    deploy_thread = threading.Thread(
        target=send_deployment_transactions,
        args=(deploy_paths, expected_deploy_ids, ip_addresses, network),
        kwargs={"blocks_before_retry": 10, "max_retries": 5, "poll_interval": 2, "start_event": broadcast_started},
    )
    deploy_thread.start()

    print(f"Sending {len(exec_paths)} execution transactions")
    with ThreadPoolExecutor(max_workers=num_validators) as exec_pool:
        exec_futures = {
            exec_pool.submit(
                send_transactions,
                exec_paths[i],
                ip_addresses[i % num_validators].strip(),
                network,
                tx_ids_sent,
                tx_ids_lock,
                broadcast_started,  # <-- pass event
            ): i for i in range(len(exec_paths))
        }
        for future in as_completed(exec_futures):
            i = exec_futures[future]
            try:
                _ = future.result()
            except Exception as exc:
                print(f"[Execution] Exception: {exc}")
            else:
                print(f"[Execution] Validator {i % num_validators} completed")

    deploy_thread.join()
    scanner_thread.join()

    end = time.time()
    print(f"Time elapsed: {end - start} seconds")

    if os.path.isdir(txs_folder):
        shutil.rmtree(txs_folder)

    if os.path.isdir(transactions_split_folder_path):
        shutil.rmtree(transactions_split_folder_path, ignore_errors=True)

    print("Block scanning finished.")

if __name__ == '__main__':
    main()
