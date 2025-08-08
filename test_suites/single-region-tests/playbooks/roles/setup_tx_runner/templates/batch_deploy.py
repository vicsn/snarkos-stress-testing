import argparse
import json
import os
import shutil
import subprocess
import threading
import time

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from itertools import cycle

SNARKOS_BIN_PATH = "{{ snarkos_bin_path }}/snarkos"
DATA_FILE = "/home/ubuntu/validator_data/data.json"

def log(msg):
    print(msg, flush=True)  # Ensure it flushes and goes to stdout

def load_private_keys(senders_count):
    if not os.path.exists(DATA_FILE):
        raise FileNotFoundError(f"{DATA_FILE} not found")

    with open(DATA_FILE, "r") as f:
        data = json.load(f)

    accounts = data.get("accounts", [])
    if len(accounts) < senders_count:
        raise ValueError(f"Only {len(accounts)} accounts available, but {senders_count} senders requested")

    return [acc["private_key"] for acc in accounts[:senders_count]]


def deploy_program(private_key, network, program_name, query_url, broadcast_url):
    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%S%f")
    base_program = os.path.splitext(program_name)[0]
    unique_program_name = f"p{timestamp.lower()}_{base_program}"
    program_filename = f"{base_program}.aleo"

    deployments_dir = "/home/ubuntu/deployments"
    os.makedirs(deployments_dir, exist_ok=True)

    program_src_path = f"/home/ubuntu/programs/{program_filename}"
    deployment_path = os.path.join(deployments_dir, unique_program_name)
    os.makedirs(deployment_path, exist_ok=True)

    main_aleo_path = os.path.join(deployment_path, "main.aleo")
    program_json_path = os.path.join(deployment_path, "program.json")

    try:
        # Read and rewrite the program
        with open(program_src_path, "r") as f:
            program_contents = f.read()

        rewritten = program_contents.replace(program_filename, f"{unique_program_name}.aleo")
        rewritten = rewritten.replace("<program>", f"{unique_program_name}.aleo")

        with open(main_aleo_path, "w") as f:
            f.write(rewritten)

        # Write program.json
        program_metadata = {
            "program": f"{unique_program_name}.aleo",
            "version": "0.0.0",
            "description": "",
            "license": "MIT"
        }

        with open(program_json_path, "w") as f:
            json.dump(program_metadata, f)

        # Call snarkos
        cmd = [
            "stdbuf", "-oL", "-eL",
            SNARKOS_BIN_PATH, "developer", "deploy",
            "--private-key", private_key,
            "--query", query_url,
            "--priority-fee", "1",
            "--network", str(network),
            "--broadcast", broadcast_url,
            "--path", deployment_path,
            f"{unique_program_name}.aleo"
        ]

        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"

        def stream_and_log(stream, prefix, timestamp):
            for line in iter(stream.readline, ''):
                if line.strip():
                    log(f"[{timestamp}] [{prefix}] {line.strip()}")
            stream.close()

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
            env=env,
        )
        stdout_thread = threading.Thread(target=stream_and_log, args=(process.stdout, "snarkos stdout", timestamp))
        stderr_thread = threading.Thread(target=stream_and_log, args=(process.stderr, "snarkos stderr", timestamp))

        stdout_thread.start()
        stderr_thread.start()

        process.wait()
        stdout_thread.join()
        stderr_thread.join()

    except Exception as e:
        log(f"[{timestamp}] Deployment failed for {unique_program_name}: {e}")

    finally:
        try:
            shutil.rmtree(deployment_path)
        except Exception as e:
            log(f"[{timestamp}] Failed to clean up {deployment_path}: {e}")


def main():
    parser = argparse.ArgumentParser(description="Batch deploy Aleo programs using snarkos")

    parser.add_argument("program_name", type=str, help="Name of the Aleo program")
    parser.add_argument("--senders", type=int, required=True, help="Number of senders (private keys)")
    parser.add_argument("--redeploys", type=int, default=0, help="Number of redeployments (0 = infinite)")
    parser.add_argument("--concurrent-deployments", type=int, default=None, help="Max concurrent deployments")
    parser.add_argument("--network", type=int, required=True, help="Network: 0 = mainnet, 1 = testnet, 2 = canary")
    parser.add_argument("--endpoint", type=str, required=True, help="Base endpoint for query and broadcast")
    parser.add_argument("--wait", type=int, default=1000, help="Wait time in milliseconds between deployment batches")

    args = parser.parse_args()

    concurrent = args.concurrent_deployments or args.senders
    if concurrent > args.senders:
        raise ValueError("Concurrent deployments cannot exceed number of senders")

    network_map = {0: "mainnet", 1: "testnet", 2: "canary"}
    if args.network not in network_map:
        raise ValueError(f"Invalid network: {args.network}")

    network_str = network_map[args.network]
    query_url = args.endpoint
    broadcast_url = f"{args.endpoint.rstrip('/')}/{network_str}/transaction/broadcast"

    private_keys = load_private_keys(args.senders)
    pk_iterator = cycle(private_keys)

    executor = ThreadPoolExecutor(max_workers=concurrent)
    futures = []

    count = 0
    try:
        while args.redeploys == 0 or count < args.redeploys * args.senders:
            for _ in range(concurrent):
                pk = next(pk_iterator)
                futures.append(executor.submit(
                    deploy_program,
                    pk,
                    args.network,
                    args.program_name,
                    query_url,
                    broadcast_url
                ))
                count += 1
                if args.redeploys != 0 and count >= args.redeploys * args.senders:
                    break

            for f in as_completed(futures):
                try:
                    f.result()
                except Exception as e:
                    log(f"Deployment task crashed: {e}")
            futures.clear()

            if args.wait > 0:
                time.sleep(args.wait / 1000.0)

    except KeyboardInterrupt:
        log("Interrupted by user. Shutting down.")
    finally:
        executor.shutdown(wait=True)


if __name__ == "__main__":
    main()
