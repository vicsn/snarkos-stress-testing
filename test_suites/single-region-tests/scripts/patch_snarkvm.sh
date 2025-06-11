#!/bin/bash

set -euo pipefail

export SNARKVM_VERSION=$(cargo metadata --format-version=1 | jq -r '.packages[] | select(.name == "snarkvm-console-network") | .version' | head -n 1)
curl -L https://crates.io/api/v1/crates/snarkvm-console-network/$SNARKVM_VERSION/download -o snarkvm-console-network.tar.gz
tar -xzf snarkvm-console-network.tar.gz
mv snarkvm-console-network-$SNARKVM_VERSION patched-snarkvm-console-network

cat <<EOF >> Cargo.toml

[patch.crates-io]
snarkvm-console-network = { path = "./patched-snarkvm-console-network" }
EOF

build_rs_file="build.rs"
patch_file="patched-snarkvm-console-network/src/$1_v0.rs"

# Sed is different on linux (gnu) and mac (unix) so we check the version for all runs of it.

# Replace license check as we patch and it fails
[[ $(sed --version 2>/dev/null) ]] \
  && sed -i 's|contents == EXPECTED_LICENSE_TEXT|true|' "$build_rs_file" \
  || sed -i '' 's|contents == EXPECTED_LICENSE_TEXT|true|' "$build_rs_file"

multiplier=20

max_consensus_version=$(grep -o 'ConsensusVersion::V[0-9]\+' $patch_file | sed 's/.*V//' | sort -n | tail -n1)
echo "MAX ConsensusVersion is: $max_consensus_version"

# Patch consensus versions
for version in $(seq 2 "$max_consensus_version"); do
  height=$((version * multiplier))
  [[ $(sed --version 2>/dev/null) ]] \
    && sed -i "s|(ConsensusVersion::V${version}, [0-9_]\+)|(ConsensusVersion::V${version}, ${height})|" "$patch_file" \
    || sed -i '' "s|(ConsensusVersion::V${version}, [0-9_]\{1,\})|(ConsensusVersion::V${version}, ${height})|" "$patch_file"
done
