#![warn(unused_imports, unused_variables)]

use anyhow::{anyhow, Context, Result};
use futures::future::join_all;
use once_cell::sync::Lazy;
use regex::Regex;
use reqwest::Client;
use serde_json::Value;
use walkdir::WalkDir;

use aws_config::BehaviorVersion;
use aws_sdk_s3::{types::Object, Client as S3Client};

use std::collections::HashSet;
use std::env;
use std::error::Error;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write as IoWrite, BufWriter};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tokio::sync::Semaphore;

// Working with two log files.
// As a whole this is ran through the Ansible setup code, so output is blocked by Ansible, we need
// output in real time, so we use these log files.
static LOG_PATH: &str = "confirmed_txs.log";
static LOG_LOCK: Lazy<Mutex<BufWriter<File>>> = Lazy::new(|| {
    let f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(LOG_PATH)
        .unwrap();
    Mutex::new(BufWriter::new(f))
});

static SEND_LOG_PATH: &str = "sender_txs.log";
static SEND_LOG_LOCK: Lazy<Mutex<BufWriter<File>>> = Lazy::new(|| {
    let f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(SEND_LOG_PATH)
        .unwrap();
    Mutex::new(BufWriter::new(f))
});

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    // Args: <network> <s3_bucket> <s3_prefix> <exec_cnt> <deploy_cnt> <target_consensus_version> <target_height>
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 8 {
        eprintln!("Usage: tx_submitter <network> <s3_bucket> <s3_prefix> <exec_cnt> <deploy_cnt> <target_consensus_version> <target_height>");
        std::process::exit(1);
    }
    let network = &args[1];
    let s3_bucket = &args[2];
    let s3_prefix = &args[3];
    let exec_cnt = &args[4];
    let deploy_cnt = &args[5];
    let target_consensus_version: i64 = args[6].parse().context("bad consensus version")?;
    let target_height: i64 = args[7].parse().context("bad height")?;
    let load_saved_type = args.get(8).map(|s| s.as_str()).unwrap_or("all");

    println!("=== TX Submitter (Rust) ===");
    println!(
        "Args: network={network}, bucket={s3_bucket}, prefix={s3_prefix}, exec_cnt={exec_cnt}, deploy_cnt={deploy_cnt}, target_consensus_version={target_consensus_version}, target_height={target_height}"
    );

    // Fresh logs each run.
    if std::path::Path::new(LOG_PATH).exists() {
        std::fs::remove_file(LOG_PATH).ok();
    }
    if std::path::Path::new(SEND_LOG_PATH).exists() {
        std::fs::remove_file(SEND_LOG_PATH).ok();
    }

    // ip_addresses.txt (The working dir is the rust project dir).
    let ip_list_path = std::env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("..")
        .join("..")
        .join("..")
        .join("ip_addresses.txt");
    let ips =
        read_ip_addresses(&ip_list_path).with_context(|| format!("reading {:?}", ip_list_path))?;
    if ips.is_empty() {
        return Err(anyhow!("No validator IPs found in {:?}", ip_list_path));
    }
    println!("Loaded {} validator IP(s). First IP: {}", ips.len(), ips[0]);

    // Temp dir for archive/extract
    let tx_root = std::env::current_dir()?
        .join("..")
        .join("..")
        .join("transaction_files");

    // Setup paths:
    std::fs::create_dir_all(&tx_root).ok();
    let archive_path = tx_root.join("transactions.zip");
    let tx_dir = tx_root.join("transaction_files");
    if tx_dir.exists() {
        std::fs::remove_dir_all(&tx_dir).ok();
    }
    std::fs::create_dir_all(&tx_dir).ok();

    // S3 download:
    let cfg = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let s3 = S3Client::new(&cfg);
    download_exact_zip(
        &s3,
        s3_bucket,
        s3_prefix,
        network,
        ips.len(),
        exec_cnt,
        deploy_cnt,
        target_consensus_version,
        target_height,
        &archive_path,
    )
    .await?;
    unzip_to(&archive_path, &tx_dir)?;

    // Read TXs into memory. All txs are in memory to not slow down when loading them file by file,
    // while sending them:
    let (deploy_lines, exec_lines) = collect_tx_lines(&tx_dir, network)?;
    println!(
        "Prepared TX lines: deploy={}, exec={}, total={}",
        deploy_lines.len(),
        exec_lines.len(),
        deploy_lines.len() + exec_lines.len()
    );

    // Build all_lines based on load_saved_type
    let all_lines: Vec<String> = match load_saved_type {
        "executions" => {
            println!("Using only execution transactions (load_saved_transactions_type=executions)");
            exec_lines
        }
        "deployments" => {
            println!("Using only deployment transactions (load_saved_transactions_type=deployments)");
            deploy_lines
        }
        "all" | "" => {
            println!("Using both deployment and execution transactions (load_saved_transactions_type=all)");
            let mut v = Vec::with_capacity(deploy_lines.len() + exec_lines.len());
            v.extend(deploy_lines);
            v.extend(exec_lines);
            v
        }
        other => {
            eprintln!(
                "Unknown load_saved_transactions_type='{}'. Defaulting to 'all' (deployments + executions).",
                other
            );
            let mut v = Vec::with_capacity(deploy_lines.len() + exec_lines.len());
            v.extend(deploy_lines);
            v.extend(exec_lines);
            v
        }
    };

    if all_lines.is_empty() {
        println!("No transactions to send. Exiting.");
        return Ok(());
    }
    let expected_ids = Arc::new(tx_ids_from_lines(&all_lines));
    println!("Collected {} expected tx id(s).", expected_ids.len());

    // These are because we are hitting "too many open files" otherwise:
    let per_ip_limit = parse_env_usize(
        "TX_PER_IP_LIMIT",
        std::cmp::max(256usize, all_lines.len() / ips.len()),
    );
    let overall_limit = parse_env_usize(
        "TX_OVERALL_LIMIT",
        std::cmp::min(all_lines.len(), 2000usize),
    );

    // ---- Build two separate clients: small one for scanner, modest one for sender ----
    let scan_client = Client::builder()
        .pool_max_idle_per_host(4)
        .pool_idle_timeout(Some(Duration::from_secs(10)))
        .connect_timeout(Duration::from_secs(3))
        .timeout(Duration::from_secs(5))
        .tcp_keepalive(Duration::from_secs(30))
        .build()?;

    let send_client = Client::builder()
        .http2_adaptive_window(true)
        .pool_max_idle_per_host(std::cmp::min(per_ip_limit, 64)) // Tried with 128, but again am
                                                                 // getting the too many files..
        .pool_idle_timeout(Some(Duration::from_secs(10)))
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(6))
        .tcp_keepalive(Duration::from_secs(30))
        .build()?;

    // Start block scanner (concurrent), baseline at current latest height
    let first_ip = ips[0].trim().to_string();
    let start_height = match get_latest_height(&scan_client, &first_ip, network).await {
        Ok(h) => h, // Modify here manually to start from a specific block, if needed.
        Err(e) => {
            eprintln!("Failed to fetch latest height, defaulting to 1: {e}");
            1
        }
    };
    println!("Scanner baseline latest_height={start_height}");

    let scanner_expected_total = expected_ids.len();
    let scanner_expected_ids = expected_ids.clone();
    let client_for_scanner = scan_client.clone();
    let network_scanner = network.to_string();
    let first_ip_scanner = first_ip.clone();
    let scanner_task = tokio::spawn(async move {
        block_scanner(
            &client_for_scanner,
            &first_ip_scanner,
            &network_scanner,
            scanner_expected_total,
            scanner_expected_ids,
            start_height,
            2,  // poll_interval seconds
            20, // max_idle_blocks
            20, // max_exceptions
        )
        .await;
    });

    // --- Measure only the send phase (using the sender client) ---
    let t0 = Instant::now();
    let (ok_count, err_count, first_ok, last_ok) = blast_all(
        &send_client,
        network,
        &ips,
        &all_lines,
        per_ip_limit,
        overall_limit,
        t0,
    )
    .await;
    let dt = t0.elapsed().as_secs_f64();
    // The measured time is not very correct as if we look in the logs of the sender,
    // the first and last transaction times and substract them, we get 2-3 times faster.
    // This is because of timeouts when sending and then checking.

    // Explicitly drop the sender client now to free sockets/FDs early
    drop(send_client);

    println!(
        "Blast complete: ok={} err={} total={} time={:.3}s rate={:.0} req/s",
        ok_count,
        err_count,
        all_lines.len(),
        dt,
        (all_lines.len() as f64 / dt) as usize
    );

    if let (Some(f), Some(l)) = (first_ok, last_ok) {
        let window = l - f;
        println!(
            "Effective success window: {:.3}s (first-ok at {:.3}s, last-ok at {:.3}s)",
            window, f, l
        );
    }

    // --- end of measured section ---

    // Wait for scanner to finish (it exits when all confirmed or idle threshold)
    let _ = scanner_task.await;

    // Cleanup temp dir (optional)
    std::fs::remove_file(&archive_path).ok();
    std::fs::remove_dir_all(&tx_root).ok();

    Ok(())
}

fn read_ip_addresses(path: &Path) -> Result<Vec<String>> {
    let content = std::fs::read_to_string(path)?;
    let mut ips: Vec<String> = content
        .lines()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    ips.dedup();
    Ok(ips)
}

async fn download_exact_zip(
    s3: &S3Client,
    bucket: &str,
    prefix: &str,
    network: &str,
    num_validators: usize,
    exec_cnt: &str,
    deploy_cnt: &str,
    target_consensus_version: i64,
    target_height: i64,
    out_path: &Path,
) -> Result<()> {
    let want_prefix =
        format!("{prefix}/transactions-{network}-{num_validators}val-{target_consensus_version}-{target_height}-");
    let want_suffix = format!("-{exec_cnt}-{deploy_cnt}.zip");

    println!("S3 search s3://{bucket}/{prefix} for exact archive…");

    let mut token: Option<String> = None;
    let mut best: Option<Object> = None;

    loop {
        let mut req = s3.list_objects_v2().bucket(bucket).prefix(format!(
            "{prefix}/transactions-{network}-{num_validators}val-"
        ));
        if let Some(t) = &token {
            req = req.continuation_token(t);
        }
        let resp = req.send().await?;

        for o in resp.contents() {
            let Some(key) = o.key() else { continue };
            if key.starts_with(&want_prefix) && key.ends_with(&want_suffix) {
                best = match best.take() {
                    None => Some(o.clone()),
                    Some(prev) => {
                        let newer = match (o.last_modified(), prev.last_modified()) {
                            (Some(a), Some(b)) => a > b,
                            (Some(_), None) => true,
                            _ => false,
                        };
                        if newer {
                            Some(o.clone())
                        } else {
                            Some(prev)
                        }
                    }
                };
            }
        }

        token = resp.next_continuation_token().map(|s| s.to_string());
        if resp.is_truncated() != Some(true) {
            break;
        }
    }

    let chosen = best.ok_or_else(|| {
        anyhow!(
            "No zip matched height={target_height} for prefix='{}*' suffix='{}'",
            want_prefix,
            want_suffix
        )
    })?;
    let key = chosen
        .key()
        .ok_or_else(|| anyhow!("Chosen object has no key"))?;
    println!("Chosen: s3://{bucket}/{key}");

    // Download to file with Tokio I/O
    let body = s3.get_object().bucket(bucket).key(key).send().await?;
    let mut reader = body.body.into_async_read();
    let mut out = tokio::fs::File::create(out_path).await?;
    tokio::io::copy(&mut reader, &mut out).await?;
    println!("Downloaded to {:?}", out_path);
    Ok(())
}

fn unzip_to(archive_path: &Path, out_dir: &Path) -> Result<()> {
    let mut f = File::open(archive_path)?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)?;
    let reader = std::io::Cursor::new(buf);
    let mut zip = zip::ZipArchive::new(reader)?;
    for i in 0..zip.len() {
        let mut file = zip.by_index(i)?;
        let outpath = out_dir.join(file.name());
        if file.name().ends_with('/') {
            std::fs::create_dir_all(&outpath).ok();
            continue;
        }
        if let Some(p) = outpath.parent() {
            std::fs::create_dir_all(p).ok();
        }
        let mut outfile = File::create(&outpath)?;
        std::io::copy(&mut file, &mut outfile)?;
    }
    Ok(())
}

fn collect_tx_lines(tx_dir: &Path, network: &str) -> Result<(Vec<String>, Vec<String>)> {
    let re_deploy = Regex::new(&format!(r"^deploys-{network}-\d+val-\d+-\d+\.txt$"))?;
    let re_exec = Regex::new(&format!(r"^executions-{network}-\d+val-\d+-\d+\.txt$"))?;

    let mut deploy_lines = Vec::new();
    let mut exec_lines = Vec::new();

    let mut total_files = 0usize;
    let mut matched_files = 0usize;

    for entry in WalkDir::new(tx_dir).into_iter().filter_map(Result::ok) {
        if !entry.file_type().is_file() {
            continue;
        }
        total_files += 1;

        let name_os = entry.file_name();
        let name = name_os.to_string_lossy();

        let class = if re_deploy.is_match(&name) {
            matched_files += 1;
            "deploy"
        } else if re_exec.is_match(&name) {
            matched_files += 1;
            "exec"
        } else {
            continue;
        };

        let path = entry.path();
        let content =
            std::fs::read_to_string(path).with_context(|| format!("reading {:?}", path))?;

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            match class {
                "deploy" => deploy_lines.push(line.to_string()),
                _ => exec_lines.push(line.to_string()),
            }
        }
    }

    if deploy_lines.is_empty() && exec_lines.is_empty() {
        let mut samples: Vec<String> = WalkDir::new(tx_dir)
            .into_iter()
            .filter_map(Result::ok)
            .filter(|e| e.file_type().is_file())
            .take(12)
            .map(|e| e.file_name().to_string_lossy().to_string())
            .collect();
        samples.sort();
        eprintln!(
            "WARNING: Found {total_files} files under {:?}, matched {matched_files}. \
             First few basenames: {samples:?}",
            tx_dir
        );
    }

    deploy_lines.shrink_to_fit();
    exec_lines.shrink_to_fit();
    Ok((deploy_lines, exec_lines))
}

/// Extract expected tx ids from tx payload lines.
fn tx_ids_from_lines(lines: &[String]) -> HashSet<String> {
    let mut ids = HashSet::with_capacity(lines.len());
    for l in lines {
        if let Ok(v) = serde_json::from_str::<Value>(l) {
            if let Some(id) = v.get("id").and_then(|x| x.as_str()) {
                if id.starts_with("at1") {
                    ids.insert(id.to_string());
                }
            }
        }
    }
    ids
}

/// Broadcasts all pregenerated transaction payloads to validator nodes in
/// parallel, performing asynchronous HTTP POST requests.
///
/// - Each transaction line (JSON) is sent to a `/transaction/broadcast`
///   endpoint on a validator, round-robin distributed across all IPs.
/// - Concurrency is limited globally by `overall_limit` and per node by
///   `per_ip_limit` using Tokio semaphores.
/// - Uses the provided `reqwest::Client` for connection reuse and timeouts.
/// - Each send attempt is logged to `sender_txs.log` (via `slogf`):
///     * On success: logs the expected transaction ID as sent (we no longer
///       read the echoed body for speed).
///     * On failure: logs HTTP status or detailed network error chain.
/// - The function waits for all requests to complete before returning.
/// - Success entries look like:
///   ```text
///   [2025-10-28 13:30:52] [Exec] TX sent : at1xyz...
///   ```
/// - HTTP or network errors include response snippets or cause chains.
/// - Logs are thread-safe and written concurrently from all tasks.
///
/// # Parameters
/// * `client` — the HTTP client used for sending (usually the “sender” client
///   with a moderate pool size and timeouts).
/// * `network` — network name (e.g. `"testnet"`), used in the broadcast URL.
/// * `ips` — list of validator IPs (each must serve port `3030`).
/// * `tx_lines` — vector of raw JSON transaction payloads (each line is sent
///   verbatim as body).
/// * `per_ip_limit` — maximum concurrent in-flight requests per validator.
/// * `overall_limit` — global cap on all concurrent in-flight requests.
/// * `start` — Instant captured before sending starts; used to compute the
///   effective timing window of successful sends.
///
/// # Returns
/// `(ok_count, err_count, first_ok, last_ok)` — numbers of successfully and
/// unsuccessfully sent transactions, plus timestamps (seconds since `start`)
/// of the earliest and latest successful send (if any).
///
/// - Designed for extremely high concurrency, but still bounded by semaphores because of the FD
/// problems - too many open files.
/// - Connection reuse keeps throughput high; typical rates >900 req/s even
///   under moderate limits.
/// - Intended to run while the block scanner runs concurrently.
/// - The send phase’s duration is measured in `main()` for throughput stats.
async fn blast_all(
    client: &Client,
    network: &str,
    ips: &[String],
    tx_lines: &[String],
    per_ip_limit: usize,
    overall_limit: usize,
    start: Instant,
) -> (usize, usize, Option<f64>, Option<f64>) {
    let overall = Arc::new(Semaphore::new(overall_limit));
    let per_ip: Vec<Arc<Semaphore>> =
        ips.iter().map(|_| Arc::new(Semaphore::new(per_ip_limit))).collect();

    let urls: Vec<String> = ips
        .iter()
        .map(|ip| format!("http://{}:3030/{}/transaction/broadcast", ip.trim(), network))
        .collect();

    let first_ok = Arc::new(Mutex::new(None::<f64>));
    let last_ok = Arc::new(Mutex::new(None::<f64>));

    let mut futs = Vec::with_capacity(tx_lines.len());
    for (i, payload) in tx_lines.iter().enumerate() {
        let idx = i % urls.len();
        let url = urls[idx].clone();
        let client = client.clone();
        let p = payload.clone();
        let exp_id = extract_id_from_payload(&p);

        let overall_sem = overall.clone();
        let ip_sem = per_ip[idx].clone();
        let first_ok_clone = first_ok.clone();
        let last_ok_clone = last_ok.clone();

        let fut = async move {
            // meddle@2025-10-28: I couldn't fix the too many open files problems on my mac, but
            // another runner on another machine maybe will, meaning we can just pass 6000 as
            // limits or remove these:
            let _op = overall_sem.acquire_owned().await.map_err(|e| anyhow!(e))?;
            let _ip = ip_sem.acquire_owned().await.map_err(|e| anyhow!(e))?;

            let rsp = client
                .post(&url)
                .header("content-type", "application/json")
                .body(p)
                .send()
                .await;

            match rsp {
                Ok(r) if r.status().is_success() => {
                    // Fast path: don't read the body at all on success – just log expected id.
                    if let Some(exp) = exp_id {
                        slogf(&format!("[Exec] TX sent : {}", exp));
                    } else {
                        slogf("[Exec] TX sent : <unknown-id>");
                    }

                    // Track earliest and latest successful send times (relative to `start`).
                    let elapsed = start.elapsed().as_secs_f64();
                    {
                        let mut f = first_ok_clone.lock().unwrap();
                        if f.is_none() || elapsed < f.unwrap() {
                            *f = Some(elapsed);
                        }
                    }
                    {
                        let mut l = last_ok_clone.lock().unwrap();
                        if l.is_none() || elapsed > l.unwrap() {
                            *l = Some(elapsed);
                        }
                    }

                    Ok::<(), anyhow::Error>(())
                }
                Ok(r) => {
                    let status = r.status();
                    let body = r.text().await.unwrap_or_default();
                    let snippet = if body.len() > 200 { &body[..200] } else { &body };
                    slogf(&format!(
                        "[Exec] HTTP error {} for {} (body: {:?})",
                        status, url, snippet
                    ));
                    Err(anyhow!("HTTP {}", status))
                }
                Err(e) => {
                    let mut err_chain = format!("{e}");
                    let mut src = e.source();
                    while let Some(s) = src {
                        err_chain.push_str(&format!("; caused by: {s}"));
                        src = s.source();
                    }
                    slogf(&format!("[Exec] Network error for {} -> {}", url, err_chain));
                    Err(anyhow!(err_chain))
                }
            }
        };
        futs.push(tokio::spawn(fut));
    }

    let results = join_all(futs).await;
    let mut ok = 0usize;
    let mut err = 0usize;
    for r in results {
        match r {
            Ok(Ok(())) => ok += 1,
            _ => err += 1,
        }
    }

    let first_ok_val = *first_ok.lock().unwrap();
    let last_ok_val = *last_ok.lock().unwrap();
    (ok, err, first_ok_val, last_ok_val)
}

// ---------------- Block scanner ----------------

/// Continuously scans new blocks for the appearance of expected
/// transaction IDs, logging confirmations and progress to `confirmed_txs.log`.
///
/// - Periodically fetches the latest block height (`/block/height/latest`).
/// - Iterates forward from `start_height`, fetching `/block/<height>` JSONs
///   and examining their `"transactions"` arrays.
/// - For each transaction found, if its `"id"` exists in `expected_ids` and
///   was not already confirmed, the ID is logged as confirmed and added to
///   the `matched` set.
/// - Stops when all expected IDs are confirmed, or after `max_idle_blocks`
///   consecutive new blocks contain no expected transactions.
/// - Also stops early if more than `max_exceptions` consecutive network or
///   parsing errors occur.
///
/// Logs are written to `confirmed_txs.log` (thread-safe via `LOG_LOCK`):
/// - Each block’s height and transaction count are logged.
/// - Each confirmed transaction is logged with its block number.
/// - Progress (confirmed/remaining counts) is periodically printed.
/// - On termination, a summary of unconfirmed transactions (up to 200 IDs)
///   is logged if any remain.
///
/// # Parameters
/// * `client` — an async HTTP client (used with small connection pool).
/// * `ip` — the validator node to query (e.g. `"34.222.19.25"`).
/// * `network` — the network name (e.g. `"testnet"`).
/// * `expected_tx_count` — total number of transaction IDs expected.
/// * `expected_ids` — shared `Arc<HashSet<String>>` of IDs to confirm.
/// * `start_height` — height from which to begin scanning (usually baseline
///   height before sending transactions).
/// * `poll_interval_secs` — seconds to wait between new height checks.
/// * `max_idle_blocks` — maximum consecutive blocks without confirming any
///   expected transaction before giving up.
/// * `max_exceptions` — maximum consecutive HTTP or parsing failures before
///   stopping.
///
/// - Designed to run concurrently with the transaction sender.
/// - Uses small HTTP pool and per-request timeouts to avoid FD exhaustion, which with the sender
/// can happen easily.
/// - Intended to work like the previous Python scanner code.
async fn block_scanner(
    client: &Client,
    ip: &str,
    network: &str,
    expected_tx_count: usize,
    expected_ids: Arc<HashSet<String>>,
    start_height: i64,
    poll_interval_secs: u64,
    max_idle_blocks: i64,
    max_exceptions: usize,
) {
    use tokio::time::{sleep, Duration};

    let mut checked_height = start_height;
    let mut matched: HashSet<String> = HashSet::with_capacity(expected_tx_count);
    let mut blocks_since_last_expected: i64 = 0;
    let mut exceptions_count = 0usize;

    logf(&format!(
        "Scanner starting at height={checked_height} (expected_tx_count={expected_tx_count}, max_idle_blocks={max_idle_blocks})"
    ));

    loop {
        let latest_height = match get_latest_height(client, ip, network).await {
            Ok(h) => h,
            Err(e) => {
                let mut err_chain = format!("{e}");
                let mut source_opt = e.source();
                while let Some(src) = source_opt {
                    err_chain.push_str(&format!("; caused by: {src}"));
                    source_opt = src.source();
                }
                logf(&format!("Scanner warning (latest height): {err_chain}"));
                exceptions_count += 1;
                if exceptions_count >= max_exceptions {
                    logf(&format!(
                        "Scanner stopping: {max_exceptions} consecutive exceptions."
                    ));
                    return;
                }
                sleep(Duration::from_secs(poll_interval_secs)).await;
                continue;
            }
        };

        if checked_height > latest_height {
            sleep(Duration::from_secs(poll_interval_secs)).await;
            continue;
        }

        logf(&format!(
            "Scanner loop: checked_height={checked_height}, latest_height={latest_height}"
        ));

        while checked_height <= latest_height {
            let block_url = format!("http://{}:3030/{}/block/{}", ip, network, checked_height);
            match client
                .get(&block_url)
                .timeout(Duration::from_secs(8))
                .send()
                .await
            {
                Ok(resp) if resp.status().is_success() => {
                    exceptions_count = 0;
                    let block = match resp.json::<Value>().await {
                        Ok(v) => v,
                        Err(e) => {
                            logf(&format!("Failed to parse block {checked_height} json: {e}"));
                            checked_height += 1;
                            continue;
                        }
                    };

                    let tx_count = block
                        .get("transactions")
                        .and_then(|t| t.as_array())
                        .map(|a| a.len())
                        .unwrap_or(0);
                    logf(&format!("Block {checked_height}: {tx_count} tx(s)"));

                    let mut new_ids: HashSet<String> = HashSet::new();
                    if let Some(txs) = block.get("transactions").and_then(|t| t.as_array()) {
                        for t in txs {
                            if let Some(id) = t
                                .get("transaction")
                                .and_then(|tr| tr.get("id"))
                                .and_then(|x| x.as_str())
                            {
                                new_ids.insert(id.to_string());
                            }
                        }
                    }

                    let prev_confirmed = matched.len();
                    for id in new_ids {
                        if expected_ids.contains(&id) && !matched.contains(&id) {
                            logf(&format!("CONFIRMED tx={id} in block {checked_height}"));
                            matched.insert(id);
                        }
                    }

                    let confirmed_now = matched.len() - prev_confirmed;
                    if confirmed_now > 0 {
                        blocks_since_last_expected = 0;
                    } else {
                        blocks_since_last_expected += 1;
                    }

                    let remaining = expected_tx_count.saturating_sub(matched.len());
                    logf(&format!(
                        "Progress: confirmed={}/{} (remaining={})",
                        expected_tx_count - remaining,
                        expected_tx_count,
                        remaining
                    ));

                    if matched.len() >= expected_tx_count {
                        logf("All expected transactions confirmed. Scanner exiting.");
                        return;
                    }

                    if !expected_ids.is_empty() && blocks_since_last_expected >= max_idle_blocks {
                        logf(&format!("Scanner stopping: {max_idle_blocks} consecutive blocks without expected confirmations."));
                        let mut rem: Vec<&String> = expected_ids.difference(&matched).collect();
                        rem.sort();
                        logf("Unconfirmed TX list (first up to 200):");
                        for (i, id) in rem.iter().take(200).enumerate() {
                            logf(&format!("  {}: {}", i + 1, id));
                        }
                        if rem.len() > 200 {
                            logf(&format!("... ({} more)", rem.len() - 200));
                        }
                        return;
                    }

                    checked_height += 1;
                }
                Ok(resp) => {
                    logf(&format!(
                        "Failed to fetch block {checked_height}: http {}",
                        resp.status()
                    ));
                    checked_height += 1;
                }
                Err(e) => {
                    let mut err_chain = format!("{e}");
                    let mut source_opt = e.source();
                    while let Some(src) = source_opt {
                        err_chain.push_str(&format!("; caused by: {src}"));
                        source_opt = src.source();
                    }
                    logf(&format!(
                        "Scanner warning (fetch block {checked_height}): {err_chain}"
                    ));
                    exceptions_count += 1;
                    if exceptions_count >= max_exceptions {
                        logf(&format!(
                            "Scanner stopping: {max_exceptions} consecutive exceptions."
                        ));
                        return;
                    }
                    sleep(Duration::from_secs(poll_interval_secs)).await;
                    break; // break inner loop to recheck latest height
                }
            }
        }
        sleep(std::time::Duration::from_secs(poll_interval_secs)).await;
    }
}

async fn get_latest_height(client: &Client, ip: &str, network: &str) -> Result<i64> {
    let url = format!("http://{}:3030/{}/block/height/latest", ip, network);
    let rsp = client
        .get(url)
        .timeout(Duration::from_secs(5))
        .send()
        .await?;
    if !rsp.status().is_success() {
        return Err(anyhow!("latest height http {}", rsp.status()));
    }
    let text = rsp.text().await?.trim().to_string();
    let h: i64 = text.parse().context("parse latest height")?;
    Ok(h)
}

// ---------- Helpers ----------

fn parse_env_usize(key: &str, default: usize) -> usize {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn extract_id_from_payload(line: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(line)
        .ok()
        .and_then(|v| v.get("id")?.as_str().map(|s| s.to_string()))
        .filter(|s| s.starts_with("at1"))
}

// ---------- Logger functions ----------

fn logf(msg: &str) {
    use chrono::Local;
    use std::io::Write;

    let ts = Local::now().format("%F %T");
    let line = format!("[{}] {}\n", ts, msg);

    let mut w = LOG_LOCK.lock().unwrap();
    let _ = w.write_all(line.as_bytes());
    let _ = w.flush();
}

fn slogf(msg: &str) {
    use chrono::Local;
    let ts = Local::now().format("%F %T");
    let line = format!("[{}] {}\n", ts, msg);
    let mut w = SEND_LOG_LOCK.lock().unwrap();
    let _ = w.write_all(line.as_bytes());
}
