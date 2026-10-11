# Public map functions at 1,000, 10,000, and 100,000 entries

The [complete cost tables](costs.md) compare actual public functions with Core
`2.5.0` pure Map, showing IC instructions and cumulative allocated bytes for
each size. Construction is separate from operations on populated maps. The
[CSV](summary.csv) also records raw batch totals, units, Core adapters, trial
ranges, and reclamation. The [raw report](results.json) retains every sample.

PocketIC 14.0.0 ran 37 workload variants at each size: **111 workloads,
333 fresh canisters, and 720 measurements** across three trials. These cover
27 distinct generic public function names and three scalar wrappers. Every
correctness check passed, instruction/allocation/reclamation counts were
identical across trials, and no synchronous collection occurred. See
[validation.json](validation.json) for counts and artifact checks.

Both implementations use compiler
`f1ccbba5e445df9db03bbc35be557187ade9b436`, boxed Nat64 keys starting at
`2^63`, Nat values, and identical distinct keys in a deterministic shuffled
insertion order. The ordinary plugin column uses the same Motoko comparison
callback as Core. A separate scalar table measures `getNat64`, `addNat64`,
and `replaceNat64` on six of the same workloads; these functions avoid
comparator dispatch while retaining generic Motoko values.

## What each row measures

- Point functions perform 32 calls on prepared key sequences spread across
  the map. Mixed rows alternate present keys and interleaved absent keys.
  Updates use the preceding result and retain the first, middle, and final
  roots; returned old values and Bool flags are retained and checked.
- `add` returns the changed map. `swap` also returns the old optional value
  (put with an old-value result); `insert` returns an insertion flag. These
  are separate measured functions, as are `replace`, `take`, `delete`,
  `alter`, and `update`.
- `find` is an ordered predicate search, distinct from key lookup with
  `get`. The first/middle/last/missing rows match thresholds at those
  positions. Validation checks the earliest result and exactly how many
  times the predicate ran. The tested APIs include `fromIter`, `entriesFrom`,
  and `find`; `findIter` is not a current public name.
- Iterator creation retains four cursors at 100,000 entries or eight at
  smaller sizes, consuming them only during validation. Consumption rows
  include cursor creation and the entire traversal. Seek rows include
  creation plus 16 entries at positions spanning the map. Their unit is a
  complete stated workload, **not one `next()` call**.
- Rank and selection use eight spread positions. Split uses three positions
  at 100,000 entries or four at smaller sizes. Both resulting maps and the
  found entry remain live and are checked completely.
- Whole-map folds, transforms, filtering, and construction run once.
  `fromIter` receives an input cursor prepared before timing for both
  implementations. The `fromArray` Core adapter creates its required array
  iterator inside timing. Sorted and shuffled constructors use distinct
  keys, avoiding Core's known duplicate-size constructor defect.
- Full snapshots compare ordinary persistent Core root capture with the
  plugin's snapshot metadata. Replay includes cursor creation; the consume
  variant also traverses the complete map. Both APIs retain the original
  data by reference.

Every row includes ordinary loop, counter, result retention, and callback
work. Traversal/fold rows include the same bounded, order-sensitive checksum
work and check an independent count. Cumulative allocation includes results
and temporary garbage; **peak heap and live memory after GC are not measured**.

## Core adapters and limitations

The tables show the exact Core baseline for each row. Where Core has no
matching public API, the comparison uses an explicitly named composition:
`get` plus a pair for `getEntry`; lookup/callback/add-or-remove for
`alter`/`update`; ordered iterators for seek, predicate search, rank, and
selection; and ordered iteration plus `add` into two maps for split.
The `getEntry` adapter is equivalent for the exact Nat64 key ordering used
here. Full snapshot creation uses Core root capture, which already provides
persistence without allocating snapshot metadata.

These rows compare complete algorithms and representations. Large seek,
rank, or split differences include the plugin's additional operations and
subtree metadata; they do not isolate the cost of crossing a plugin boundary.
Every measured row remains in the tables, including operations where Core
uses fewer instructions or allocates fewer bytes.

The gains depend on the operation: shuffled `fromIter`, cursor creation,
folds, and snapshot creation favor Core on instructions in this matrix.
Sorted construction, point updates, and traversal have different tradeoffs;
the complete tables keep their allocation costs beside their instruction
costs. No peak or retained-live-memory advantage is inferred from allocation.

## Validation and reproduction

Input construction, arrays, output slots, prepared snapshots, and four GC
increments precede timing. Synchronous GC is included and reported equally
for every implementation. End-of-message GC, replies, independent validation,
and canister cleanup are outside the interval. Cleanup stops/deletes each
trial's canister after all measurements and checks have been saved, limiting
PocketIC host memory use without changing the measured methods.

After each phase, a separate query checks both complete original maps, every
old-value/flag result, retained update versions and final contents against an
independent ordinal-slot oracle, and sizes. It checks plugin AVL invariants on
the initial map, final updated/constructed/transformed maps, and both split
outputs; intermediate update versions are checked for contents and size. Created
cursors and snapshots are fully consumed in expected order; exhausted
iterators are called again to check repeatable exhaustion. Consumed prefixes
and folds use an order-sensitive checksum and independent count, with expected
values computed from ordinal bindings. Remaining iterator suffixes are checked
entry by entry. Construction checks input cursor exhaustion. The reply is
`"ok"` only after those checks pass; its two-byte size is not the returned
object's heap size.

Use the [benchmark guide](../../../README.md#persistent-ordered-map) to
regenerate and run the matrix. [provenance.json](provenance.json) captures
the clean compiler, package, dependency, public library, wrapper/RTS, actor,
and source hashes. [harness/](harness/) freezes the generator, builder,
summary validator, and actual runner for this suite, including per-trial
cleanup. Earlier point/bulk archives retain their original runners and data.

Validate the saved three-trial report without running PocketIC:

```sh
python3 benchmarks/summarize-map.py \
  benchmarks/results/pure-map/functions/results.json \
  --cases benchmarks/results/pure-map/functions/cases.json \
  --out /tmp/pure-map-functions.csv
```
