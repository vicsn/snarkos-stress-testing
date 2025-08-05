import aiohttp
import asyncio
import json
import logging
import subprocess
import uvicorn

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from random import shuffle
from typing import List

ALLOWED_COMMANDS = {"snarkos", "program-probe"}

TASK_FILE = "/home/ubuntu/tasks.json"
MAX_CONCURRENT_TASKS = 5

BLOCK_SCAN_INTERVAL = 5
PROGRAM_CALLER_IDLE_DURATION = 1

SNARKOS_BIN_PATH="{{ snarkos_bin_path }}/snarkos"

program_probe_running = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tx_runner")

task_queue = asyncio.Queue()
app = FastAPI()

semaphore = asyncio.Semaphore(MAX_CONCURRENT_TASKS)

class Task(BaseModel):
    command: List[str]


@app.post("/task")
async def enqueue_task(task: Task):
    logger.info(f"Received new task: {task.command}")
    await task_queue.put(task.command)

    return {"status": "queued"}

@app.get("/status")
async def queue_status():
    return {"queue_size": task_queue.qsize()}

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

                # Now call each discovered program
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


async def main():
    load_initial_tasks()

    asyncio.create_task(task_worker())

    config = uvicorn.Config(app, host="0.0.0.0", port=3030, log_level="info")
    server = uvicorn.Server(config)

    await server.serve()


if __name__ == "__main__":
    asyncio.run(main())
