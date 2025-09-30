#!/usr/bin/env python3

"""
Stream Aleo ledger snapshots from HTTP to S3 using multipart upload.

Run in its venv, e.g.:
    cd scripts
    . .venv_store_latest_snapshot/bin/activate
    python store_latest_snapshot.py --network canary

- Discovers the real snapshot URL from: https://ledger.aleo.network/<network>/snapshot/latest.txt
- Downloads each part via HTTP Range into memory (e.g., 256 MiB), with live progress
- Uploads each part as bytes to S3 (avoids body-stream signing quirks)
- Resumable in Range mode via a local state file
- Stall-safe: if no bytes arrive for --stall-timeout seconds (default 20s), the part is retried
- Ctrl+C: first press = finish current part then stop; second press = abort immediately
- Robust to transient origin glitches where Range is ignored (status=200): retry instead of aborting MPU/state
- Resume is STRICTLY LOCKED to the original SourceURL: if it’s gone/changed, we abort (leave state) and do NOT switch to a newer snapshot automatically.
- Optional HTTP keep-alive session (off by default) via --http-session on.
"""

import argparse
import base64
import hashlib
import json
import math
import os
import signal
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse, unquote

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import re

DEFAULT_BUCKET = os.getenv("INGEST_BUCKET", "aleo-snapshots")
NETWORK_PREFIX = {
    "main":    os.getenv("INGEST_PREFIX_MAIN", "main/"),
    "testnet": os.getenv("INGEST_PREFIX_TESTNET", "testnet/"),
    "canary":  os.getenv("INGEST_PREFIX_CANARY", "canary/"),
}
LEDGER_BASE = os.getenv("LEDGER_BASE", "https://ledger.aleo.network")

AWS_RETRIES = {"max_attempts": 10, "mode": "standard"}
HTTP_TIMEOUT = (10, 120)  # (connect, read) base; per-request read timeout overridden by --stall-timeout
CHUNK = 16 * 1024 * 1024   # 16 MiB HTTP read chunks for per-part download

CANCEL = {"mode": 0}  # 0=run, 1=soft cancel after current part, 2=hard cancel now

SETTINGS = {
    "http_session": "off",  # 'off' or 'on'
}

SESSION = {"obj": None, "uses": 0}

class RangeNotHonored(Exception):
    pass

class TooSlow(Exception):
    pass


def parse_args():
    p = argparse.ArgumentParser(description="Stream huge Aleo ledger snapshot to S3 via multipart upload.")
    p.add_argument("--network", required=True, choices=["main", "testnet", "canary"])
    p.add_argument("--url", help="Override source URL (skips latest.txt parsing)")
    p.add_argument("--bucket", help="Destination S3 bucket (overrides defaults/env)")
    p.add_argument("--key", help="Destination S3 key (default: <prefix>/<basename(real-url)>)")
    p.add_argument("--part-size-mib", type=int, default=256, help="Multipart part size in MiB (default 256)")
    p.add_argument("--state-dir", default=".upload_state", help="Dir to store/resume state (default .upload_state)")
    p.add_argument("--checksum", choices=["none", "sha256"], default="none",
                   help="Per-part checksum header (sha256). Default: none")
    p.add_argument("--region", help="AWS region (optional)")
    p.add_argument("--user-agent-suffix", default="http-to-s3-multipart/2.2",
                   help="Suffix for HTTP User-Agent")
    p.add_argument("--fallback-tempdir", default=None, help="Temp dir for fallback mode")
    p.add_argument("--stall-timeout", type=int, default=20,
                   help="If no bytes are received for this many seconds, restart the part (default 20)")
    p.add_argument("--force-new", action="store_true",
                   help="Start a new upload even if a resume state exists (won't overwrite old state)")

    p.add_argument("--http-session", choices=["off", "on"], default="off",
                   help="Use a persistent HTTP session with keep-alive (default: off)")
    p.add_argument("--min-mibps", type=float, default=0.0,
                   help="If >0, retry the part if instantaneous throughput stays below this MiB/s for --min-mibps-seconds")
    p.add_argument("--min-mibps-seconds", type=int, default=20,
                   help="Seconds of sustained slow throughput before retry (only if --min-mibps > 0)")
    p.add_argument("--recycle-session-every", type=int, default=0,
                   help="(Session ON only) Recycle HTTP session after this many parts (0=disabled)")

    return p.parse_args()


def make_session():
    s = requests.Session()
    adapter = HTTPAdapter(
        pool_connections=8, pool_maxsize=8,
        max_retries=Retry(connect=0, read=0, redirect=0, status=0, backoff_factor=0.0, raise_on_status=False),
    )
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s


def get_session():
    if SETTINGS.get("http_session") == "on":
        if SESSION["obj"] is None:
            SESSION["obj"] = make_session()
            SESSION["uses"] = 0
        return SESSION["obj"]
    else:
        return requests  # one-off per call


def recycle_session(reason: str):
    if SETTINGS.get("http_session") != "on":
        return
    try:
        if SESSION["obj"] is not None:
            print(f"\n[session] Recycling HTTP session ({reason}).", flush=True)
            try:
                SESSION["obj"].close()
            except Exception:
                pass
    finally:
        SESSION["obj"] = None
        SESSION["uses"] = 0


def basename_from_url(u: str) -> str:
    return Path(unquote(Path(urlparse(u).path).name or "")).name


def fetch_real_url_from_latest(network, ua_suffix):
    latest_url = f"{LEDGER_BASE}/{network}/snapshot/latest.txt"
    headers = {"User-Agent": f"Mozilla/5.0 ({ua_suffix})"}
    r = get_session().get(latest_url, timeout=HTTP_TIMEOUT, headers=headers)
    r.raise_for_status()
    txt = r.text
    m = re.search(r'(https?://[^\s\'"]+\.(?:tar\.zst|tar\.gz|tar\.xz|zip))', txt)
    if not m:
        sys.exit(f"ERROR: Could not find a snapshot URL in latest.txt at {latest_url}")
    return m.group(1)


def resolve_bucket_region(bucket, prefer_region=None):
    if prefer_region:
        return prefer_region
    try:
        s3_global = boto3.client("s3")
        loc = s3_global.get_bucket_location(Bucket=bucket).get("LocationConstraint")
        return "us-west-2" if not loc else loc
    except Exception:
        return "us-west-2"


def s3_client(region):
    if region:
        return boto3.client("s3", region_name=region, config=Config(retries=AWS_RETRIES))
    return boto3.client("s3", config=Config(retries=AWS_RETRIES))


def state_file_path(state_dir, bucket, key):
    safe = f"{bucket}__{key}".replace("/", "__")
    Path(state_dir).mkdir(parents=True, exist_ok=True)
    return Path(state_dir) / (safe + ".json")


def save_state(path, data):
    tmp = str(path) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def load_state(path):
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def delete_state(path):
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def derive_bucket_and_key(bucket_arg, key_arg, network, real_url):
    bucket = bucket_arg or DEFAULT_BUCKET
    if not bucket:
        sys.exit("ERROR: S3 bucket is not provided. Set --bucket or INGEST_BUCKET env.")
    base = Path(unquote(Path(urlparse(real_url).path).name or "snapshot.tar.zst")).name
    prefix = NETWORK_PREFIX[network]
    key = key_arg or f"{prefix}{base}"
    return bucket, key


def http_head(url, ua_suffix):
    headers = {"User-Agent": f"Mozilla/5.0 ({ua_suffix})"}
    r = get_session().head(url, timeout=HTTP_TIMEOUT, allow_redirects=True, headers=headers)
    r.raise_for_status()
    size = r.headers.get("Content-Length")
    accept_ranges = r.headers.get("Accept-Ranges", "")
    return (int(size) if size is not None else None), accept_ranges.lower()


def http_get_range(url, start, end, ua_suffix, timeout=HTTP_TIMEOUT):
    headers = {
        "Range": f"bytes={start}-{end}",
        "User-Agent": f"Mozilla/5.0 ({ua_suffix})",
        "Accept-Encoding": "identity",
    }
    r = get_session().get(url, headers=headers, timeout=timeout, stream=True)
    r.raise_for_status()
    if r.status_code != 206:
        raise RangeNotHonored(
            f"Origin did not honor Range (status={r.status_code}); "
            f"Accept-Ranges={r.headers.get('Accept-Ranges')}, "
            f"Content-Range={r.headers.get('Content-Range')}"
        )
    if hasattr(r.raw, "decode_content"):
        r.raw.decode_content = False
    return r


def with_retries(fn, *, attempts=5, base_delay=1.0,
                 exc_types=(requests.RequestException, BotoCoreError, ClientError, RangeNotHonored, RuntimeError, TooSlow),
                 desc=""):
    last = None
    for i in range(attempts):
        try:
            return fn()
        except exc_types as e:
            last = e
            sleep = base_delay * (2 ** i)
            print(f"[retry {i+1}/{attempts}] {desc}: {e} -> sleeping {sleep:.1f}s", flush=True)
            if isinstance(e, (requests.ReadTimeout, requests.ConnectionError, RangeNotHonored, TooSlow)):
                recycle_session(type(e).__name__)
            time.sleep(sleep)
    if last:
        raise last


def compute_sha256_b64(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return base64.b64encode(digest).decode("ascii")


def download_part_bytes(real_url, start, end, ua_suffix, total_size, part_no, stall_timeout, min_mibps, min_mibps_seconds):
    if CANCEL["mode"] == 2:
        raise KeyboardInterrupt

    resp = http_get_range(real_url, start, end, ua_suffix, timeout=(HTTP_TIMEOUT[0], stall_timeout))
    total_in_part = end - start + 1
    buf = bytearray(total_in_part)
    view = memoryview(buf)
    filled = 0
    last_t = time.time()
    last_filled = 0
    last_progress_t = last_t
    slow_start_t = None

    try:
        for chunk in resp.iter_content(chunk_size=CHUNK):
            if CANCEL["mode"] == 2:
                raise KeyboardInterrupt

            if not chunk:
                now = time.time()
                if now - last_progress_t > stall_timeout:
                    recycle_session("stall-timeout")
                    raise requests.ReadTimeout(f"no progress for >{stall_timeout}s", request=resp.request)
                continue

            n = len(chunk)
            if filled + n > total_in_part:
                n = total_in_part - filled
                chunk = chunk[:n]
            view[filled:filled+n] = chunk
            filled += n
            last_progress_t = time.time()

            now = time.time()
            if now - last_t >= 1.0 or filled == total_in_part:
                p_part = (filled / total_in_part) * 100.0
                p_total = ((start + filled) / total_size) * 100.0 if total_size else 0.0
                dt = max(1e-6, now - last_t)
                db = filled - last_filled
                speed_mib_s = (db / 1024 / 1024) / dt
                remaining = max(0, total_in_part - filled)
                eta_s = (remaining / 1024 / 1024) / speed_mib_s if speed_mib_s > 0 else float("inf")
                print(
                    f"\rPart {part_no}: {p_part:5.1f}% | total {p_total:6.2f}% | "
                    f"{speed_mib_s:5.1f} MiB/s | ETA(part) {eta_s:6.1f}s",
                    end="", flush=True
                )

                if min_mibps > 0.0:
                    if speed_mib_s < min_mibps:
                        if slow_start_t is None:
                            slow_start_t = now
                        elif now - slow_start_t >= min_mibps_seconds:
                            recycle_session(f"too-slow<{min_mibps}MiB/s for {min_mibps_seconds}s")
                            raise TooSlow(f"throughput < {min_mibps} MiB/s for >= {min_mibps_seconds}s")
                    else:
                        slow_start_t = None

                last_t = now
                last_filled = filled

            if filled >= total_in_part:
                break

        if filled != total_in_part:
            raise RuntimeError(f"Short read for range {start}-{end}: got {filled} bytes, expected {total_in_part}")
        return buf
    finally:
        try:
            resp.close()
        except Exception:
            pass


def upload_range_part(s3, bucket, key, upload_id, part_no, start, end, args, real_url, total_size):
    if CANCEL["mode"] == 2:
        raise KeyboardInterrupt

    content_length = end - start + 1

    def do_once():
        data = download_part_bytes(
            real_url, start, end, args.user_agent_suffix, total_size, part_no,
            args.stall_timeout, args.min_mibps, args.min_mibps_seconds
        )
        if CANCEL["mode"] == 2:
            raise KeyboardInterrupt
        kwargs = dict(
            Bucket=bucket, Key=key, UploadId=upload_id,
            PartNumber=part_no, Body=data, ContentLength=content_length
        )
        if args.checksum == "sha256":
            kwargs["ChecksumSHA256"] = compute_sha256_b64(data)
        return s3.upload_part(**kwargs)

    resp = with_retries(
        do_once,
        attempts=5,
        base_delay=2.0,
        desc=f"upload_part #{part_no} bytes {start}-{end}",
    )
    return resp["ETag"]


# ---------- STRICT RESUME HELPERS ----------

def state_is_consistent(st: dict) -> bool:
    """Key basename and SourceURL basename must match; Size must be a positive int."""
    key = st.get("Key")
    url = st.get("SourceURL")
    size = st.get("Size")
    if not key or not url or not size:
        return False
    key_base = Path(key).name
    url_base = basename_from_url(url)
    return key_base == url_base and isinstance(size, int) and size > 0


def pick_resume_state(state_dir: str, bucket: str, prefix: str):
    """
    Choose the newest state that is internally consistent and whose Key starts with the prefix.
    Returns (path, state) or (None, None).
    """
    sd = Path(state_dir)
    if not sd.exists():
        return None, None
    candidates = []
    for p in sd.glob("*.json"):
        try:
            st = json.loads(p.read_text())
        except Exception:
            continue
        if not isinstance(st, dict):
            continue
        if st.get("Bucket") != bucket:
            continue
        k = st.get("Key")
        if not isinstance(k, str) or not k.startswith(prefix):
            continue
        if not state_is_consistent(st):
            continue
        candidates.append((p, st))
    if not candidates:
        return None, None
    candidates.sort(key=lambda x: x[0].stat().st_mtime, reverse=True)
    return candidates[0]


# ---------- MAIN MPU DRIVER ----------

def multipart_upload_range_mode(s3, bucket, key, total_size, args, st_path, resume, real_url):
    part_size = args.part_size_mib * 1024 * 1024
    parts_total = math.ceil(total_size / part_size)

    st = load_state(st_path) if resume else None

    # If state exists, enforce strict invariants before resuming
    if st and resume:
        if not state_is_consistent(st):
            print(f"Inconsistent state at {st_path} (Key/URL/Size mismatch). Refusing to resume.", flush=True)
            return False

        saved_url = st.get("SourceURL")
        saved_key = st.get("Key")
        saved_size = st.get("Size")

        # Require HEAD match on saved URL
        try:
            size_head, ar = http_head(saved_url, args.user_agent_suffix)
            if ar != "bytes":
                print(f"Resume check failed: Accept-Ranges={ar} (expected 'bytes').", flush=True)
                return False
            if size_head is not None and size_head != saved_size:
                print(f"Resume check failed: Content-Length changed ({size_head} != saved {saved_size}).", flush=True)
                return False
        except Exception as e:
            print(f"Resume HEAD failed for saved URL: {e}", flush=True)
            return False

        real_url = saved_url
        key = saved_key
        total_size = saved_size

    # Build or restore MPU
    if st and resume and st.get("UploadId") and st.get("Size") == total_size and st.get("PartSize") == part_size:
        upload_id = st["UploadId"]
        completed = {p["PartNumber"]: p["ETag"] for p in st.get("Parts", [])}
        next_part = max(completed.keys()) + 1 if completed else 1
        print(f"Resuming upload_id={upload_id}, next_part={next_part}/{parts_total}")
    else:
        resp = s3.create_multipart_upload(Bucket=bucket, Key=key)
        upload_id = resp["UploadId"]
        completed = {}
        next_part = 1
        st = {"Bucket": bucket, "Key": key, "UploadId": upload_id,
              "Size": total_size, "PartSize": part_size, "Parts": [],
              "SourceURL": real_url}
        save_state(st_path, st)
        print(f"Started multipart upload: upload_id={upload_id}")

    # SIGINT handler (soft on first press, hard on second)
    def handle_sigint(sig, frame):
        if CANCEL["mode"] == 0:
            CANCEL["mode"] = 1
            print("\nCtrl+C detected: will stop after current part. Press Ctrl+C again to abort immediately.", flush=True)
        else:
            CANCEL["mode"] = 2
            print("\nCtrl+C (again): aborting now!", flush=True)
            raise KeyboardInterrupt

    old_handler = signal.signal(signal.SIGINT, handle_sigint)

    try:
        for part_no in range(next_part, parts_total + 1):
            if CANCEL["mode"] >= 1:
                break

            if SETTINGS.get("http_session") == "on" and args.recycle_session_every > 0:
                SESSION["uses"] += 1
                if SESSION["uses"] % args.recycle_session_every == 0:
                    recycle_session(f"periodic every {args.recycle_session_every} parts")

            start = (part_no - 1) * part_size
            end = min(total_size - 1, part_no * part_size - 1)
            print(f"\nUploading part {part_no}/{parts_total} ({(end-start+1)/1024/1024:.1f} MiB) "
                  f"range {start}-{end} ...", flush=True)
            etag = upload_range_part(s3, bucket, key, upload_id, part_no, start, end, args, real_url, total_size)
            print()
            st["Parts"].append({"PartNumber": part_no, "ETag": etag})
            save_state(st_path, st)

        if CANCEL["mode"] >= 1:
            print("Cancelled by user. Leaving upload incomplete so it can be resumed.", flush=True)
            return False

        parts_sorted = sorted(st["Parts"], key=lambda x: x["PartNumber"])
        s3.complete_multipart_upload(
            Bucket=bucket, Key=key, UploadId=upload_id,
            MultipartUpload={"Parts": parts_sorted},
        )
        print("Completed multipart upload.")
        delete_state(st_path)
        return True

    except KeyboardInterrupt:
        try:
            if 'upload_id' in locals():
                print("Aborting multipart upload due to interrupt.", flush=True)
                # s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
        finally:
            delete_state(st_path)
        raise

    except Exception as e:
        print(f"Error during multipart upload: {e}", flush=True)
        print("Keeping the multipart upload open and the state file for resume.", flush=True)
        return False

    finally:
        signal.signal(signal.SIGINT, old_handler)


def fallback_tempfile_then_upload(s3, bucket, key, args, st_path, real_url):
    print("Origin lacks Range/Content-Length; falling back to temp-file download...", flush=True)
    with tempfile.NamedTemporaryFile(dir=args.fallback_tempdir, delete=False) as tf:
        tmp_path = tf.name
    try:
        with get_session().get(real_url, stream=True, timeout=(HTTP_TIMEOUT[0], args.stall_timeout)) as r:
            r.raise_for_status()
            total = int(r.headers.get("Content-Length", 0)) or None
            downloaded = 0
            last_t = time.time()
            last_bytes = 0
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=CHUNK):
                    if CANCEL["mode"] == 2:
                        raise KeyboardInterrupt
                    if not chunk:
                        now = time.time()
                        if now - last_t > args.stall_timeout and downloaded == last_bytes:
                            recycle_session("stall-timeout-fallback")
                            raise requests.ReadTimeout(f"no progress for >{args.stall_timeout}s", request=r.request)
                        continue
                    f.write(chunk)
                    downloaded += len(chunk)
                    now = time.time()
                    if total and (now - last_t >= 1.0):
                        pct = downloaded * 100.0 / total
                        print(f"\rDownloading... {pct:.1f}% ({downloaded/1024/1024:.1f} MiB)", end="", flush=True)
                        last_t = now
                        last_bytes = downloaded
        print("\nDownload complete. Uploading via multipart from disk...", flush=True)

        size = os.path.getsize(tmp_path)
        part_size = args.part_size_mib * 1024 * 1024
        parts_total = math.ceil(size / part_size)

        resp = s3.create_multipart_upload(Bucket=bucket, Key=key)
        upload_id = resp["UploadId"]
        parts = []
        try:
            with open(tmp_path, "rb") as f:
                for part_no in range(1, parts_total + 1):
                    if CANCEL["mode"] == 2:
                        raise KeyboardInterrupt
                    start = (part_no - 1) * part_size
                    f.seek(start)
                    to_read = min(part_size, size - start)
                    data = f.read(to_read)
                    kwargs = dict(
                        Bucket=bucket, Key=key, UploadId=upload_id,
                        PartNumber=part_no, Body=data, ContentLength=len(data)
                    )
                    if args.checksum == "sha256":
                        kwargs["ChecksumSHA256"] = compute_sha256_b64(data)
                    resp = with_retries(lambda: s3.upload_part(**kwargs),
                                        attempts=5, base_delay=2.0,
                                        desc=f"upload_part #{part_no}")
                    parts.append({"PartNumber": part_no, "ETag": resp["ETag"]})
            s3.complete_multipart_upload(
                Bucket=bucket, Key=key, UploadId=upload_id,
                MultipartUpload={"Parts": parts}
            )
            print("Completed multipart upload from disk.")
        except KeyboardInterrupt:
            # s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
            delete_state(st_path)
            raise
        except Exception as e:
            print(f"Error in fallback path: {e}", flush=True)
            print("Keeping state for manual resume.", flush=True)
            return False
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


def main():
    args = parse_args()
    SETTINGS["http_session"] = args.http_session

    # Decide bucket early (key ignored here)
    dummy_url = args.url or f"{LEDGER_BASE}/{args.network}/snapshot/latest.txt"
    bucket_guess, _ = derive_bucket_and_key(args.bucket, args.key, args.network, dummy_url)

    # Try to pick a consistent resume state for this network prefix
    resume_prefix = NETWORK_PREFIX[args.network]
    cand_path, cand_state = (None, None)
    if not args.force_new:
        cand_path, cand_state = pick_resume_state(args.state_dir, bucket_guess, resume_prefix)

    if cand_state and not args.force_new:
        st_path = Path(cand_path)
        bucket = cand_state["Bucket"]
        key = cand_state["Key"]
        real_url = cand_state["SourceURL"]
        print(f"Found existing CONSISTENT state to resume:\n  {st_path}\n  Key={key}\n  SourceURL={real_url}")

        # Strict resume check: saved URL must still be rangeable and same size
        try:
            size_head, ar = http_head(real_url, args.user_agent_suffix)
            if ar != "bytes":
                print(f"Resume refused: Accept-Ranges={ar} (expected 'bytes').", flush=True)
                print("Abort: saved snapshot is no longer safely rangeable. Keep state and try later or --force-new.")
                sys.exit(131)
            if size_head is not None and size_head != cand_state.get("Size"):
                print(f"Resume refused: Content-Length changed ({size_head} != saved {cand_state.get('Size')}).", flush=True)
                print("Abort: saved snapshot has changed. Keep state and try later or --force-new.")
                sys.exit(131)
        except Exception as e:
            print(f"Resume refused: HEAD to saved SourceURL failed: {e}", flush=True)
            print("Abort: saved snapshot may be gone. Keep state and try later or --force-new.")
            sys.exit(131)

        region = resolve_bucket_region(bucket, args.region)
        print(f"Using S3 region: {region}")
        s3 = s3_client(region)
        ok = multipart_upload_range_mode(s3, bucket, key, cand_state["Size"], args, st_path, resume=True, real_url=real_url)
        sys.exit(0 if ok else 130)

    # Fresh start (no state or forced)
    if args.url:
        real_url = args.url
    else:
        real_url = fetch_real_url_from_latest(args.network, args.user_agent_suffix)

    bucket, key = derive_bucket_and_key(args.bucket, args.key, args.network, real_url)
    st_path = state_file_path(args.state_dir, bucket, key)

    print(f"Network={args.network}  Bucket={bucket}  Key={key}")
    print(f"Source URL: {real_url}")

    region = resolve_bucket_region(bucket, args.region)
    print(f"Using S3 region: {region}")
    s3 = s3_client(region)

    try:
        size, accept_ranges = http_head(real_url, args.user_agent_suffix)
    except requests.RequestException as e:
        sys.exit(f"HEAD failed: {e}")

    print(f"Origin Content-Length={size}  Accept-Ranges={accept_ranges or 'n/a'}")

    if size and accept_ranges == "bytes":
        ok = multipart_upload_range_mode(s3, bucket, key, size, args, st_path, resume=False, real_url=real_url)
        sys.exit(0 if ok else 130)
    else:
        ok = fallback_tempfile_then_upload(s3, bucket, key, args, st_path, real_url)
        sys.exit(0 if ok else 130)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)

