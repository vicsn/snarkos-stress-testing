# node_exporter_setup

Installs `prometheus-node-exporter` from the Ubuntu universe apt repository and
manages it via systemd on port 9100.

Includes a graceful cleanup step that stops any pre-existing docker-compose-based
node-exporter container before starting the systemd service, preventing port
conflicts on live cluster re-runs.

**Variables** (see `defaults/main.yml`):
- `node_exporter_listen_address` (default: `0.0.0.0:9100`)
- `node_exporter_extra_args` (default: `""`)
