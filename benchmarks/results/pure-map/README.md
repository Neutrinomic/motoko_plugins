# Persistent ordered map instruction and allocation comparison

Measured with compiler `f1ccbba5e445df9db03bbc35be557187ade9b436`
(`2.0.0-9-gf1ccbba5e`, clean checkout), plugin ABI 1, Core `2.5.0`, and
PocketIC 14.0.0. Both implementations use the same compiler and actor.
The 48 workloads used 144 fresh canisters and 384 measurements: all three
trials had identical counts, every correctness check passed, and no
synchronous collection occurred.

## Point operations

The callback column uses the same Motoko comparison function as Core. The
scalar column uses native Nat64 ordering; values remain ordinary generic
Motoko references. Keys are boxed Nat64s starting at `2^63`, and values are
Nats. Inputs use an identical insertion permutation and a prebuilt,
deterministic spread of hit keys and interleaved absent keys. Each row is a
64-operation batch divided by 64, except retained-overwrite, which retains
eight successive versions and divides by eight. Counter, loop, branch, and
result-assignment costs remain included.

| Operation, 65,536 entries | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Plugin allocated B/op |
| --- | ---: | ---: | ---: | ---: | ---: |
| get-hit | 3,234.27 | 2,560.17 | 1,413.59 | 0.00 | 0.00 |
| get-miss | 3,436.27 | 2,712.06 | 1,511.16 | 0.00 | 0.00 |
| insert | 13,311.12 | 10,089.95 | 8,889.05 | 2,379.88 | 1,323.00 |
| overwrite | 12,337.73 | 5,831.77 | 4,685.19 | 2,165.00 | 1,109.25 |
| replace-miss | 3,566.27 | 3,039.73 | 1,838.83 | 0.00 | 0.00 |
| remove-hit | 17,378.17 | 9,049.58 | 7,903.00 | 3,443.38 | 1,104.75 |
| remove-miss | 16,604.55 | 3,056.73 | 1,855.83 | 3,269.38 | 0.00 |
| retained-overwrite | 12,660.75 | 6,150.38 | 4,994.38 | 2,167.00 | 1,116.00 |

The [complete instruction table](point/instructions.md) covers 16, 256,
4,096, and 65,536 entries. [point/summary.csv](point/summary.csv) contains
raw batch totals, allocation, reclamation, per-operation values, and trial
ranges; [point/results.json](point/results.json) retains every measurement.

The workload names describe operations, not new API names. Their exact public
functions are:

| Workload | Core function | Plugin callback function | Plugin scalar function |
| --- | --- | --- | --- |
| get-hit / get-miss | `Core.get` | `Map.get` | `Map.getNat64` |
| insert / overwrite / retained-overwrite | `Core.add` | `Map.add` | `Map.addNat64` |
| replace-miss | `Core.replace` | `Map.replace` | `Map.replaceNat64` |
| remove-hit / remove-miss | `Core.remove` | `Map.remove` | `Map.removeNat64` |

In particular, the `insert` workload calls `Map.add` with a missing key; it
does not call the separate `Map.insert` API that returns an insertion flag.

Insert and remove-hit each operate on the original root so every operation
succeeds. Overwrite, missing replace/remove, and retained-overwrite use the
preceding result. The last result stays live; retained-overwrite additionally
keeps all eight intermediate roots. Small differences between ordinary and
retained overwrite reflect their different key sequences and retention work.

## Allocation and persistence

Both Core and the plugin already share unchanged subtrees. Plugin updates
copy a logarithmic path of nodes, retaining keys, values, and unaffected
subtrees by reference. Existing-key replacement reuses height/count metadata
on that copied path. Lookup, missing remove, and missing replace allocate
zero bytes in these measurements.

| Entries | Core overwrite B/op | Plugin overwrite B/op | Plugin retained overwrite B/op |
| ---: | ---: | ---: | ---: |
| 16 | 695.50 | 247.50 | 261.00 |
| 256 | 1,159.50 | 525.38 | 549.00 |
| 4,096 | 1,532.50 | 801.00 | 810.00 |
| 65,536 | 2,165.00 | 1,109.25 | 1,116.00 |

A 4,096-fold increase in map size grows the plugin's measured overwrite
allocation from 247.50 to 1,109.25 bytes/op. Keeping eight versions at 65,536
entries allocates 8,928 bytes for the plugin versus 17,336 bytes for Core.
These are **cumulative heap bytes**, including temporary objects, not a
measurement of peak heap, retained live memory, or a count of tree nodes. The
harness does not record peak or live heap size. Releasing old
roots permits normal Motoko GC to reclaim their unshared nodes.

The [sharing/GC fixture](../../../plugins/pure-map/tests/run-drun/pure-map-sharing.mo)
separately verifies identical update allocation with shared 5-byte and 1 MiB
Blob payloads, retained branching versions through GC, and zero allocation
for missing native remove/replace. The
[callback/GC fixture](../../../plugins/pure-map/tests/run-drun/pure-map-callback-gc.mo)
retains original and edited roots, shared 1 MiB Blobs, closure/mutable-cell
payloads, and managed Replace/Split result tuples through four allocating,
reentrant callback and GC cycles. These are correctness checks, not GC
instruction benchmarks.

## Bulk operations and library adapters

These rows execute one complete operation. The plugin uses its callback
ordering API. Core has no public seek, union, intersection, or difference
operation, so those rows include explicit adapters using its public API:

- `bulk-sorted`: sorted, distinct input for both implementations; Core
  `fromIter`, versus plugin `fromSortedDistinctArray`, including the plugin's
  adjacent-key ordering checks. No sorting is needed. Distinct inputs also
  avoid the pinned Core constructor's duplicate-size defect.
- `scan`: consume the complete ascending iterator and sum values.
- `range`: consume at most 16 entries starting at the midpoint. Core scans
  its ascending iterator to the upper bound; the plugin seeks by rank and
  traverses only the selection. The large difference is an algorithm/API
  capability comparison, not a measurement of plugin boundary overhead.
- `filter-all` / `filter-half`: public filters retaining every value or
  even-valued entries. The plugin still calls every predicate when it can
  return the original root unchanged.
- `union-small`: fold the smaller Core map into the larger with `add`;
  plugin split/join union. Right input wins conflicts.
- `intersection-small`: iterate the smaller Core input, look up each key in
  the larger, and add present left values to the output; plugin split/join
  intersection, preserving left keys/values and complete surviving subtrees.
- `difference-small`: iterate the smaller Core input, test membership before
  removal to skip absent-key allocation; plugin split/join difference.

Set inputs have a 16:1 size ratio, with half the smaller input's keys present
in the larger map. Both implementations receive the same keys and values.

| Operation | Entries | Core instructions | Plugin instructions | Core allocated B | Plugin allocated B | Core/plugin |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| bulk-sorted | 256 | 2,110,975 | 226,621 | 383,656 | 28,632 | 9.32× |
| scan | 256 | 375,240 | 274,203 | 65,712 | 10,664 | 1.37× |
| range | 256 | 226,693 | 25,332 | 37,808 | 1,128 | 8.95× |
| filter-all | 256 | 2,106,897 | 84,443 | 383,584 | 112 | 24.95× |
| filter-half | 256 | 967,906 | 170,839 | 170,040 | 13,288 | 5.67× |
| union-small | 256 | 112,880 | 87,695 | 20,440 | 12,664 | 1.29× |
| intersection-small | 256 | 57,509 | 87,555 | 6,016 | 12,184 | 0.66× |
| difference-small | 256 | 108,042 | 95,261 | 16,792 | 13,624 | 1.13× |
| bulk-sorted | 4,096 | 50,348,835 | 3,621,677 | 8,946,504 | 458,712 | 13.90× |
| scan | 4,096 | 6,003,538 | 4,336,399 | 1,048,752 | 164,288 | 1.38× |
| range | 4,096 | 3,184,016 | 29,305 | 530,096 | 1,152 | 108.65× |
| filter-all | 4,096 | 50,298,725 | 1,331,531 | 8,946,432 | 112 | 37.78× |
| filter-half | 4,096 | 23,744,662 | 2,768,468 | 4,121,304 | 216,904 | 8.58× |
| union-small | 4,096 | 2,566,561 | 1,195,925 | 461,144 | 168,496 | 2.15× |
| intersection-small | 4,096 | 1,592,655 | 1,404,364 | 180,160 | 198,792 | 1.13× |
| difference-small | 4,096 | 2,548,958 | 1,502,129 | 394,280 | 216,360 | 1.70× |

The small intersection is an explicit weak case: at 256 entries the plugin
uses 52.25% more instructions and about twice the allocation. At 4,096 it
uses fewer instructions but still more allocation. The current implementation
keeps its subtree-sharing strategy; it is not fastest for every shape or
operation. Full data is in [bulk/summary.csv](bulk/summary.csv) and
[bulk/results.json](bulk/results.json).

## Measurement and correctness boundaries

Input construction, history storage preparation, and four forced GC
increments happen before each phase. The timed synchronous update uses
`performanceCounter(0)`, `rts_total_allocation`, and `rts_reclaimed`. Any
collection inside that interval is included and reported equally for all
implementations; none occurred in these runs. End-of-message GC, reply
serialization, and correctness checks are excluded. Counts are IC
instructions, not CPU time or complete canister execution costs.

After each measurement, a separate query checks the entire ordered result
against independently known ordinal bindings, exact size, both original
maps, every retained historical root, and independently recomputed plugin
AVL order, heights, counts, and balance. It returns `"ok"` only after these
checks pass. The runner's `checked_decode` phase kind is reused for this
checked-result protocol; its two-byte output size describes that reply.

The [differential fixture](../../../plugins/pure-map/tests/run/pure-map-differential.mo)
compares 1,200 deterministic point operations with an independent sorted-array
oracle, including 32 branching history slots, rotations/deletions, nested
optional values, comparator-equivalent stored keys, callback effects, and
mutable/function payloads. The
[advanced fixture](../../../plugins/pure-map/tests/run/pure-map-advanced.mo)
checks split/rank/select, range replay, sorted/duplicate construction,
ordered transforms/folds, both set-operation size branches, conflict callback
order, and builder freeze isolation. The other map fixtures test specialized
key aliases, opaque/optional representations, allocating callbacks, malformed
metadata, traversal depth, and rank overflow. A separate
[long-key fixture](../../../plugins/pure-map/tests/run/pure-map-long-keys.mo)
checks 16 KiB Text prefixes with different rope shapes, Unicode suffix order,
and Blob keys with late byte differences against both comparison paths. See
[validation.json](validation.json) for test scopes and source hashes.

The compiler passed the full Nix build, including 313 `test/run` and 433
`test/run-drun` tests, native/JavaScript builds and installation checks. The
independent SDK review passed 43 targeted SDK fixtures and packaging checks;
these are separate from the external plugin suite's 61 Rust tests and 47
Motoko fixtures. The long-key fixture was added and passed separately after
that suite. The [final validation summary](validation/final-sdk-summary.json)
records those external tests and final codec checks. The final SDK also
passed the existing CandidX upstream 500-record fuzz seed (1,130 typed plugin
instances) and 93 directed cases. Their byte-identical reports are saved as
[fuzz](validation/candidx-fuzz-cad1d-500.json) and
[conformance](validation/candidx-conformance.json); embedded `_build` paths
identify original run locations and have not been rewritten.

## Reproduction and artifacts

Follow the [benchmark guide](../../README.md#persistent-ordered-map). The
build helper requires a clean committed compiler for these final runs and
checks compiler/version/binary identity, build-time plugin and host source
hashes, package artifact hashes, and every locked Core file. Rebuilding after
source changes is required. [point/provenance.json](point/provenance.json) and
[bulk/provenance.json](bulk/provenance.json) record the exact inputs, including
Map.mo and actor Wasm hashes. The
[RTS reproduction check](validation/rts-reproduction.json) additionally records
compiler wrapper and runtime Wasm hashes and confirms both actors recompile
byte-for-byte with those inputs. The dependency manifest/lock and measured
harness sources are archived in [dependencies/](dependencies/) and
[harness/](harness/). Wasm binaries are identified by hash rather than committed.

The archived harness files preserve the measured code; use the repository
scripts from the guide for reproduction, since the scripts resolve inputs
relative to the repository root. Validate both saved reports without running
PocketIC:

```sh
for map_suite in point bulk; do
  python3 benchmarks/summarize-map.py \
    "benchmarks/results/pure-map/$map_suite/results.json" \
    --cases "benchmarks/results/pure-map/$map_suite/cases.json" \
    --out "/tmp/pure-map-$map_suite.csv"
done
```

The validator rejects failed/incomplete phases, missing trials, wrong output
hashes, and mismatched actor/manifest identities. These measurements compare
complete representations and algorithms on the stated workloads; they do
not establish costs for an optimized Wasm component implementation.
