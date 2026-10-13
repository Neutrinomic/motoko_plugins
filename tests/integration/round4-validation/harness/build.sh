#!/usr/bin/env bash
set -euo pipefail
cd /srv/shared/code/motoko_experiments/plugins/_build/signature-round4/integration
export CARGO_BUILD_JOBS=2
export RUST_TEST_THREADS=2
scripts/build.sh --motoko /srv/shared/code/motoko_experiments/prepared-crypto/sdk --skip-motoko-build 2>&1 | tee _build/round4-validation/logs/build-all23.log
