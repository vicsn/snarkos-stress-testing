import argparse
import json
import os
import subprocess
import threading
import time

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from itertools import cycle

SNARKOS_BIN_PATH = "{{ snarkos_bin_path }}/snarkos"
DATA_FILE = "/home/ubuntu/validator_data/data.json"

def log(msg):
    print(msg, flush=True)

def load_accounts():
    if not os.path.exists(DATA_FILE):
        raise FileNotFoundError(f"{DATA_FILE} not found")
    with open(DATA_FILE, "r") as f:
        return json.load(f).get("accounts", [])

def transfer(sender_pk, receiver_address, network, query_url, broadcast_url, amount):
    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%S%f")
    cmd = [
        "stdbuf", "-oL", "-eL",
        SNARKOS_BIN_PATH, "developer", "execute",
        "--private-key", sender_pk,
        "--query", query_url,
        "--broadcast", broadcast_url,
        "credits.aleo", "transfer_public", receiver_address, f"{amount}u64",
        "--network", str(network)
    ]

    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"

    def stream_and_log(stream, prefix):
        for line in iter(stream.readline, ''):
            if line.strip():
                log(f"[{timestamp}] [{prefix}] {line.strip()}")
        stream.close()

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        stdout_thread = threading.Thread(target=stream_and_log, args=(process.stdout, "snarkos stdout"))
        stderr_thread = threading.Thread(target=stream_and_log, args=(process.stderr, "snarkos stderr"))

        stdout_thread.start()
        stderr_thread.start()

        process.wait()
        stdout_thread.join()
        stderr_thread.join()
    except Exception as e:
        log(f"[{timestamp}] Transfer failed from {sender_pk} to {receiver_address}: {e}")

def main():
    parser = argparse.ArgumentParser(description="Batch transfer Aleo microcredits")
    parser.add_argument("--senders", type=int, default=1, help="Number of senders (private keys)")
    parser.add_argument("--receivers", type=int, default=1, help="Number of receivers")
    parser.add_argument("--wait", type=int, default=200, help="Wait time in milliseconds between transactions")
    parser.add_argument("--network", type=int, required=True, help="Network: 0 = mainnet, 1 = testnet, 2 = canary")
    parser.add_argument("--endpoint", type=str, required=True, help="Base endpoint for query and broadcast")
    parser.add_argument("--amount", type=int, default=100, help="Amount in microcredits")
    parser.add_argument("--repetitions", type=int, default=0, help="Number of repetitions per sender (0 = infinite)")

    args = parser.parse_args()

    accounts = load_accounts()
    if len(accounts) < args.senders + args.receivers:
        raise ValueError(f"Need at least {args.senders + args.receivers} accounts in {DATA_FILE}")

    private_keys = [acc["private_key"] for acc in accounts[:args.senders]]
    receiver_addresses = [acc["address"] for acc in accounts[args.senders:args.senders + args.receivers]]

    pk_iterator = cycle(private_keys)
    addr_iterator = cycle(receiver_addresses)

    network_map = {0: "mainnet", 1: "testnet", 2: "canary"}
    if args.network not in network_map:
        raise ValueError(f"Invalid network: {args.network}")

    network_str = network_map[args.network]
    query_url = args.endpoint
    broadcast_url = f"{args.endpoint.rstrip('/')}/{network_str}/transaction/broadcast"

    executor = ThreadPoolExecutor(max_workers=args.senders)
    futures = []
    count = 0

    try:
        while args.repetitions == 0 or count < args.repetitions * args.senders:
            for _ in range(args.senders):
                sender_pk = next(pk_iterator)
                receiver_addr = next(addr_iterator)
                futures.append(executor.submit(
                    transfer, sender_pk, receiver_addr, args.network,
                    query_url, broadcast_url, args.amount
                ))
                count += 1
                if args.repetitions != 0 and count >= args.repetitions * args.senders:
                    break

            for f in as_completed(futures):
                try:
                    f.result()
                except Exception as e:
                    log(f"Transfer task crashed: {e}")
            futures.clear()

            if args.wait > 0:
                time.sleep(args.wait / 1000.0)

    except KeyboardInterrupt:
        log("Interrupted by user. Shutting down.")
    finally:
        executor.shutdown(wait=True)

if __name__ == "__main__":
    main()
