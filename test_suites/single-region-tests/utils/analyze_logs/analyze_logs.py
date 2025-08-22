#!/usr/bin/env python3
import os
import sys
import re
import gzip
import tarfile
import json
from typing import Dict, Set, Tuple, Optional

PROVER_ARCHIVE = "../../log_files/prover-0.log.gz"
TXRUNNER_ARCHIVE = "../../log_files/tx_runner.logs.gz"
OUTPUT_JSON = "../../log_files/landing_stats.json"

BLOCK_SCANNER_FN = "tx_runner_block_scanner.log"
DEPLOYMENTS_FN   = "tx_runner_deployments.log"
TRANSFERS_FN     = "tx_runner_transfers.log"
PROVER_LOG_FN    = "prover-0.log"

# ---------------------------
# Helpers
# ---------------------------

def read_single_gzip_bytes(path: str) -> bytes:
    with gzip.open(path, "rb") as f:
        return f.read()

def read_member_bytes_from_tar(tar_path: str, member_name: str) -> bytes:
    with tarfile.open(tar_path, mode="r:*") as tf:
        try:
            member = tf.getmember(member_name)
        except KeyError:
            for m in tf.getmembers():
                if os.path.basename(m.name) == os.path.basename(member_name):
                    member = m
                    break
            else:
                raise FileNotFoundError(f"Missing member '{member_name}' in {tar_path}")
        return tf.extractfile(member).read()  # type: ignore

def read_text_from_possible_tar_gz(path: str, inner_name: Optional[str]) -> str:
    if tarfile.is_tarfile(path):
        if inner_name is None:
            raise ValueError(f"{path} is a tar archive; inner_name is required")
        return read_member_bytes_from_tar(path, inner_name).decode("utf-8", errors="replace")
    else:
        try:
            data = read_single_gzip_bytes(path)
        except OSError:
            with open(path, "rb") as f:
                data = f.read()
        return data.decode("utf-8", errors="replace")

def read_multiple_members_from_tar(tar_path: str, members: Tuple[str, ...]) -> Tuple[str, ...]:
    with tarfile.open(tar_path, mode="r:*") as tf:
        names_map = {os.path.basename(m.name): m for m in tf.getmembers() if m.isfile()}
        contents = []
        for wanted in members:
            m = None
            if wanted in tf.getnames():
                m = tf.getmember(wanted)
            else:
                m = names_map.get(os.path.basename(wanted))
            if not m:
                raise FileNotFoundError(f"Missing member '{wanted}' in {tar_path}")
            contents.append(tf.extractfile(m).read().decode("utf-8", errors="replace"))  # type: ignore
        return tuple(contents)

# ---------------------------
# Regex
# ---------------------------

RE_PROVER_SOLUTION = re.compile(
    r"Found a Solution\s+'(?P<sid>solution[0-9a-z]+)'\s+\(Proof Target\s+(?P<target>\d+)\)",
    re.IGNORECASE,
)

RE_LANDED_SOLUTION = re.compile(
    r"^(?:\[solution\]\s+)?(?P<sid>solution[0-9a-z]+)\s+(?P<target>\d+)\s*$",
    re.IGNORECASE,
)

RE_ABORTED_SOLUTION = re.compile(
    r"^(?:\[aborted_solution\]\s+)?(?P<sid>solution[0-9a-z]+)\s*$",
    re.IGNORECASE,
)

RE_SENT_DEPLOY = re.compile(r"\bDeployment\s+(?P<txid>[a-z0-9]+)\b", re.IGNORECASE)
RE_SENT_EXECUTE = re.compile(r"\bExecution\s+(?P<txid>[a-z0-9]+)\b", re.IGNORECASE)

RE_LANDED_TX = re.compile(
    r"^(?:\[transaction\]\s+)?(?P<txid>[a-z0-9]+)\s+(?P<ttype>deploy|execute)\s*$",
    re.IGNORECASE,
)

# ---------------------------
# Parsing
# ---------------------------

def parse_prover_sent_solutions(prover_text: str) -> Dict[str, str]:
    """
    Returns dict {solution_id: target} with unique solution ids.
    If the same id appears multiple times, the first seen target is kept.
    """
    sent: Dict[str, str] = {}
    for line in prover_text.splitlines():
        m = RE_PROVER_SOLUTION.search(line)
        if m:
            sid = m.group("sid")
            target = m.group("target")
            if sid not in sent:
                sent[sid] = target
    return sent

def parse_txrunner_members(
    block_scanner_text: str,
    deployments_text: str,
    transfers_text: str,
) -> Tuple[Set[str], Set[str], Set[str], Set[str], Set[str], Set[str]]:
    landed_solutions: Set[str] = set()
    aborted_solutions: Set[str] = set()
    sent_deploy_txs: Set[str] = set()
    landed_deploy_txs: Set[str] = set()
    sent_exec_txs: Set[str] = set()
    landed_exec_txs: Set[str] = set()

    for raw in block_scanner_text.splitlines():
        line = raw.strip()
        ls = RE_LANDED_SOLUTION.match(line)
        if ls:
            landed_solutions.add(ls.group("sid"))
            continue
        la = RE_ABORTED_SOLUTION.match(line)
        if la:
            aborted_solutions.add(la.group("sid"))
            continue
        lt = RE_LANDED_TX.match(line)
        if lt:
            txid = lt.group("txid")
            ttype = lt.group("ttype").lower()
            if ttype == "deploy":
                landed_deploy_txs.add(txid)
            elif ttype == "execute":
                landed_exec_txs.add(txid)

    for line in deployments_text.splitlines():
        m = RE_SENT_DEPLOY.search(line)
        if m:
            sent_deploy_txs.add(m.group("txid"))

    for line in transfers_text.splitlines():
        m = RE_SENT_EXECUTE.search(line)
        if m:
            sent_exec_txs.add(m.group("txid"))

    return (
        landed_solutions,
        aborted_solutions,
        sent_deploy_txs,
        landed_deploy_txs,
        sent_exec_txs,
        landed_exec_txs,
    )

# ---------------------------
# Main
# ---------------------------

def calculate_percent(n: int, d: int) -> float:
    return (n / d * 100.0) if d > 0 else 0.0

def main():
    if not os.path.exists(PROVER_ARCHIVE) or not os.path.exists(TXRUNNER_ARCHIVE):
        print("ERROR: One or more source archives are missing.", file=sys.stderr)
        print(f"Expected paths : {PROVER_ARCHIVE} and {TXRUNNER_ARCHIVE}", file=sys.stderr)
        sys.exit(1)

    try:
        prover_text = read_text_from_possible_tar_gz(PROVER_ARCHIVE, PROVER_LOG_FN)
    except Exception as e:
        print(f"ERROR: Failed reading {PROVER_ARCHIVE}: {e}", file=sys.stderr)
        sys.exit(1)

    if not tarfile.is_tarfile(TXRUNNER_ARCHIVE):
        print(f"ERROR: {TXRUNNER_ARCHIVE} is not a tar archive.", file=sys.stderr)
        sys.exit(1)

    try:
        block_scanner_text, deployments_text, transfers_text = read_multiple_members_from_tar(
            TXRUNNER_ARCHIVE,
            (BLOCK_SCANNER_FN, DEPLOYMENTS_FN, TRANSFERS_FN),
        )
    except Exception as e:
        print(f"ERROR: Failed reading members from {TXRUNNER_ARCHIVE}: {e}", file=sys.stderr)
        sys.exit(1)

    sent_solutions = parse_prover_sent_solutions(prover_text)
    (
        landed_solutions,
        aborted_solutions,
        sent_deploy_txs,
        landed_deploy_txs,
        sent_exec_txs,
        landed_exec_txs,
    ) = parse_txrunner_members(block_scanner_text, deployments_text, transfers_text)

    sent_solution_ids = set(sent_solutions.keys())

    # Counts
    landed_solution_count  = len(landed_solutions  & sent_solution_ids)
    aborted_solution_count = len(aborted_solutions & sent_solution_ids)
    landed_deploy_count    = len(landed_deploy_txs & sent_deploy_txs)
    landed_exec_count      = len(landed_exec_txs   & sent_exec_txs)

    data = {
        # Solutions
        "landed_solutions": landed_solution_count,
        "aborted_solutions": aborted_solution_count,
        "sent_solutions": len(sent_solutions),
        "solutions_percentage": calculate_percent(landed_solution_count, len(sent_solutions)),
        "aborted_percentage":  calculate_percent(aborted_solution_count, len(sent_solutions)),

        # Execution TXs
        "landed_execution_transactions": landed_exec_count,
        "sent_execution_transactions": len(sent_exec_txs),
        "execution_percentage": calculate_percent(landed_exec_count, len(sent_exec_txs)),

        # Deployment TXs
        "landed_deployment_transactions": landed_deploy_count,
        "sent_deployment_transactions": len(sent_deploy_txs),
        "deployment_percentage": calculate_percent(landed_deploy_count, len(sent_deploy_txs)),
    }

    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    with open(OUTPUT_JSON, "w") as f:
        json.dump(data, f, indent=2)

    print(f"Wrote results to {OUTPUT_JSON}")

    # --- Print unresolved IDs (exclude aborted from unlanded solutions) ---
    unresolved_solutions = [
        (sid, tgt)
        for sid, tgt in sent_solutions.items()
        if sid not in landed_solutions and sid not in aborted_solutions
    ]
    unlanded_deploys = sorted(sent_deploy_txs - landed_deploy_txs)
    unlanded_execs   = sorted(sent_exec_txs   - landed_exec_txs)

    if unresolved_solutions:
        print("Unlanded solutions (non-aborted):", " ".join(f"{sid}:{tgt}" for sid, tgt in unresolved_solutions))
    if aborted_solutions & sent_solution_ids:
        print("Aborted solutions:", " ".join(sorted(aborted_solutions & sent_solution_ids)))
    if unlanded_deploys:
        print("Unlanded deployment txs:", " ".join(unlanded_deploys))
    if unlanded_execs:
        print("Unlanded execution txs:", " ".join(unlanded_execs))

if __name__ == "__main__":
    main()

