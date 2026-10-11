#!/usr/bin/env bash
# Run kernel tests and Motoko expectations against an explicitly selected host.
set -euo pipefail

plugins_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
motoko_root=${MOTOKO_ROOT:-}
accept=()
while (($#)); do
  case "$1" in
    --motoko)
      if (($# < 2)); then
        echo "--motoko requires a compiler checkout path" >&2
        exit 2
      fi
      motoko_root=$2
      shift 2
      ;;
    --accept)
      accept=(-a)
      shift
      ;;
    --help|-h)
      echo "Usage: scripts/test.sh --motoko PATH [--accept]"
      echo "Run inside the selected Motoko checkout's nix develop environment after scripts/build.sh."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done
if [[ -z "$motoko_root" ]]; then
  echo "Pass --motoko PATH or set MOTOKO_ROOT to the compiler checkout." >&2
  exit 2
fi
motoko_root=$(cd -- "$motoko_root" && pwd)
if [[ ! -x "$motoko_root/bin/moc" || ! -x "$motoko_root/src/moc" || ! -d "$motoko_root/test" ]]; then
  echo "Not a built Motoko compiler checkout: $motoko_root" >&2
  exit 2
fi
shopt -s nullglob
plugin_manifests=("$plugins_root"/plugins/*/plugin.json)
if ((${#plugin_manifests[@]} == 0)); then
  echo "No plugins/*/plugin.json manifests found." >&2
  exit 2
fi
for manifest in "${plugin_manifests[@]}"; do
  plugin_directory=${manifest%/plugin.json}
  plugin=${plugin_directory##*/}
  artifacts=(plugin.cmxs)
  if python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("runtime_crate") is None)' "$manifest"; then
    artifacts+=(runtime.wasm)
  fi
  for artifact in "${artifacts[@]}"; do
    if [[ ! -f "$plugins_root/dist/$plugin/$artifact" ]]; then
      echo "Missing dist/$plugin/$artifact; run scripts/build.sh --motoko PATH first." >&2
      exit 2
    fi
  done
done
export MOTOKO_ROOT=$motoko_root
export PATH="$motoko_root/bin:$PATH"

cd -- "$plugins_root"
cargo test --manifest-path "$plugins_root/Cargo.toml" --locked \
  --target-dir "$plugins_root/_build/native-tests"

# The runner uses the compiler's build wrappers and changes into each test's
# directory. Passing absolute paths preserves fail/run-drun flag inference and
# keeps all expectations and generated _out files in this repository.
cd -- "$motoko_root"
test_directories=()
for directory in "$plugins_root"/plugins/*/tests/{run,fail,trap,run-drun} \
                 "$plugins_root"/tests/integration/{run,fail,trap,run-drun}; do
  if [[ -d "$directory" ]]; then
    test_directories+=("$directory")
  fi
done
if ((${#test_directories[@]} == 0)); then
  echo "No Motoko test directories found." >&2
  exit 1
fi
test-runner -b "${accept[@]}" "${test_directories[@]}"
python3 "$plugins_root/tests/packaging.py" --motoko "$motoko_root"
