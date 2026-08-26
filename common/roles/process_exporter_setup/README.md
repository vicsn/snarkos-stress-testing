# process_exporter_setup

Installs `prometheus-process-exporter` from the Ubuntu universe apt repository and
manages it via systemd on port 9256.

Monitors processes by executable name (default: `snarkos`), matching the behavior
of the legacy `-procnames snarkos` docker-compose flag.

Includes a graceful cleanup step that stops any pre-existing docker-compose-based
process-exporter container before starting the systemd service, preventing port
conflicts on live cluster re-runs.

**Variables** (see `defaults/main.yml`):
- `process_exporter_listen_address` (default: `0.0.0.0:9256`)
- `process_exporter_config_path` (default: `/etc/prometheus/process_mappings.yml`)
- `process_exporter_procnames` (default: `[snarkos]`)
- `process_exporter_extra_args` (default: `""`)
