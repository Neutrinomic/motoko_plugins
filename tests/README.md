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
