#!/usr/bin/env bash
set -euo pipefail
audit_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugins_root=$(cd -- "$audit_dir/../../../.." && pwd)
# Match plugin.json and the deployed Wasm runtime's serial32 backend.
export CARGO_ENCODED_RUSTFLAGS=$'--cfg\x1fcurve25519_dalek_bits="32"\x1f--cfg\x1fcurve25519_dalek_backend="serial"'
exec cargo test --locked -j2 --manifest-path "$audit_dir/Cargo.toml" --lib \
  --target-dir "${CARGO_TARGET_DIR:-$plugins_root/_build/audit-native-tests}"
