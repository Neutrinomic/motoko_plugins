# Prepared cryptographic keys

This protocol compares a direct public call with preparation followed by reuse, using the **same prepared-capable plugin artifacts, compiler, RTS, fixtures and independently derived oracle**. Earlier crypto benchmark archives remain unchanged.

Each case runs on three fresh PocketIC canisters. IC time is fixed and calls advance explicitly; the actors have no wall-clock-driven behavior. One benchmark runner may run beside capped builds/tests on the same host. Host isolation is not claimed and elapsed host time is not compared. `configure()` sets up inputs outside the measured interval. `run()` records instructions, allocated and reclaimed bytes; `bytesResult()` checks the exact operation result afterward. Preparation cases keep the new key and execute the operation only in `bytesResult()`, so all three modes share the same oracle. Prepared-call cases create their key in `configure()`.

Use `common.actor(..., memory_metrics=True)` or implement its interface. The actor's prepared key must be a transient field. The runner queries heap occupancy and Wasm capacity before the run, after the run message, and after four further GC increments. These snapshots are neither true peaks nor proof of retained live data; actual collection and release require separate pressure tests. `payload_bytes` describes the explicit prepared representation, excluding ordinary managed-object overhead.

A scheme owns `prepared/<scheme>/cases.json`, self-contained actor sources, generator and copied independent fixture data. Each manifest case has this shape (paths relative to `benchmarks/crypto`):

```json
{
  "name": "ed25519-verify-rfc8032-1-direct",
  "implementation": "native",
  "family": "ed25519",
  "plugins": ["ed25519"],
  "source": "prepared/ed25519/cases/verify-direct/main.mo",
  "expected_hex": "01",
  "memory_metrics": true,
  "prepared": {
    "scheme": "ed25519",
    "profile": "RFC8032",
    "operation": "verify",
    "fixture": "rfc8032-1",
    "fixture_source": "prepared/ed25519/fixtures.json",
    "comparison_group": "ed25519-verify-rfc8032-1",
    "mode": "direct",
    "reuse": 1,
    "payload_bytes": 0
  }
}
```

Each comparison group needs `direct`, `prepare` and `prepared` modes with `reuse: 1`. Their fixture ID/file and `expected_hex` agree. Preparation and prepared-call payload sizes agree; direct uses zero. The builder adds `fixture_sha256` from the exact fixture file. Keep prepared keys rooted through result checking. Do not output or expose their private bytes.

Additional `direct` and `prepared` rows can measure bounded batches with `reuse: 2`, `10` or `100`; these measure repeated operations only, with preparation outside their timed interval. The report shows them separately from fixture-specific modeled end-to-end costs `preparation + N × prepared call` versus `N × direct call`. For costly operations, use the labeled model and actual cross-message reuse tests rather than oversized message batches. Modeled break-even is not a universal threshold: fixed harness costs and garbage collection can affect real batches. No empty-loop subtraction is applied. Optional `cold` rows measure the factory and N operations together inside the interval; they are reported as actual costs including setup. A standalone `control` row, in its own comparison group, records a key-generation or direct public-key operation without claiming a prepared speedup. Controls use `reuse: 1`.

Build from the integration worktree using explicit, matching compiler paths. Use the actual `src/moc` executable, not the `bin/moc` build wrapper; its hash must match the plugin build manifest:

```sh
python3 benchmarks/crypto/prepared/build.py \
  --stage prepared-ed25519-final \
  --manifest /path/to/lane/benchmarks/crypto/prepared/ed25519/cases.json \
  --case-root /path/to/lane/benchmarks/crypto \
  --plugin-roots /path/to/plugin-roots.json \
  --fast-root /path/to/lane/packages/fast/src \
  --moc /path/to/prepared-sdk/src/moc --bundle /path/to/prepared-sdk/rts

node benchmarks/crypto/prepared/results/prepared-ed25519-final/inputs/benchmarks/crypto/prepared/run.mjs \
  --build benchmarks/crypto/prepared/results/prepared-ed25519-final/build.json \
  --out benchmarks/crypto/prepared/results/prepared-ed25519-final/results.json --trials 3

python3 benchmarks/crypto/prepared/summarize.py \
  --run benchmarks/crypto/prepared/results/prepared-ed25519-final \
  --json /new/summary.json --markdown /new/summary.md
```

`plugin-roots.json` maps plugin names to isolated lane checkouts. Build inputs are frozen before compilation and checked for source/artifact consistency. Stages and reports never overwrite earlier evidence. The runner pins the PocketIC executable, its JavaScript dependency lock and loaded module contents. Comparisons reject failures, missing modes, changed inputs and mismatched toolchains or plugin artifacts. Preparation and steady-call costs include their actual public result wrappers; for example, a prepared signing function returning Blob may allocate less than a direct Result-returning function.
