#!/usr/bin/env python3
"""Summarize why a TX blast failed to confirm on a snarkOS validator.

Reads a validator journal (plain or .gz), optionally clipped to a time window.
Works on GCS downloads (val-0-*.log.gz) better than Cloud Logging: Ops Agent
ingest timestamps lag snarkOS event time by minutes.

Example:
  python3 log_analysis_scripts/analyze_tx_blast.py \\
    --logfile val-0-10.41.0.50.log.gz --from 10:49:00 --to 10:53:00
"""

from __future__ import annotations

import argparse
import gzip
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Iterator

TS_RE = re.compile(
    r"^(?P<ts>20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+"
    r"(?P<level>INFO|DEBUG|WARN|WARNING|ERROR)\s+"
    r"(?P<msg>.*)$"
)
PROPOSE_RE = re.compile(
    r"Proposing a batch with (?P<n>\d+) transmissions for round (?P<round>\d+)"
)
BLOCK_RE = re.compile(r"Advanced to block (?P<block>\d+) at round (?P<round>\d+)")
FINISH_MS_RE = re.compile(r"Finished request in (?P<ms>[0-9.]+)ms")
LOCK_WAIT_RE = re.compile(r"avg w: (?P<ms>[0-9.]+)ms")
IP_RE = re.compile(r"\d+\.\d+\.\d+\.\d+(?::\d+)?")
NUM_RE = re.compile(r"\b\d+\b")


def open_text(path: Path) -> Iterable[str]:
    if path.suffix == ".gz":
        with gzip.open(path, "rt", errors="replace") as fh:
            yield from fh
    else:
        with path.open("r", errors="replace") as fh:
            yield from fh


def in_window(ts: str, start: str | None, end: str | None) -> bool:
    clock = ts[11:19]  # HH:MM:SS
    if start and clock < start:
        return False
    if end and clock > end:
        return False
    return True


def parse_lines(
    path: Path, start: str | None, end: str | None
) -> Iterator[tuple[str, str, str]]:
    for line in open_text(path):
        m = TS_RE.match(line.rstrip())
        if not m:
            continue
        ts, level, msg = m.group("ts", "level", "msg")
        if not in_window(ts, start, end):
            continue
        yield ts, level, msg


def norm_warn(msg: str) -> str:
    msg = IP_RE.sub("IP", msg)
    msg = NUM_RE.sub("N", msg)
    return msg[:180]


def pctile(xs: list[float], p: float) -> float:
    if not xs:
        return 0.0
    xs = sorted(xs)
    i = min(len(xs) - 1, max(0, int(round((p / 100.0) * (len(xs) - 1)))))
    return xs[i]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--logfile", required=True, help="Validator journal (.log or .gz)")
    parser.add_argument(
        "--from",
        dest="start",
        default=None,
        help="Start clock UTC HH:MM:SS (inclusive), compared to the snarkOS timestamp",
    )
    parser.add_argument(
        "--to",
        dest="end",
        default=None,
        help="End clock UTC HH:MM:SS (inclusive)",
    )
    args = parser.parse_args()
    path = Path(args.logfile)
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 1

    rest_recv = rest_fin = 0
    rest_ms: list[float] = []
    propose: list[tuple[str, int, int]] = []
    blocks: list[tuple[str, int, int]] = []
    warns: Counter[str] = Counter()
    gossip_fail = fetch_fail = proto_viol = 0
    lock_waits: list[tuple[str, float]] = []

    n = 0
    first_ts = last_ts = None
    for ts, level, msg in parse_lines(path, args.start, args.end):
        n += 1
        first_ts = first_ts or ts
        last_ts = ts
        if "uri=/transaction/broadcast" in msg:
            if "Received a request" in msg:
                rest_recv += 1
            if "Finished request" in msg:
                rest_fin += 1
                m = FINISH_MS_RE.search(msg)
                if m:
                    rest_ms.append(float(m.group("ms")))
        m = PROPOSE_RE.search(msg)
        if m:
            propose.append((ts, int(m.group("round")), int(m.group("n"))))
        m = BLOCK_RE.search(msg)
        if m:
            blocks.append((ts, int(m.group("block")), int(m.group("round"))))
        if level in ("WARN", "WARNING"):
            warns[norm_warn(msg)] += 1
        if "UnconfirmedTransaction" in msg or "non-connected peer" in msg:
            gossip_fail += 1
        if "Failed to fetch missing transmissions" in msg or "Unable to fetch transmission" in msg:
            fetch_fail += 1
        if "protocol violation" in msg or "excessive unconfirmed" in msg:
            proto_viol += 1
        if "avg w:" in msg and "bft.rs" in msg:
            m = LOCK_WAIT_RE.search(msg)
            if m:
                lock_waits.append((ts, float(m.group("ms"))))

    nonempty = [p for p in propose if p[2] > 0]
    empty = [p for p in propose if p[2] == 0]
    print(f"file: {path}")
    print(f"window: {args.start or '*'} .. {args.end or '*'}  snarkOS span {first_ts} -> {last_ts}")
    print(f"lines: {n}")
    print()
    print("REST /transaction/broadcast")
    print(f"  received {rest_recv}  finished {rest_fin}")
    if rest_ms:
        print(
            "  latency ms: "
            f"n={len(rest_ms)} p50={pctile(rest_ms, 50):.0f} "
            f"p95={pctile(rest_ms, 95):.0f} max={max(rest_ms):.0f}"
        )
    print()
    print("BFT primary proposes")
    print(
        f"  batches {len(propose)}  empty {len(empty)}  nonempty {len(nonempty)}  "
        f"sum transmissions {sum(p[2] for p in propose)}  "
        f"max {max((p[2] for p in propose), default=0)}"
    )
    if propose:
        print(f"  first {propose[0]}  last {propose[-1]}")
    if blocks:
        print(f"  blocks advanced {len(blocks)}  last {blocks[-1]}")
    print()
    print("Failures")
    print(f"  gossip UnconfirmedTransaction / not-connected: {gossip_fail}")
    print(f"  missing-transmission fetch: {fetch_fail}")
    print(f"  protocol-violation / excessive solutions: {proto_viol}")
    if lock_waits:
        ts, ms = max(lock_waits, key=lambda x: x[1])
        print(f"  bft.rs lock wait max {ms:.0f} ms at {ts}")
    if warns:
        print("  WARN templates:")
        for msg, c in warns.most_common(8):
            print(f"    {c:5d}  {msg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
