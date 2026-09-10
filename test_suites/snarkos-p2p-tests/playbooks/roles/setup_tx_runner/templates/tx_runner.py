import os
import aiohttp
import asyncio
import json
import logging
import requests
import subprocess
import sys

from random import shuffle
from typing import List

ALLOWED_COMMANDS = {"snarkos", "program-probe", "batch-deploy", "batch-transfer"}

TASK_FILE = "/home/ubuntu/tasks.json"
MAX_CONCURRENT_TASKS = 5

BLOCK_SCAN_INTERVAL = 5
PROGRAM_CALLER_IDLE_DURATION = 1

SNARKOS_BIN_PATH = "{{ snarkos_bin_path }}/snarkos"

REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT", "5"))
CONSENSUS_POLL_INTERVAL_SEC = 5

LATEST_CONSENSUS_VERSION_ENV = os.getenv("LATEST_CONSENSUS_VERSION")
if LATEST_CONSENSUS_VERSION_ENV is None:
    log_error("ERROR: Missing required env: LATEST_CONSENSUS_VERSION")
    sys.exit(2)
LATEST_CONSENSUS_VERSION = int(LATEST_CONSENSUS_VERSION_ENV)

IP_ADDRESS = os.getenv("BLOCK_SCANNER_IP")
NETWORK = os.getenv("BLOCK_SCANNER_NETWORK")

batch_deploy_process = None
program_probe_running = False

logging.basicConfig(
    level=logging.INFO,
    stream=sys.stdout,
    format="%(levelname)s:%(name)s:%(message)s"
)
logger = logging.getLogger("tx_runner")

task_queue = asyncio.Queue()
semaphore = asyncio.Semaphore(MAX_CONCURRENT_TASKS)

# --- HTTP helpers ---
def get_consensus_version(ip_address: str, network: str, timeout: float = REQUEST_TIMEOUT) -> int:
    url = f"http://{ip_address}:3030/{network}/consensus_version"
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return int(r.text.strip())

async def wait_until_consensus_ready(
    ip_address: str,
    network: str,
    min_version: int,
    poll_interval_sec: int = CONSENSUS_POLL_INTERVAL_SEC,
    request_timeout: float = REQUEST_TIMEOUT,
):
    """Poll /consensus_version until it reaches >= min_version."""
    if not ip_address or not network:
        logger.error("Missing BLOCK_SCANNER_IP or BLOCK_SCANNER_NETWORK env; cannot wait for consensus.")
        sys.exit(2)

    url = f"http://{ip_address}:3030/{network}/consensus_version"
    logger.info(f"Waiting for consensus_version >= {min_version} at {url} ...")

    async with aiohttp.ClientSession() as session:
        while True:
            try:
                async with session.get(url, timeout=request_timeout) as resp:
                    text = await resp.text()
                    version = int(text.strip())
                    if version >= min_version:
                        logger.info(f"Consensus version {version} reached (>= {min_version}), continuing.")
                        return
                    else:
                        logger.info(f"Consensus version {version} < {min_version}; retrying in {poll_interval_sec}s...")
            except Exception as e:
                logger.warning(f"Consensus version check failed: {e}")

            await asyncio.sleep(poll_interval_sec)

async def run_task(command: List[str]):
    async with semaphore:
        try:
            logger.info(f"Running: {' '.join(command)}")
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await process.communicate()
            logger.info(f"Finished: {' '.join(command)}\n{stdout.decode()}\n{stderr.decode()}")
        except Exception as e:
            logger.error(f"Task failed: {e}")

async def task_worker():
    while True:
        command = await task_queue.get()

        if not command or command[0] not in ALLOWED_COMMANDS:
            logger.warning(f"Skipping unsupported command: {command}")
            task_queue.task_done()
            continue

        if command[0] == "snarkos":
            command[0] = SNARKOS_BIN_PATH
            asyncio.create_task(run_task(command))

        elif command[0] == "program-probe":
            global program_probe_running
            if program_probe_running:
                logger.info("program-probe already running, skipping duplicate")
            else:
                program_probe_running = True
                logger.info(f"Starting program-probe with args: {command[1:]}")
                asyncio.create_task(program_probe_task(command[1:]))

        elif command[0] == "batch-deploy":
            global batch_deploy_process
            if batch_deploy_process and batch_deploy_process.returncode is None:
                logger.info("batch-deploy is already running, skipping duplicate")
            else:
                logger.info(f"Starting batch-deploy with args: {command[1:]}")
                asyncio.create_task(monitor_batch_deploy(command[1:]))

        elif command[0] == "batch-transfer":
            logger.info(f"Starting batch-transfer with args: {command[1:]}")
            asyncio.create_task(monitor_batch_transfer(command[1:]))

        task_queue.task_done()

def load_initial_tasks():
    try:
        with open(TASK_FILE) as f:
            tasks = json.load(f)
            for task in tasks:
                command = task.get("command")
                if command:
                    asyncio.create_task(task_queue.put(command))
                    logger.info(f"Preloaded task: {command}")
    except FileNotFoundError:
        logger.warning(f"No task file found at {TASK_FILE}")

async def extract_program_name(program_code: str) -> str | None:
    for line in program_code.splitlines():
        if line.strip().lower().startswith("program "):
            tokens = line.strip().split()
            if len(tokens) >= 2:
                return tokens[1].rstrip(";")
    return None

async def program_probe_task(args: List[str]):
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--network", default="mainnet")
    parser.add_argument("--randomize", action="store_true")
    parser.add_argument("--wait", type=int, default=0)

    opts = parser.parse_args(args)

    await program_probe(
        endpoint=opts.endpoint,
        network=opts.network,
        randomize=opts.randomize,
        wait_ms=opts.wait
    )

async def program_probe(endpoint: str, network: str, randomize: bool = False, wait_ms: int = 0):
    logger.info("Starting program probe")
    discovered_programs = set()
    last_height = 0

    async with aiohttp.ClientSession() as session:
        while True:
            try:
                height_url = f"{endpoint}/{network}/block/height/latest"
                async with session.get(height_url) as resp:
                    current_height = await resp.json()

                if current_height >= last_height:
                    for height in range(last_height, current_height + 1):
                        block_url = f"{endpoint}/{network}/block/{height}"
                        async with session.get(block_url) as resp:
                            if resp.status != 200:
                                logger.warning(f"Failed to fetch block {height}: HTTP {resp.status}")
                                continue
                            block = await resp.json()

                        txs = block.get("transactions", [])
                        deploy_txs = [tx for tx in txs if tx.get("type") == "deploy"]

                        for tx in deploy_txs:
                            inner = tx.get("transaction")
                            if not inner:
                                continue
                            deployment = inner.get("deployment")
                            if not deployment:
                                continue
                            prog_code = deployment.get("program", "")
                            prog_name = await extract_program_name(prog_code)
                            if prog_name and prog_name not in discovered_programs:
                                discovered_programs.add(prog_name)
                                logger.info(f"Discovered new program: {prog_name}")

                    last_height = current_height + 1

                prog_list = list(discovered_programs)
                if randomize:
                    shuffle(prog_list)
                for prog in prog_list:
                    url = f"{endpoint}/{network}/program/{prog}"
                    async with session.get(url) as resp:
                        if resp.status == 200:
                            logger.info(f"Called program endpoint: {prog}")
                        else:
                            logger.warning(f"Failed to call {prog}: HTTP {resp.status}")
                    await asyncio.sleep(wait_ms / 1000)

            except Exception as e:
                logger.error(f"Program probe error: {e}")

            await asyncio.sleep(BLOCK_SCAN_INTERVAL)

async def stream_output(stream, logfile):
    with open(logfile, "ab") as f:
        while True:
            line = await stream.readline()
            if not line:
                break
            f.write(line)
            f.flush()

async def monitor_batch_deploy(args: List[str]):
    global batch_deploy_process
    while True:
        try:
            cmd = ["/home/ubuntu/venv/bin/python3", "/home/ubuntu/batch_deploy.py"] + args
            logger.info(f"Launching batch-deploy: {' '.join(cmd)}")

            batch_deploy_process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            await asyncio.gather(
                stream_output(batch_deploy_process.stdout, "tx_runner_deployments.log"),
                stream_output(batch_deploy_process.stderr, "tx_runner_deployments.err.log"),
            )

            logger.warning(f"batch-deploy exited with code {batch_deploy_process.returncode}. Restarting...")

        except Exception as e:
            logger.error(f"batch-deploy crashed: {e}")

        await asyncio.sleep(2)

async def monitor_batch_transfer(args: List[str]):
    while True:
        try:
            cmd = ["/home/ubuntu/venv/bin/python3", "/home/ubuntu/batch_transfer.py"] + args
            logger.info(f"Launching batch-transfer: {' '.join(cmd)}")

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            await asyncio.gather(
                stream_output(process.stdout, "tx_runner_transfers.log"),
                stream_output(process.stderr, "tx_runner_transfers.err.log"),
            )

            logger.warning(f"batch-transfer exited with code {process.returncode}. Restarting...")

        except Exception as e:
            logger.error(f"batch-transfer crashed: {e}")

        await asyncio.sleep(2)

async def main():
    # Wait for consensus version BEFORE starting workers/tasks
    await wait_until_consensus_ready(
        ip_address=IP_ADDRESS,
        network=NETWORK,
        min_version=LATEST_CONSENSUS_VERSION,
    )

    load_initial_tasks()
    asyncio.create_task(task_worker())
    await asyncio.Event().wait()

if __name__ == "__main__":
    asyncio.run(main())

