# Log analysis scripts

This folder contains scripts for analyzing and visualizing the logs:
* to visualize the consensus process of validators.
* to visualize the syncing of nodes (validators or clients).
* to analyze the transaction propagation for validators.
* to visualize the peer message processing times for validators.

It also contains a common log preparation file `analysis_01_prepare_logfile.py` that you need to run first. For this, you need to pass a relative path with the `--logpath` argument. For example, `python3 analysis_01_prepare_logfile.py --logpath aws-logs/client-0.log` will create a file `aws-logs/prepared_client-0.log`. You can also pass an entire folder of logs, e.g., `python3 analysis_01_prepare_logfile.py --logpath aws-logs` will create a folder `prepared_aws-logs`. Which mode you need depends on the task, please refer to the descriptions below.

Note that it is not advisable to do both profiling steps (consensus and syncing) for the same validator or even for the same network, rather use different network runs.

# Validator consensus profiling
To profile the validator consensus process:
* Obtain logs from a snarkOS validator that runs a `malice` branch, thus outputting `profiling` logs.
* Place the logs in a subfolder here (e.g., `/aws-logs/val-0.log`).
* Run `analysis_01_prepare_logfile.py`, which stores a prepared log file. Example command: `python3 analysis_01_prepare_logfile.py --logpath aws-logs/validator-0.log`.
* Run `analysis_02_val_consensus_profiling.py`, which creates four different plots: the validator consensus steps per round, the block times, the number of transmissions per block, and the number of associated rounds per block. Example command: `python3 analysis_02_val_consensus_profiling.py --logfile aws-logs/prepared_validator-0.log`.

# Sync profiling
To visualize the validator or client syncing, and to compute the syncing speed, proceed as follows:
* Start a network of validators except for one validator, or except for one client.
* Wait for it to advance to a block height of your choice.
* Start the last validator or client that will sync. It should run a `malice` branch outputting `SYNCPROFILING` logs.
* Wait for the validator/client to be synced. For the validator case, specifically wait for it to participate in consensus (wait for the first `Signed a batch for round` log as a reference for speed measurement).
* Place the logs in a subfolder (e.g., `/aws-logs/validator-0.log`).
* Run `analysis_01_prepare_logfile.py`, which stores a prepared log file. Example command: `python3 analysis_01_prepare_logfile.py --logpath aws-logs/validator-0.log`.
* Run `analysis_02_sync_profiling.py`, which creates a plot and outputs the syncing speed. Example command: `python3 analysis_02_sync_profiling.py --logfile aws-logs/prepared_validator-0.log`.

# Transaction propagation analysis
To analyze the tx propagation:
* Run a network with tx-cannons and obtain the logs of all validators.
* Place the logs in a subfolder here.
* Run the preparation script for the entire folder of logs. Example command: `python3 analysis_01_prepare_logfile.py --logpath aws-logs`.
* Run `analysis_02_val_tx_propagation_analysis.py`, which creates plots and outputs statistics of the transaction propagation. Example command: `python3 analysis_02_val_tx_propagation_analysis.py --logpath prepared_aws-logs`.

# Validator peer message profiling
To visualize the validator peer message processing:
* Obtain logs from a snarkOS validator that runs a `malice` branch, thus outputting `profiling` logs.
* Place the logs in a subfolder here (e.g., `/aws-logs/`).
* Run the preparation script for the entire folder of logs. Example command: `python3 analysis_01_prepare_logfile.py --logpath aws-logs` (you can alternatively run it only for a single file).
* Run `analysis_02_analyze_logfile.py`, which creates a plot, and also prints if detecting an unexpected order of logs. Example command: `python3 analysis_02_val_consensus_profiling.py --logpath aws-logs/prepared_validator-0.log`. The `--logpath` argument is required, you can also pass an entire folder to compute an average across validators. Furthermore, you can pass an optional integer `--round_start_avg` argument to compute the printed average values from a later round (e.g., after the tx-cannon was active), and an optional integer `--round_limit` argument to limit the plotting and the printed average values up to a certain amount (e.g., before the network tear down process was initiated).

# Mempool and transmission request analysis
To analyze whether requested transmissions have been in the mempool:
* Obtain logs from a snarkOS validator that runs a `malice` branch, thus outputting the required logs.
* Place the logs in a subfolder here (e.g., `/aws-logs/`).
* Run the preparation script for the entire folder of logs. Example command: `python3 analysis_01_prepare_logfile.py --logpath aws-logs` (you can alternatively run it only for a single file).
* Run `analysis_02_transmission_consensus_queues.py`, which outputs the analysis. Example command: `python3 analysis_02_transmission_consensus_queues.py --logfile prepared_aws-logs/prepared_validator-0.log`.

# Flamegraph analysis
To count frequently occuring tasks from a flamegraph, you can use:
`python3 analysis_flamegraph_svg.py ../test_suites/single-region-tests/log_files/val-0.svg`
