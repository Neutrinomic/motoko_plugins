# Prepared ML-DSA retained-memory experiment

This experiment measures occupied heap while prepared keys remain reachable,
then measures recovery after dropping them. It uses **one identical Wasm** for
three modes, with a fresh canister for each mode and trial:

| Mode | Rooted preparation | Canonical inputs and array capacity |
|---|---|---|
| `baseline` | None | Identical to the other modes |
| `public` | 32 independently prepared public-key objects | Identical |
| `secret` | 32 independently prepared secret-key objects | Identical |

The 32 objects use the same official key to isolate retained representation
cost. Each factory is called independently; this is not 32 references to one
prepared object. Both public and secret root arrays exist in every mode and
keep their capacities after dropping objects. The seed, public key, message,
context and expected signature also remain rooted in every mode. Mode, root
count and configuration count are returned with every sample.

## Protocol

The default is three trials, with baseline/public/secret canisters installed
from the same frozen artifact in each trial. Every canister follows this order:

1. Record an installed snapshot; configure its mode, 32 roots and official
   deterministic ACVP case 4; record a configured snapshot.
2. Verify every rooted prepared object against the independent expected
   signature in a query.
3. Allocate and discard four 32 MiB arrays, in four separate update messages.
   Record a query snapshot after each. This pressure crosses the pinned RTS's
   64 MiB partition boundary; array headers add 24 bytes per allocation in the
   64-bit representation.
4. Invoke `__motoko_gc_trigger` 24 times, with a snapshot after each. Treat
   each invocation as an **increment**, not as a completed collection.
5. Verify every rooted object again in a query. In secret mode, signing with
   each retained key must still yield the exact official signature.
6. Set every prepared root to `null`, preserving the two root arrays and
   canonical inputs. Record the dropped snapshot. Repeat steps 3–4 unchanged,
   then query-check that all roots are absent.

Queries keep their temporary signing, verification, snapshot and reply
allocations out of committed update state. The full trajectory is retained,
including configured occupancy before pressure, pressure samples, all forced
increment samples and correctness outcomes. There is no timing parameter search
or adaptive extra collection to favor a particular mode.

The last eight forced-increment samples form the comparison window. The runner
records minimum, median and maximum occupied heap and allocation minus reclaim.
A window qualifies only if its heap range is at most 4 KiB, no sample has
active evacuation-copy bytes, and its stage reclaimed at least 64 MiB. Failed
qualification is retained as incomplete evidence requiring investigation.

These conditions establish a reproducible quiet measurement window. They do
**not** expose the collector's authoritative phase or prove every dead object
has been reclaimed.

## Counters and interpretation

The pinned-source evidence and line anchors are in
[`gc-semantics.json`](gc-semantics.json). Check that evidence against the exact
RTS used in the build before interpreting the measurements.

| Recorded value | Meaning |
|---|---|
| `heapOccupiedBytes` | Current occupied heap, including garbage and any active evacuation copies |
| `totalAllocationBytes` | Cumulative allocation counter; not current retained memory |
| `reclaimedBytes` | Cumulative reclamation of all garbage, including pressure and GC bookkeeping |
| `heapOccupiedBytes − (totalAllocationBytes − reclaimedBytes)` | Active evacuation-copy bytes in this pinned RTS |
| `maxObservedPostGcHeapBytes` | Historical post-GC occupied dynamic-heap high-water mark |
| `wasmMemoryBytes` | Wasm linear-memory capacity; dropping keys need not reduce it |
| Collector/mutator instruction counters | Evidence of work during the full collection schedule |

The matched-trial comparisons are:

```text
observed retained heap increment = retained mode median − retained baseline median
residual after dropping          = dropped mode median − dropped baseline median
recovered increment             = retained increment − residual after dropping
observed increment per key      = retained increment / configured root count
```

Report the measurement ranges beside those deltas. The baseline subtraction
controls the common arrays, input objects, fixture, actor, schedule and GC
bookkeeping; it cannot certify exact live bytes when collector phase is hidden.
The report must call these **observed retained heap increments** and retain the
drop-residual check, rather than presenting them as exact object sizes.

The private payload sizes, 20,576 bytes per public cache and 28,800 bytes per
secret cache, are separate layout facts. Managed Blob headers, option wrappers,
array slots and any surviving garbage affect actual heap measurements. The
configure allocation delta must be at least `count × payloadBytes` for cache
modes, to catch accidentally aliasing one prepared object across all slots.

## Build and run

Use the prepared-type compiler/RTS bundle and matching ML-DSA plugin; the older
compiler cannot load these descriptors. Build under the centrally assigned
heavy-job slot. The standard crypto builder freezes the actor and toolchain:

```sh
python3 benchmarks/crypto/build.py \
  --manifest benchmarks/crypto/prepared/ml-dsa/memory/cases.json \
  --stage prepared-mldsa-memory \
  --bundle /path/to/prepared/compiler-bundle \
  --plugin-roots /path/to/prepared/plugin-roots.json \
  --fast-root packages/fast/src

node benchmarks/crypto/prepared/ml-dsa/memory/run.mjs \
  --build benchmarks/crypto/results/prepared-mldsa-memory/build.json \
  --out benchmarks/crypto/results/prepared-mldsa-memory/memory.json \
  --trials 3 --keys 32
```

The memory runner uses [`../fixtures.json`](../fixtures.json), whose official
corpus and upstream source commit are pinned. It preserves runner/fixture/build
hashes and source snapshots beside its output, and refuses to overwrite a
previous result. The standard instruction runner is not suitable for this
actor because this protocol has configure/retain/drop stages instead of one
measured `run` method.

**Status:** source prepared; this experiment has not yet been compiled or run.
No measured retained-heap or recovery claim is made until its report passes the
correctness and window-qualification checks above.
