# Prometheus snapshots

Prometheus snapshots can be used in a local setup to run Prometheus with data from another Prometheus.
This script creates a snapshot of the Prometheus that ran with the data of the SnarkOS nodes and tars it.

This snapshot can be un-archived locally in a folder and then running Prometheus locally with the option `--storage.tsdb.path`,
pointing to that folder will run Prometheus with the snapshotted metrics.

If that prometheus is accessible from a Grafana instance, it can be added as a [source to it](https://grafana.com/docs/grafana/latest/datasources/prometheus/configure-prometheus-data-source/).

This is an experimental feature and may need improvements in the future, but its idea is to be used when the test runner doesn't have Grafana access.
