#!/usr/bin/env bash
# Exercise the public fast modules as canisters on Ash's local PocketIC.
set -euo pipefail

plugins_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ash_command=(ash)
suites=()
while (($#)); do
  case "$1" in
    --ash-source)
      if (($# < 2)); then
        echo "--ash-source requires an Ash checkout path" >&2
        exit 2
      fi
      ash_source=$(cd -- "$2" && pwd)
      ash_command=(bun "$ash_source/src/index.ts")
      shift 2
      ;;
    --help|-h)
      echo "Usage: scripts/test-ash.sh [--ash-source PATH] [MODULE ...]"
      echo "Default: all packages/fast/tests/ash/*.ash.json suites."
      echo "Requires Ash with mocArgs support, Mops, and built matching native plugins."
      echo "Ash selects moc/didc/pocket-ic from its own toolchain (ash bin)."
      exit 0
      ;;
    --*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) suites+=("$1"); shift ;;
  esac
done

if ! "${ash_command[@]}" schema | python3 -c '
import json, sys
schema = json.load(sys.stdin)
sys.exit("mocArgs" not in schema["$defs"]["canister"]["properties"])
'; then
  echo "Ash must support canister mocArgs for --plugin; use --ash-source with a current checkout." >&2
  exit 2
fi

config_directory=$plugins_root/packages/fast/tests/ash
configs=()
if ((${#suites[@]})); then
  for suite in "${suites[@]}"; do
    config=$config_directory/$suite.ash.json
    if [[ ! -f "$config" ]]; then
      echo "Unknown module suite: $suite" >&2
      exit 2
    fi
    configs+=("$config")
  done
else
  shopt -s nullglob
  configs=("$config_directory"/*.ash.json)
fi
if ((${#configs[@]} == 0)); then
  echo "No Ash module suites found." >&2
  exit 1
fi

cd -- "$plugins_root/packages/fast"
mops install
cd -- "$plugins_root"
failed=0
for config in "${configs[@]}"; do
  if ! "${ash_command[@]}" test "$config" --verbose; then
    failed=1
  fi
done
exit "$failed"
