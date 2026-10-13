# Tests

Run from the plugin repository inside the selected compiler checkout's Nix
shell, with its RTS already built (`make -C /path/to/motoko/rts`):

```sh
scripts/build.sh --motoko ../motoko_sha
scripts/test.sh --motoko ../motoko_sha
```

`--motoko` may name any compatible compiler checkout; `MOTOKO_ROOT` is the
equivalent environment variable. Tests load `dist/<name>` from this repository.
The script adds that compiler's `bin/` wrappers to `PATH` and invokes Motoko's
`test-runner` from the compiler checkout with absolute paths to the external
tests. It does not install or copy tests into the compiler tree.

- `plugins/<name>/tests/{run,fail,trap}` owns that plugin's behavior and errors.
- `packages/fast/tests/run` checks public `mo:fast` codec/hash imports with only
  the corresponding plugin loaded. Map tests also use the public package.
- `packages/fast/tests/{fail,trap}` checks public module compile-time rejection
  and checked-constructor failures.
- [`packages/fast/tests/ash`](../packages/fast/tests/ash/) runs public API,
  reference-model, codec vector, composition, and incremental GC tests as
  canisters on PocketIC through Ash. It has a separate runner (below).
- `tests/integration/` tests plugin composition, load order, specialization,
  allocation, and collection of retained values under forced GC.
- `tests/packaging.py` checks compiler compatibility diagnostics, package
  loading, missing/corrupt runtimes, and elimination of unused plugins.
- Rust kernel unit tests live with each `plugins/<name>/runtime` crate and run
  together through the workspace's `cargo test`.
- [`tests/crypto-audit`](crypto-audit/) holds independent cryptographic vectors
  and native/Motoko audit drivers. These standalone audits run separately from
  the workspace tests and Ash suites; see the commands below.

Motoko fixture flags use paths relative to their test directory. `run-test`
writes generated output under `_out/` beside each fixture and compares it to
`ok/`. To deliberately regenerate expectations, use
`scripts/test.sh --motoko ../motoko_sha --accept`, then review the changes.
`tests/check-expectations.py` rejects accepted compile failures in runtime
fixtures so that a failing typecheck cannot silently replace a passing test.

For the public Ash suite, first build the native plugins and select the same
compiler in Ash's toolchain (`ash bin`). Then run from this repository:

```sh
scripts/test-ash.sh
# A source checkout is supported when the installed Ash lacks mocArgs:
scripts/test-ash.sh --ash-source /path/to/ash
# Or select suites:
scripts/test-ash.sh --ash-source /path/to/ash Set PureSet SetGC
```

The runner installs the package's Mops dependencies. Ash needs canister
`mocArgs` support to load native plugins; the runner checks for it before
starting tests. See the [suite guide](../packages/fast/tests/ash/README.md)
for coverage and execution details. This runner is separate from the native
suite used by CI; its correctness-test metrics are not benchmark results.

For the independent CandidX conformance and fuzz drivers, use
[`plugins/candidx/tests/candidx-moc.py`](../plugins/candidx/tests/candidx-moc.py)
as described in the [benchmark guide](../benchmarks/README.md#candidx-repository-correctness-suite).

## Independent crypto audits

[Round-five regressions](crypto-audit/round5/README.md) run through the normal
native/public runners above. The native runner also invokes the round-five
`run-native.sh` adapters, preserving independent oracle and rare-case injection
setup; RSA's CLI oracle needs `openssl` on `PATH` or an `OPENSSL` override.
New public Ash configurations are discovered by `scripts/test-ash.sh`.

Run the audit drivers against explicit plugin directories built for the
selected compiler. Hash/codec, curve, BLS and Bitcoin audits use separate entry points:

| Audit | Runner and independent evidence |
| --- | --- |
| Hashes and codecs | [run.py](crypto-audit/hash-codec/run.py) checks native pointer/buffer contracts and public Motoko behavior using [pinned vector provenance](crypto-audit/hash-codec/vector-provenance.json), including BLAKE3, OpenSSL hash/HMAC, Bitcoin Core Base58 and BIP350 vectors. The public run loads SHA256, BLAKE3, SHA512, RIPEMD160, HMAC, Base58 and Bech32 together. |
| ECDSA curves | [run_audit.py](crypto-audit/curves/run_audit.py) uses Wycheproof plus an independent Python integer/HMAC RFC6979 oracle for secp256k1 and P256; it executes native and source/IR/lowered/Wasm checks. |
| Bitcoin composition | [run.py](crypto-audit/bitcoin/run.py) checks transaction sighashes against Bitcoin Core, independent Taproot signing vectors, address encodings and malformed inputs in the interpreter and Wasm. |
| BLS12-381 | [run.py](crypto-audit/bls/run.py) selects native, interpreter and Wasm phases; [provenance](crypto-audit/bls/provenance.json) identifies RFC9380, Ethereum and independent profile vectors. |

For example, from this repository inside the compiler's Nix shell:

```sh
python3 tests/crypto-audit/hash-codec/run.py --motoko ../motoko_sha --native-only
python3 tests/crypto-audit/curves/run_audit.py --motoko ../motoko_sha \
  --secp dist/secp256k1 --p256 dist/p256
python3 tests/crypto-audit/bls/run.py --motoko ../motoko_sha \
  --plugin dist/bls12-381
python3 tests/crypto-audit/bitcoin/run.py
```

For the full hash/codec audit, omit `--native-only` and supply seven
`--plugin NAME=DIR` arguments as listed in that runner's docstring. Driver
reports record command exit codes and source/artifact hashes. Consult those
reports for execution status; vendored vectors and source inventories alone do
not establish that an audit passed on the current build. Audit cases are
correctness checks. Instruction/allocation/Wasm-size comparisons are recorded
separately in [`benchmarks/crypto`](../benchmarks/crypto/).

The [first-round integrated validation record](crypto-audit/integration/report.json)
captures the shared build, all native/Motoko/Ash checks, fixture corrections and
reruns, packaging checks, and the exact audited artifact hashes. Its accompanying
logs retain the initial fixture failures as well as the successful reruns.

The [second-round integration record](crypto-audit/round2/integration/report.json)
checks the combined optimized build, with frozen source/artifact inventories
and complete test logs. Independent optimization audits are retained for
[hashes and codecs](crypto-audit/round2/hash-codec/final-shared-report.json),
[BLS](crypto-audit/round2/bls/report.json), and
[curves and Bitcoin](crypto-audit/round2/final-curves-bitcoin/report.json).
[Candidate audit and promotion records](crypto-audit/round2/retained/)
preserve the independent checks made before the combined build.
Performance measurements and their native Motoko counterparts appear in the
[public API benchmark table](../benchmark_crypto.md).
