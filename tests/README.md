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

For the independent CandidX conformance and fuzz drivers, use
[`plugins/candidx/tests/candidx-moc.py`](../plugins/candidx/tests/candidx-moc.py)
as described in the [benchmark guide](../benchmarks/README.md#candidx-repository-correctness-suite).
