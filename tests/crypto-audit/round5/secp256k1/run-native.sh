#!/usr/bin/env bash
# Run inside the matching SDK Nix development shell. Maximum two Cargo jobs.
set -euo pipefail
lane=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$lane/../../../.." && pwd)
mkdir -p "$root/_build"
out=${SECP_AUDIT5_OUT:-$(mktemp -d "$root/_build/secp-audit5-native.XXXXXX")}
mkdir -p "$out"
python3 "$lane/generate.py" --reference "$lane/oracle/reference.py" --check
for mode in debug release; do
  flags=()
  if [[ "$mode" == release ]]; then flags+=(--release); fi
  cargo test --locked --jobs 2 --manifest-path "$lane/native/Cargo.toml" \
    --target-dir "$out/native-target" "${flags[@]}" -- --test-threads=2 \
    >"$out/native-$mode.log" 2>&1
done
python3 "$lane/run_injected.py" --reference "$lane/oracle/reference.py" --out "$out/injected"
