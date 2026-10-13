#!/usr/bin/env bash
set -euo pipefail
round4_root=/srv/shared/code/motoko_experiments/plugins/_build/signature-round4/integration
round4_sdk=/srv/shared/code/motoko_experiments/prepared-crypto/sdk
round4_ash=/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/ash-local
phase=${1:-}
case "$phase" in packaging|run|replay-fail|ash) ;; *) echo 'Usage: run.sh {packaging|run|replay-fail|ash}' >&2; exit 2;; esac
round4_log="$round4_root/_build/round4-validation/logs/$phase-$(date -u +%Y%m%dT%H%M%S).log"
export MOTOKO_ROOT="$round4_sdk"
export MOTOKO_CORE="$round4_root/benchmarks/crypto/dependencies/.mops/core@2.5.0/src"
export PATH="$round4_sdk/bin:$PATH"
cd "$round4_sdk"
run_phase() {
  python3 "$round4_root/_build/round4-validation/preflight.py" "$round4_log.provenance.json" || return $?
  case "$phase" in
    packaging) python3 "$round4_root/tests/packaging.py" --motoko "$round4_sdk";;
    run) test-runner -b -j 1 "$round4_root/tests/integration/run/prepared-composition.mo" "$round4_root/tests/integration/run/signature-composition.mo";;
    replay-fail) test-runner -b -j 1 "$round4_root/tests/integration/fail";;
    ash) bun "$round4_ash/src/index.ts" test "$round4_root/packages/fast/tests/ash/PreparedComposition.ash.json" --verbose;;
  esac
}
run_phase 2>&1 | tee "$round4_log"
