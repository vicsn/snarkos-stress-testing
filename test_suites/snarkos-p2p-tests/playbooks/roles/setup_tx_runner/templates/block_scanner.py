#!/usr/bin/env python3
import os
import sys
import time
import json
import requests
import signal
import threading

from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

def log_info(msg: str):
    print(f"[info] {msg}", file=sys.stderr, flush=True)

def log_warn(msg: str):
    print(f"[warn] {msg}", file=sys.stderr, flush=True)

def log_error(msg: str):
    print(f"[error] {msg}", file=sys.stderr, flush=True)

def _get_arg_or_env(idx: int, env_key: str, default: Optional[str] = None) -> str:
    if len(sys.argv) > idx:
        return sys.argv[idx]
    v = os.getenv(env_key, default)
    if v is None:
        log_error(f"ERROR: Missing required arg/env: {env_key}")
        sys.exit(2)
    return v

IP_ADDRESS = _get_arg_or_env(1, "BLOCK_SCANNER_IP")
NETWORK    = _get_arg_or_env(2, "BLOCK_SCANNER_NETWORK")

REQUEST_TIMEOUT      = float(os.getenv("BLOCK_SCANNER_TIMEOUT", "5"))
CATCHUP_DELAY_SEC    = float(os.getenv("BLOCK_SCANNER_CATCHUP_DELAY_SEC", "0.2"))
IDLE_DELAY_SEC       = float(os.getenv("BLOCK_SCANNER_IDLE_DELAY_SEC", "5"))
START_HEIGHT         = int(os.getenv("BLOCK_SCANNER_START_HEIGHT", "0"))
MAX_BACKOFF_SEC      = float(os.getenv("BLOCK_SCANNER_MAX_BACKOFF_SEC", "5"))

# New tunables
MAX_FETCH_ATTEMPTS        = int(os.getenv("BLOCK_SCANNER_MAX_FETCH_ATTEMPTS", "20"))
SKIP_HTTP_STATUSES        = {int(s) for s in os.getenv("BLOCK_SCANNER_SKIP_STATUSES", "500,502,503,504").split(",")}
REVISIT_BATCH_PER_IDLE    = int(os.getenv("BLOCK_SCANNER_REVISIT_BATCH_PER_IDLE", "10"))
HEARTBEAT_SEC             = float(os.getenv("BLOCK_SCANNER_HEARTBEAT_SEC", "30"))

LATEST_CONSENSUS_VERSION  = int(_get_arg_or_env(3, "LATEST_CONSENSUS_VERSION"))

# --- Graceful shutdown ---
_shutdown = threading.Event()
def _handle_signal(signum, frame):
    _shutdown.set()
signal.signal(signal.SIGINT, _handle_signal)
signal.signal(signal.SIGTERM, _handle_signal)

# --- HTTP helpers ---
def http_get(url: str, timeout: float) -> requests.Response:
    return requests.get(url, timeout=timeout)

def get_latest_height(ip_address: str, network: str, timeout: float = REQUEST_TIMEOUT) -> int:
    url = f"http://{ip_address}:3030/{network}/block/height/latest"
    r = http_get(url, timeout=timeout)
    r.raise_for_status()
    return int(r.text.strip())

def get_block(ip_address: str, network: str, height: int, timeout: float = REQUEST_TIMEOUT) -> Dict[str, Any]:
    url = f"http://{ip_address}:3030/{network}/block/{height}"
    r = http_get(url, timeout=timeout)
    r.raise_for_status()
    return r.json()

def get_consensus_version(ip_address: str, network: str, timeout: float = REQUEST_TIMEOUT) -> int:
    url = f"http://{ip_address}:3030/{network}/consensus_version"
    r = http_get(url, timeout=timeout)
    r.raise_for_status()
    return int(r.text.strip())

# --- Parsing helpers ---
def iter_solutions(block: Dict[str, Any]) -> Iterable[Dict[str, Any]]:
    """
    Yields dicts with keys 'solution_id' and 'target'
    Expected structure:
      block['solutions']['solutions']['solutions'] -> list of entries with:
        {'partial_solution': {'solution_id': ...}, 'target': ...}
    """
    try:
        root = block.get("solutions") or {}
        inner = root.get("solutions") or {}
        arr = inner.get("solutions") or []
        for item in arr:
            ps = (item or {}).get("partial_solution") or {}
            sid = ps.get("solution_id")
            tgt = item.get("target")
            if sid is not None and tgt is not None:
                yield {"solution_id": sid, "target": tgt}
    except Exception as e:
        log_error(f"solutions parse error: {e}")

def iter_aborted_solutions(block: Dict[str, Any]) -> Iterable[str]:
    try:
        arr = block.get("aborted_solution_ids") or []
        if isinstance(arr, list):
            for sid in arr:
                if isinstance(sid, str):
                    yield sid
    except Exception as e:
        log_error(f"aborted_solutions parse error: {e}")

def iter_transactions(block: Dict[str, Any]) -> Iterable[Dict[str, Any]]:
    """
    Yields dicts with keys 'id' and 'type'
    Accepts:
      block['transactions'] = [{"transaction": {"id": ..., "type": ...}}, ...]
      or {"transactions": {"transactions": [...]}}
    """
    try:
        txs = block.get("transactions")
        if isinstance(txs, dict):
            txs = txs.get("transactions")
        if not isinstance(txs, list):
            return
        for entry in txs:
            tx = (entry or {}).get("transaction") or {}
            tx_id = tx.get("id")
            tx_type = tx.get("type")
            if tx_id is not None and tx_type is not None:
                yield {"id": tx_id, "type": tx_type}
    except Exception as e:
        log_error(f"transactions parse error: {e}")

# --- Validation ---
def validate_block(block: Any, expected_height: int) -> Tuple[bool, str]:
    """
    Basic structural validation. Returns (ok, reason_if_not_ok).
    We keep it tolerant: only ensure it's a dict with header.metadata.height and
    that 'solutions' and 'transactions' (if present) are of acceptable shapes.
    """
    if not isinstance(block, dict):
        return False, "not a JSON object"
    header = block.get("header")
    if not isinstance(header, dict):
        return False, "missing header"
    metadata = header.get("metadata")
    if not isinstance(metadata, dict):
        return False, "missing header.metadata"
    height = metadata.get("height")
    if not isinstance(height, int):
        return False, "metadata.height not an int"

    # Optional: ensure node didn't return mismatched block for requested height
    if height != expected_height:
        # Not strictly an error in some nodes, but we flag it for awareness and process anyway.
        log_warn(f"block height mismatch: expected={expected_height}, got={height}")

    # Validate transactions shape if present
    txs = block.get("transactions", None)
    if txs is not None and not (
        isinstance(txs, list) or (isinstance(txs, dict) and isinstance(txs.get("transactions"), list))
    ):
        return False, "transactions malformed"

    # Validate solutions shape if present
    sol_root = block.get("solutions", None)
    if sol_root is not None:
        if not isinstance(sol_root, dict):
            return False, "solutions root not a dict"
        inner = sol_root.get("solutions")
        if inner is not None and not isinstance(inner, dict):
            return False, "solutions.inner not a dict"
        if isinstance(inner, dict):
            arr = inner.get("solutions", None)
            if arr is not None and not isinstance(arr, list):
                return False, "solutions list not a list"

    # Aborted solutions list, if present
    aborted = block.get("aborted_solution_ids", None)
    if aborted is not None and not isinstance(aborted, list):
        return False, "aborted_solution_ids not a list"

    return True, ""

# --- Backoff helper ---
def backoff_sleep(attempt: int):
    delay = min(0.5 * (2 ** (attempt - 1)), MAX_BACKOFF_SEC)
    time.sleep(delay)

# --- Main loop ---
def main():
    checked_height = START_HEIGHT
    skipped: Set[int] = set()
    last_heartbeat = time.monotonic()

    # --- Wait until consensus version is >= LATEST_CONSENSUS_VERSION ---
    log_info(f"Waiting for consensus_version >= {LATEST_CONSENSUS_VERSION} ...")
    while not _shutdown.is_set():
        try:
            current_version = get_consensus_version(IP_ADDRESS, NETWORK)
            if current_version >= LATEST_CONSENSUS_VERSION:
                log_info(f"Consensus version {current_version} reached (>= {LATEST_CONSENSUS_VERSION}), continuing.")
                break
            else:
                log_info(f"Consensus version {current_version} < {LATEST_CONSENSUS_VERSION}, waiting 5s...")
        except Exception as e:
            log_warn(f"Consensus version check failed: {e}")
        time.sleep(5)

    # Initial latest height (with retry/backoff)
    attempt = 1
    while not _shutdown.is_set():
        try:
            latest_height = get_latest_height(IP_ADDRESS, NETWORK)
            break
        except Exception as e:
            log_warn(f"Call to get_latest_height failed (attempt {attempt}): {e}")
            backoff_sleep(attempt)
            attempt += 1
    else:
        return

    while not _shutdown.is_set():
        # Heartbeat
        now = time.monotonic()
        if now - last_heartbeat >= HEARTBEAT_SEC:
            log_info(f"heartbeat: checked={checked_height}, latest={latest_height}, skipped={len(skipped)}")
            last_heartbeat = now

        # Catch up: scan from checked_height up to latest_height (inclusive)
        while not _shutdown.is_set() and checked_height <= latest_height:
            fetch_attempt = 1
            block: Optional[Dict[str, Any]] = None

            while not _shutdown.is_set():
                try:
                    block = get_block(IP_ADDRESS, NETWORK, checked_height)
                    break  # success
                except requests.HTTPError as he:
                    status = he.response.status_code if he.response is not None else None
                    log_warn(f"Block {checked_height} HTTP {status} (attempt {fetch_attempt}): {he}")
                    # Decide to skip after N attempts, for certain statuses
                    if fetch_attempt >= MAX_FETCH_ATTEMPTS and (status in SKIP_HTTP_STATUSES or status is None):
                        log_warn(f"[skip] height {checked_height} after {fetch_attempt} attempts (status {status}); will revisit later")
                        skipped.add(checked_height)
                        block = None
                        break
                    backoff_sleep(fetch_attempt)
                    fetch_attempt += 1
                except (requests.RequestException, ValueError, json.JSONDecodeError) as e:
                    log_warn(f"Block {checked_height} fetch failed (attempt {fetch_attempt}): {e}")
                    if fetch_attempt >= MAX_FETCH_ATTEMPTS:
                        log_warn(f"[skip] height {checked_height} after {fetch_attempt} attempts (exception); will revisit later")
                        skipped.add(checked_height)
                        block = None
                        break
                    backoff_sleep(fetch_attempt)
                    fetch_attempt += 1

            # If skipped due to fetch error, advance; otherwise process
            if block is not None:
                ok, reason = validate_block(block, expected_height=checked_height)
                if not ok:
                    log_error(f"Block {checked_height} malformed: {reason}. Skipping and will revisit.")
                    skipped.add(checked_height)
                else:
                    # Process
                    for sol in iter_solutions(block):
                        print(f"[solution] {sol['solution_id']} {sol['target']}", flush=True)
                    for tx in iter_transactions(block):
                        print(f"[transaction] {tx['id']} {tx['type']}", flush=True)
                    for sid in iter_aborted_solutions(block):
                        print(f"[aborted_solution] {sid}", flush=True)

            checked_height += 1

            if not _shutdown.is_set():
                time.sleep(CATCHUP_DELAY_SEC)

        if _shutdown.is_set():
            break

        # Idle: reached latest height — revisit some skipped heights
        if skipped:
            revisit = sorted(skipped)[:REVISIT_BATCH_PER_IDLE]
            for h in revisit:
                if _shutdown.is_set():
                    break
                try:
                    block = get_block(IP_ADDRESS, NETWORK, h)
                    ok, reason = validate_block(block, expected_height=h)
                    if not ok:
                        log_error(f"[revisit-malformed] height {h}: {reason}")
                        continue
                    # Success: process and drop from skipped
                    for sol in iter_solutions(block):
                        print(f"[solution] {sol['solution_id']} {sol['target']}", flush=True)
                    for tx in iter_transactions(block):
                        print(f"[transaction] {tx['id']} {tx['type']}", flush=True)
                    for sid in iter_aborted_solutions(block):
                        print(f"[aborted_solution] {sid}", flush=True)
                    skipped.discard(h)
                    log_info(f"[revisit-ok] height {h}")
                except Exception as e:
                    log_warn(f"[revisit-fail] height {h}: {e}")

        # Wait, then refresh latest height (with retry/backoff)
        time.sleep(IDLE_DELAY_SEC)

        attempt = 1
        while not _shutdown.is_set():
            try:
                latest_height = get_latest_height(IP_ADDRESS, NETWORK)
                # Handle chain reset (e.g., tests restart network)
                if latest_height < checked_height:
                    log_warn(f"latest height {latest_height} < checked {checked_height}; adjusting cursor")
                    checked_height = latest_height
                break
            except Exception as e:
                log_warn(f"Call to get_latest_height failed (attempt {attempt}): {e}")
                backoff_sleep(attempt)
                attempt += 1

    log_info("Shutting down.")

if __name__ == "__main__":
    main()

