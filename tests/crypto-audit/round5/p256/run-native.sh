#!/usr/bin/env bash
# Invoke in the compiler's Nix environment; dependencies and tools come from it.
set -euo pipefail
export CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=2

audit_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$audit_dir/../../../.." && pwd)
audit_build_dir=${P256_RARE_BUILD_DIR:-"$repo_root/_build/crypto-audit5-p256-rare"}
mkdir -p -- "$audit_build_dir"
exec python3 "$audit_dir/rare-signature.py" \
  --root "$repo_root" \
  --output "$audit_build_dir/report.json" \
  --target-dir "$audit_build_dir/target" \
  "$@"
