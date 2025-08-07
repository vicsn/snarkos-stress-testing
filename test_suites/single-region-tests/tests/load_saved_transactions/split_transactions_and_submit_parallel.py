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

# === inside block_scanner ===

def block_scanner(ip_address, network, expected_tx_count, tx_ids_sent, tx_ids_lock, start_height=1, poll_interval=2, max_idle_blocks=20, log_path="confirmed_txs.log"):
    checked_height = start_height
    seen_tx_ids = set()
    matched_tx_ids = set()
    idle_blocks = 0

    def log_unconfirmed_summary(reason):
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
                new_block_with_transactions_processed = False

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

                    if transactions:
                        new_block_with_transactions_processed = True

                    log_line = f"Block {block_height} with {len(transactions)} transaction(s)"
                    print(log_line)
                    log.write(log_line + "\n")
                    log.flush()

                    new_tx_ids = {tx["transaction"]["id"] for tx in transactions}
                    seen_tx_ids.update(new_tx_ids)

                    with tx_ids_lock:
                        newly_matched = new_tx_ids.intersection(tx_ids_sent) - matched_tx_ids
                        for tx_id in newly_matched:
                            msg = f"TX {tx_id} confirmed in block {block_height}"
                            print(msg)
                            log.write(msg + "\n")
                            log.flush()
                        matched_tx_ids.update(newly_matched)

                    checked_height += 1

                if new_block_with_transactions_processed:
                    idle_blocks = 0
                else:
                    idle_blocks += 1

                if len(matched_tx_ids) >= expected_tx_count:
                    print("All expected transactions confirmed.")
                    log.write("\nAll expected transactions confirmed.\n")
                    log.flush()
                    return

                if idle_blocks >= max_idle_blocks:
                    with tx_ids_lock:
                        remaining = tx_ids_sent - matched_tx_ids
                    print(f"Stopped scanning after {max_idle_blocks} idle blocks. Unconfirmed TXs: {remaining}")
                    log.write(f"\nStopped scanning after {max_idle_blocks} idle blocks.\n")
                    log_unconfirmed_summary("max_idle_blocks reached")
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
                log_unconfirmed_summary("fatal_exception")
                return


# Function to send transactions to a validator without surpassing the rate limit.
def send_transactions(transactions_path, ip_address, network, tx_ids_sent, tx_ids_lock):
    print(f"[Validator @ {ip_address}] Starting transaction broadcast from {transactions_path}")

    results = []

    with open(transactions_path, "r") as f:
        for i, tx in enumerate(f.readlines()):
            # On every 20 transactions send wait a bit before sending the next batch to not flood
            if i % 20 == 0:
                time.sleep(1)

            cmd = f"curl http://{ip_address}:3030/{network}/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()

            try:
                tx_id = output.strip().strip('"')
                print(f"TX sent : {tx_id}")

                with tx_ids_lock:
                    if tx_id.startswith("at1"):
                        tx_ids_sent.add(tx_id)
                    else:
                        # Mark it with a dummy label so it's counted but distinguishable
                        tx_ids_sent.add(f"unparsed::{i}")
                        print(f"Unrecognized TX output: {output}")
            except Exception as e:
                with tx_ids_lock:
                    tx_ids_sent.add(f"error::{i}")
                print(f"Exception parsing TX ID from: {output} — {e}")

            results.append(f"Executed {cmd}\nOutput: {output}\nError: {error}")

    return results

def send_deployment_transactions(deploy_paths, ip_addresses, network, tx_ids_sent, tx_ids_lock):
    print(f"Sending {len(deploy_paths)} deployment transactions (1 per second)")

    num_validators = len(ip_addresses)
    for i, path in enumerate(deploy_paths):
        ip_address = ip_addresses[i % num_validators].strip()

        try:
            with open(path, "r") as f:
                tx = f.read().strip()

            cmd = f"curl http://{ip_address}:3030/{network}/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()

            tx_id = output.strip().strip('"')
            print(f"[Deploy] TX sent: {tx_id} to {ip_address}")

            with tx_ids_lock:
                if tx_id.startswith("at1"):
                    tx_ids_sent.add(tx_id)
                else:
                    tx_ids_sent.add(f"unparsed::{i}")
                    print(f"[Deploy] Unrecognized TX output: {output}")
        except Exception as e:
            with tx_ids_lock:
                tx_ids_sent.add(f"error::{i}")
            print(f"[Deploy] Exception for deployment TX {i}: {e}")

        # After each deployment transaction wait 1 sec, so we don't have the problem that one block receives multiple
        # deployment txs from the same account.
        time.sleep(1)

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
    tx_ids_sent = set()
    tx_ids_lock = threading.Lock()

    try:
        latest_url = f"http://{ip_addresses[0].strip()}:3030/{network}/block/height/latest"
        latest_resp = requests.get(latest_url, timeout=3)
        latest_height = int(latest_resp.text.strip())
    except Exception as e:
        print(f"Failed to fetch latest block height, defaulting to 1: {e}")
        latest_height = 1

    start = time.time()

    print("Starting block scanner in background...")

    scanner_thread = threading.Thread(
        target=block_scanner,
        args=(
            ip_addresses[0].strip(),
            network,
            expected_tx_count,
            tx_ids_sent,
            tx_ids_lock,
            latest_height,
        ),
        kwargs={"max_idle_blocks": 20},
    )
    scanner_thread.start()

    deploy_thread = threading.Thread(
        target=send_deployment_transactions,
        args=(deploy_paths, ip_addresses, network, tx_ids_sent, tx_ids_lock),
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
                tx_ids_lock
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

    print("Block scanning finished.")

if __name__ == '__main__':
    main()
