#!/usr/bin/env bash
set -euo pipefail
AUDIT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AUDIT_ROOT=$(cd -- "$AUDIT_DIR/../../../.." && pwd)
export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR="$AUDIT_ROOT/_build/crypto-audit5/hashes-native"
cargo test --locked --manifest-path "$AUDIT_DIR/Cargo.toml" -- --test-threads=2
