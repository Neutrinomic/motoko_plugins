#!/usr/bin/env bash
# Run inside the selected Motoko checkout's Nix environment after building JSON.
set -euo pipefail

audit_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugins_root=$(cd -- "$audit_root/../../../.." && pwd)
motoko_root=${MOTOKO_ROOT:-}
audit_output="$plugins_root/_build/json-audit"
while (($#)); do
  case "$1" in
    --motoko|--output)
      if (($# < 2)); then
        echo "$1 requires a path" >&2
        exit 2
      fi
      if [[ $1 == --motoko ]]; then motoko_root=$2; else audit_output=$2; fi
      shift 2
      ;;
    --help|-h)
      echo "Usage: plugins/json/tests/audit/run.sh --motoko PATH [--output PATH]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z $motoko_root ]]; then
  echo "Pass --motoko PATH or set MOTOKO_ROOT." >&2
  exit 2
fi
motoko_root=$(cd -- "$motoko_root" && pwd)
if [[ ! -x $motoko_root/bin/moc || ! -d $motoko_root/test ]]; then
  echo "Not a built Motoko checkout: $motoko_root" >&2
  exit 2
fi
for artifact in plugin.cmxs runtime.wasm; do
  if [[ ! -f $plugins_root/dist/json/$artifact ]]; then
    echo "Missing dist/json/$artifact; build the JSON plugin first." >&2
    exit 2
  fi
done
export PATH="$motoko_root/bin:$PATH"
python3 "$audit_root/generate.py" --output "$audit_output"
audit_output=$(cd -- "$audit_output" && pwd)
cargo test --manifest-path "$audit_output/Cargo.toml" audit_ -- --nocapture
cd -- "$motoko_root"
test-runner -b "$audit_output/run"
test-runner -b -f 'json-error-gc|json-limits' \
  "$plugins_root/plugins/json/tests/run" \
  "$plugins_root/plugins/json/tests/run-drun"
