#!/usr/bin/env bash
# pull-artifact.sh — Pull latest stress-testing artifact from GCS (runs on STM).
#
# Fetches gs://<RELEASES_BUCKET>/stress-testing/latest.tar.gz produced by
# scripts/bin/upload-artifact.sh (locally or via GitHub Actions) and
# unpacks it into ~/snarkos-stress-testing.
set -euo pipefail

BUCKET="${RELEASES_BUCKET:-provable-binaries-releases}"
DEST="${HOME}/snarkos-stress-testing"
TARBALL="/tmp/stress-testing-latest.tar.gz"

echo "==> pulling gs://${BUCKET}/stress-testing/latest.tar.gz"
gcloud storage cp "gs://${BUCKET}/stress-testing/latest.tar.gz" "$TARBALL"

echo "==> extracting into ${DEST}"
mkdir -p "$DEST"
tar xzf "$TARBALL" -C "$DEST"

rm -f "$TARBALL"
echo "Updated: ${DEST}"
