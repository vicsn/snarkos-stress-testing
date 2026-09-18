#!/usr/bin/env python3
"""Fetch snarkOS/snarkVM thread-pool, VM, consensus, and GCE metrics from GMP Prometheus.

Queries match the snarkOS incident-response dashboard panels for metrics added by
https://github.com/ProvableHQ/snarkOS/pull/4451 and
https://github.com/ProvableHQ/snarkVM/pull/3416, plus consensus/block series and
GCE instance CPU utilization.

Requires an authenticated gcloud user with monitoring.timeSeries.list on the
project (default: protocol-development-sandbox).

Timestamps are interpreted as Europe/Berlin (CEST in summer, CET in winter)
unless the value includes an explicit offset or Z.

Examples:
  python3 scripts/fetch_thread_pool_metrics.py \\
    --start "2026-09-14 10:17" --end "2026-09-14 11:42"

  python3 scripts/fetch_thread_pool_metrics.py \\
    --start 2026-09-14T10:17 --end 2026-09-14T11:42 \\
    --network canary --role '.*validator' --json out.json --csv out.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

CEST = ZoneInfo("Europe/Berlin")
GMP_QUERY_RANGE = (
    "https://monitoring.googleapis.com/v1/projects/{project}"
    "/location/global/prometheus/api/v1/query_range"
)
DEFAULT_PROJECT = "protocol-development-sandbox"
SELECTOR = 'snarkos_network="{network}",snarkos_role=~"{role}"'
VALIDATOR_SELECTOR = 'snarkos_network="{network}",snarkos_role=~".*validator"'


@dataclass(frozen=True)
class MetricQuery:
    name: str
    title: str
    source: str
    expr: str


# Dashboard PromQL from snarkos-stress-testing/.../dashboard.json.
# Quantile overlays (p50/p95/p99) are fetched as one series set (no quantile
# matcher) so every quantile/label combination is returned.
QUERIES: tuple[MetricQuery, ...] = (
    # --- snarkOS#4451 thread pools ---
    MetricQuery(
        "snarkos_rayon_threads",
        "Rayon Threads",
        "snarkOS#4451",
        "snarkos_rayon_threads{" + SELECTOR + "}",
    ),
    MetricQuery(
        "namedprocess_namegroup_thread_cpu_seconds_total",
        "Rayon Thread CPU Seconds",
        "process-exporter",
        "namedprocess_namegroup_thread_cpu_seconds_total{"
        + SELECTOR
        + ',threadname=~"rayon-.*"}',
    ),
    MetricQuery(
        "snarkos_tokio_workers",
        "Tokio Workers",
        "snarkOS#4451",
        "snarkos_tokio_workers{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_alive_tasks",
        "Tokio Alive Tasks",
        "snarkOS#4451",
        "snarkos_tokio_alive_tasks{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_global_queue_depth",
        "Tokio Global Queue Depth",
        "snarkOS#4451",
        "snarkos_tokio_global_queue_depth{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_worker_busy_cores",
        "Tokio Worker Busy Cores",
        "snarkOS#4451",
        "snarkos_tokio_worker_busy_cores{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_worker_busy_ratio_max",
        "Tokio Worker Busy Ratio Max",
        "snarkOS#4451",
        "snarkos_tokio_worker_busy_ratio_max{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_worker_parks",
        "Tokio Worker Parks",
        "snarkOS#4451",
        "snarkos_tokio_worker_parks{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_cpu_blocking_wait_secs",
        "CPU Blocking Wait (p50/p95/p99)",
        "snarkOS#4451",
        "snarkos_cpu_blocking_wait_secs{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_blocking_threads",
        "Tokio Blocking Threads (tokio_unstable)",
        "snarkOS#4451",
        "snarkos_tokio_blocking_threads{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_blocking_threads_idle",
        "Tokio Blocking Threads Idle (tokio_unstable)",
        "snarkOS#4451",
        "snarkos_tokio_blocking_threads_idle{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_blocking_queue_depth",
        "Tokio Blocking Queue Depth (tokio_unstable)",
        "snarkOS#4451",
        "snarkos_tokio_blocking_queue_depth{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_worker_steals",
        "Tokio Worker Steals (tokio_unstable)",
        "snarkOS#4451",
        "snarkos_tokio_worker_steals{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_tokio_worker_noops",
        "Tokio Worker Noops (tokio_unstable)",
        "snarkOS#4451",
        "snarkos_tokio_worker_noops{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_bft_subdag_certificates_per_round",
        "Subdag Certificates per Round",
        "snarkOS#4451",
        "avg by (instance_name) (rate(snarkos_bft_subdag_certificates_per_round_sum{"
        + VALIDATOR_SELECTOR
        + "}[1m]))",
    ),
    MetricQuery(
        "snarkos_bft_subdag_certificate_signatures",
        "Subdag Certificate Signatures",
        "snarkOS#4451",
        "avg by (instance_name) (rate(snarkos_bft_subdag_certificate_signatures_sum{"
        + VALIDATOR_SELECTOR
        + "}[1m]))",
    ),
    MetricQuery(
        "snarkos_bft_subdag_certificate_previous_refs",
        "Subdag Certificate Previous Refs",
        "snarkOS#4451",
        "avg by (instance_name) (rate(snarkos_bft_subdag_certificate_previous_refs_sum{"
        + VALIDATOR_SELECTOR
        + "}[1m]))",
    ),
    MetricQuery(
        "snarkos_bft_subdag_rounds_per_block",
        "Subdag Rounds per Block",
        "snarkOS#4451",
        "avg by (instance_name) (rate(snarkos_bft_subdag_rounds_per_block_sum{"
        + VALIDATOR_SELECTOR
        + "}[1m]))",
    ),
    # --- snarkVM#3416 VM verification / speculate ---
    MetricQuery(
        "snarkvm_vm_check_transaction_in_flight",
        "Check Transaction In Flight",
        "snarkVM#3416",
        "snarkvm_vm_check_transaction_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_check_transaction_duplicate_in_flight",
        "Check Transaction Duplicate In Flight",
        "snarkVM#3416",
        "snarkvm_vm_check_transaction_duplicate_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_check_transaction_duration_seconds",
        "Check Transaction Duration by Cache (p95 on dashboard)",
        "snarkVM#3416",
        "snarkvm_vm_check_transaction_duration_seconds{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_check_transaction_cache_hit_total",
        "Check Transaction Cache Hit Rate",
        "snarkVM#3416",
        "rate(snarkvm_vm_check_transaction_cache_hit_total{"
        + SELECTOR
        + "}[{rate_interval}])",
    ),
    MetricQuery(
        "snarkvm_vm_check_transaction_cache_miss_total",
        "Check Transaction Cache Miss Rate",
        "snarkVM#3416",
        "rate(snarkvm_vm_check_transaction_cache_miss_total{"
        + SELECTOR
        + "}[{rate_interval}])",
    ),
    MetricQuery(
        "snarkvm_vm_check_transaction_cache_redundant_write_total",
        "Check Transaction Cache Redundant Write Rate",
        "snarkVM#3416",
        "rate(snarkvm_vm_check_transaction_cache_redundant_write_total{"
        + SELECTOR
        + "}[{rate_interval}])",
    ),
    MetricQuery(
        "snarkvm_vm_prepare_for_speculate_in_flight",
        "Prepare for Speculate In Flight",
        "snarkVM#3416",
        "snarkvm_vm_prepare_for_speculate_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_prepare_for_speculate_transactions_in_flight",
        "Prepare for Speculate Transactions In Flight",
        "snarkVM#3416",
        "snarkvm_vm_prepare_for_speculate_transactions_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_prepare_for_speculate_duration_seconds",
        "Prepare for Speculate Duration (p50/p95/p99)",
        "snarkVM#3416",
        "snarkvm_vm_prepare_for_speculate_duration_seconds{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_prepare_for_speculate_transactions",
        "Prepare for Speculate Transactions by Stage",
        "snarkVM#3416",
        "sum by (stage) (rate(snarkvm_vm_prepare_for_speculate_transactions_sum{"
        + SELECTOR
        + "}[{rate_interval}]))",
    ),
    MetricQuery(
        "snarkvm_vm_atomic_speculate_in_flight",
        "Atomic Speculate In Flight",
        "snarkVM#3416",
        "snarkvm_vm_atomic_speculate_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_atomic_speculate_duration_seconds",
        "Atomic Speculate Duration (p50/p95/p99)",
        "snarkVM#3416",
        "snarkvm_vm_atomic_speculate_duration_seconds{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_speculate_in_flight",
        "Speculate In Flight",
        "snarkVM#3416",
        "snarkvm_vm_speculate_in_flight{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_vm_speculate_duration_seconds",
        "Speculate Duration (p50/p95/p99)",
        "snarkVM#3416",
        "snarkvm_vm_speculate_duration_seconds{" + SELECTOR + "}",
    ),
    # --- consensus / block / instance (dashboard) ---
    MetricQuery(
        "snarkos_consensus_stale_unconfirmed_transactions",
        "Stale Unconfirmed Transactions",
        "dashboard",
        "snarkos_consensus_stale_unconfirmed_transactions{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_consensus_unconfirmed_transactions_total",
        "Unconfirmed Transactions",
        "dashboard",
        "snarkos_consensus_unconfirmed_transactions_total{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_blocks_transactions_total",
        "Confirmed Transactions",
        "dashboard",
        "snarkos_blocks_transactions_total{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkos_consensus_transmission_latency",
        "Avg Transaction Latency (Seconds)",
        "dashboard",
        "snarkos_consensus_transmission_latency{"
        + SELECTOR
        + ',transmission_type="transaction"}',
    ),
    # --- rocksdb (snarkVM), for write-stall and compaction backpressure ---
    MetricQuery(
        "snarkvm_rocksdb_num_running_compactions",
        "RocksDB Running Compactions",
        "rocksdb",
        "snarkvm_rocksdb_num_running_compactions{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_rocksdb_compaction_pending",
        "RocksDB Compaction Pending",
        "rocksdb",
        "snarkvm_rocksdb_compaction_pending{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_rocksdb_estimate_pending_compaction_bytes",
        "RocksDB Pending Compaction Bytes",
        "rocksdb",
        "snarkvm_rocksdb_estimate_pending_compaction_bytes{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_rocksdb_num_running_flushes",
        "RocksDB Running Flushes",
        "rocksdb",
        "snarkvm_rocksdb_num_running_flushes{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_rocksdb_mem_table_flush_pending",
        "RocksDB Memtable Flush Pending",
        "rocksdb",
        "snarkvm_rocksdb_mem_table_flush_pending{" + SELECTOR + "}",
    ),
    MetricQuery(
        "snarkvm_rocksdb_num_files_at_level0",
        "RocksDB L0 File Count",
        "rocksdb",
        "snarkvm_rocksdb_num_files_at_level0{" + SELECTOR + "}",
    ),
    # --- per-pool CPU (process-exporter, keyed by the thread names from snarkOS#4451) ---
    # Monotonic counters, so these are immune to the aliasing that affects the
    # sampled thread-pool gauges above: they lose nothing between scrapes.
    MetricQuery(
        "thread_cpu_rayon",
        "Rayon Pool CPU (cores)",
        "process-exporter",
        'sum by (instance_name) (rate(namedprocess_namegroup_thread_cpu_seconds_total{'
        + SELECTOR
        + ',threadname=~"rayon-.*"}[{rate_interval}]))',
    ),
    MetricQuery(
        "thread_cpu_tokio_worker",
        "Tokio Worker CPU (cores)",
        "process-exporter",
        'sum by (instance_name) (rate(namedprocess_namegroup_thread_cpu_seconds_total{'
        + SELECTOR
        + ',threadname=~"tokio-worker.*"}[{rate_interval}]))',
    ),
    # Linux truncates thread names at 15 bytes, so every blocking thread lands in
    # the single group "tokio-blocking-". Aggregate CPU is exact; per-thread is not
    # recoverable.
    MetricQuery(
        "thread_cpu_tokio_blocking",
        "Tokio Blocking Pool CPU (cores)",
        "process-exporter",
        'sum by (instance_name) (rate(namedprocess_namegroup_thread_cpu_seconds_total{'
        + SELECTOR
        + ',threadname=~"tokio-blocking.*"}[{rate_interval}]))',
    ),
    MetricQuery(
        "thread_cpu_rocksdb",
        "RocksDB Thread CPU (cores)",
        "process-exporter",
        'sum by (instance_name) (rate(namedprocess_namegroup_thread_cpu_seconds_total{'
        + SELECTOR
        + ',threadname=~"rocksdb.*"}[{rate_interval}]))',
    ),
    MetricQuery(
        "thread_cpu_per_rayon_thread",
        "Rayon CPU per Thread (imbalance)",
        "process-exporter",
        "rate(namedprocess_namegroup_thread_cpu_seconds_total{"
        + SELECTOR
        + ',threadname=~"rayon-.*"}[{rate_interval}])',
    ),
    # GCE metric has no snarkos_network / snarkos_role labels.
    MetricQuery(
        "compute_instance_cpu_utilization",
        "GCE Instance CPU Utilization",
        "GCE",
        '{"__name__"="compute.googleapis.com/instance/cpu/utilization",'
        '"monitored_resource"="gce_instance"}',
    ),
)


def parse_cest(value: str) -> datetime:
    """Parse --start/--end. Minute (and second) precision is first-class.

    Naive values are Europe/Berlin. Hour-only (`2026-09-14 10`) means HH:00.
    ISO-8601 with offset or Z is kept as given.
    """
    text = value.strip()
    if not text:
        raise argparse.ArgumentTypeError("empty datetime")

    candidates = [text]
    if "T" not in text[:19] and " " in text:
        candidates.append(text.replace(" ", "T", 1))

    for candidate in candidates:
        iso = candidate[:-1] + "+00:00" if candidate.endswith(("Z", "z")) else candidate
        try:
            parsed = datetime.fromisoformat(iso)
        except ValueError:
            continue
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=CEST)
        return parsed

    compact = text.replace("T", " ")
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d %H",
        "%Y-%m-%d",
    ):
        try:
            return datetime.strptime(compact, fmt).replace(tzinfo=CEST)
        except ValueError:
            continue

    raise argparse.ArgumentTypeError(
        f"expected datetime like '2026-09-14 10:17' (Europe/Berlin unless "
        f"timezone given), got {value!r}"
    )


def rfc3339_utc(when: datetime) -> str:
    """RFC3339 UTC with seconds so query_range honors minute-level bounds."""
    return when.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def gcloud_access_token() -> str:
    try:
        result = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("gcloud is not on PATH") from exc
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or exc.stdout or "").strip()
        raise SystemExit(
            "gcloud auth print-access-token failed. Run `gcloud auth login`.\n"
            + err
        ) from exc
    token = result.stdout.strip()
    if not token:
        raise SystemExit("gcloud returned an empty access token")
    return token


def default_step(start: datetime, end: datetime) -> str:
    seconds = max(1, int((end - start).total_seconds()))
    if seconds <= 3 * 3600:
        # Matches `ops_agent_prometheus_scrape_interval`. A step coarser than the
        # scrape interval silently drops samples, which matters for the sampled
        # thread-pool gauges because each one reports a single 1-second window.
        return "10s"
    if seconds <= 12 * 3600:
        return "1m"
    if seconds <= 3 * 86400:
        return "5m"
    return "15m"


def query_range(
    *,
    project: str,
    token: str,
    expr: str,
    start: datetime,
    end: datetime,
    step: str,
    timeout: int,
) -> dict[str, Any]:
    # rate() needs lookback before --start; 2x the window is enough for 1m/5m rates.
    lookback_start = start - timedelta(minutes=5)
    params = urllib.parse.urlencode(
        {
            "query": expr,
            "start": rfc3339_utc(lookback_start),
            "end": rfc3339_utc(end),
            "step": step,
        }
    )
    url = GMP_QUERY_RANGE.format(project=project) + "?" + params
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {"error": body}
        return {
            "status": "error",
            "http_status": exc.code,
            "error": payload,
        }
    except urllib.error.URLError as exc:
        return {"status": "error", "error": str(exc.reason)}
    return payload


def clip_values(result: dict[str, Any], start: datetime) -> dict[str, Any]:
    """Drop lookback samples so the returned range matches --start/--end."""
    if result.get("status") != "success":
        return result
    cutoff = start.astimezone(timezone.utc).timestamp()
    data = result.get("data") or {}
    series = data.get("result") or []
    for item in series:
        values = item.get("values") or []
        item["values"] = [point for point in values if float(point[0]) >= cutoff]
    return result


def series_count(result: dict[str, Any]) -> int:
    if result.get("status") != "success":
        return 0
    return len((result.get("data") or {}).get("result") or [])


def sample_count(result: dict[str, Any]) -> int:
    if result.get("status") != "success":
        return 0
    return sum(
        len(item.get("values") or [])
        for item in (result.get("data") or {}).get("result") or []
    )


def flatten_csv_rows(query: MetricQuery, expr: str, result: dict[str, Any]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    if result.get("status") != "success":
        return rows
    for item in (result.get("data") or {}).get("result") or []:
        metric = item.get("metric") or {}
        labels = {k: str(v) for k, v in metric.items() if k != "__name__"}
        metric_name = str(metric.get("__name__", query.name))
        for ts, value in item.get("values") or []:
            when = datetime.fromtimestamp(float(ts), tz=timezone.utc).astimezone(CEST)
            rows.append(
                {
                    "timestamp_cest": when.strftime("%Y-%m-%d %H:%M:%S%z"),
                    "query": query.name,
                    "title": query.title,
                    "source": query.source,
                    "metric": metric_name,
                    "labels": json.dumps(labels, sort_keys=True),
                    "value": str(value),
                    "expr": expr,
                }
            )
    return rows


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch snarkOS#4451 / snarkVM#3416, consensus, and GCE CPU metrics "
            "from GMP Prometheus."
        )
    )
    parser.add_argument(
        "--start",
        type=parse_cest,
        help="Range start (minute precision), e.g. '2026-09-14 10:17'",
    )
    parser.add_argument(
        "--end",
        type=parse_cest,
        help="Range end (minute precision), e.g. '2026-09-14 11:42'",
    )
    parser.add_argument(
        "--project",
        default=DEFAULT_PROJECT,
        help=f"GCP project whose GMP endpoint to query (default: {DEFAULT_PROJECT})",
    )
    parser.add_argument(
        "--network",
        default=".+",
        help='snarkos_network matcher. Default ".+" (all). Exact match unless this contains regex metacharacters.',
    )
    parser.add_argument(
        "--role",
        default=".*",
        help='snarkos_role regex, same as the dashboard [[role]] variable (default: ".*")',
    )
    parser.add_argument(
        "--rate-interval",
        default="1m",
        help="Prometheus range for rate() queries / dashboard $rate_interval (default: 1m)",
    )
    parser.add_argument(
        "--step",
        default=None,
        help="query_range step. Default depends on window length (15s / 1m / 5m / 15m).",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="HTTP timeout per query in seconds (default: 60)",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Substring filter on query name; repeatable",
    )
    parser.add_argument("--json", dest="json_path", help="Write full JSON payload here")
    parser.add_argument("--csv", dest="csv_path", help="Write flattened samples here")
    parser.add_argument(
        "--list",
        action="store_true",
        help="Print the query catalog and exit",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args(argv)


def render_network_expr(query: MetricQuery, network: str, role: str, rate_interval: str) -> str:
    # Replace placeholders without str.format so PromQL label braces stay intact.
    expr = query.expr
    if any(ch in network for ch in r".*+?[]()|\\^$"):
        expr = expr.replace('snarkos_network="{network}"', 'snarkos_network=~"{network}"')
    return (
        expr.replace("{network}", network)
        .replace("{role}", role)
        .replace("{rate_interval}", rate_interval)
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.list:
        for query in QUERIES:
            print(f"{query.name}\t{query.source}\t{query.title}")
        return 0
    if args.start is None or args.end is None:
        raise SystemExit("--start and --end are required unless --list")
    if args.end <= args.start:
        raise SystemExit("--end must be after --start")

    selected = QUERIES
    if args.only:
        selected = tuple(
            query
            for query in QUERIES
            if any(token.lower() in query.name.lower() for token in args.only)
        )
        if not selected:
            raise SystemExit("no queries matched --only")

    step = args.step or default_step(args.start, args.end)
    token = gcloud_access_token()

    results: list[dict[str, Any]] = []
    csv_rows: list[dict[str, str]] = []
    for index, query in enumerate(selected, start=1):
        expr = render_network_expr(query, args.network, args.role, args.rate_interval)
        if args.verbose:
            print(f"[{index}/{len(selected)}] {query.name}: {expr}", file=sys.stderr)
        else:
            print(f"[{index}/{len(selected)}] {query.name}", file=sys.stderr)
        payload = clip_values(
            query_range(
                project=args.project,
                token=token,
                expr=expr,
                start=args.start,
                end=args.end,
                step=step,
                timeout=args.timeout,
            ),
            args.start,
        )
        entry = {
            **asdict(query),
            "expr": expr,
            "series": series_count(payload),
            "samples": sample_count(payload),
            "result": payload,
        }
        results.append(entry)
        csv_rows.extend(flatten_csv_rows(query, expr, payload))
        status = payload.get("status")
        if status != "success":
            print(f"  error: {payload.get('error') or payload}", file=sys.stderr)
        else:
            print(f"  {entry['series']} series, {entry['samples']} samples", file=sys.stderr)
        # Gentle pacing for the Monitoring API.
        time.sleep(0.05)

    document = {
        "project": args.project,
        "timezone": "Europe/Berlin",
        "start_cest": args.start.isoformat(),
        "end_cest": args.end.isoformat(),
        "start_unix": int(args.start.astimezone(timezone.utc).timestamp()),
        "end_unix": int(args.end.astimezone(timezone.utc).timestamp()),
        "step": step,
        "network": args.network,
        "role": args.role,
        "rate_interval": args.rate_interval,
        "queries": results,
    }

    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2)
            handle.write("\n")
        print(f"wrote {args.json_path}", file=sys.stderr)
    else:
        json.dump(document, sys.stdout, indent=2)
        sys.stdout.write("\n")

    if args.csv_path:
        fieldnames = [
            "timestamp_cest",
            "query",
            "title",
            "source",
            "metric",
            "labels",
            "value",
            "expr",
        ]
        with open(args.csv_path, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(csv_rows)
        print(f"wrote {args.csv_path} ({len(csv_rows)} rows)", file=sys.stderr)

    errors = [item for item in results if item["result"].get("status") != "success"]
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
