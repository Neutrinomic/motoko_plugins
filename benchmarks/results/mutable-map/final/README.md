# Mutable-map functions at 1,000, 10,000, and 100,000 entries

[Complete instruction/allocation tables](costs.md) and [CSV](summary.csv) compare
46 workloads at each size against **mutable `mo:core/Map` 2.5.0**. Core's pure
map is a different baseline and is not used here. Eight point workloads also
measure the plugin's direct Nat64 ordering, with generic Motoko values.

The matrix contains 138 workloads, 300 implementation/workload groups and
900 measurements across three trials. All passed the independent result checks;
instruction, allocation and reclamation counts were identical across trials,
and no synchronous reclamation occurred. See [raw results](results.json) and
[validation](validation.json) for complete coverage and trial ranges.

## Measurement

Each workload/trial installs a fresh PocketIC canister. Both implementations
use boxed Nat64 keys above `2^63`, Nat values and the same comparison callback.
Seeds are populated by repeated `add` in a deterministic coprime-stride
permutation. This is what **shuffled** means; **sorted** constructors receive
ascending keys. The shuffle is not claimed to be uniformly random.

Before every phase, the harness clones both seeds **outside timing**, giving
each mutable implementation independent initial state. Actual measured point
updates mutate their map in place. Input arrays, result slots and constructor
iterators are prepared outside timing; four forced GC increments precede
measurement. Constructors use empty seeds and measure the public constructor.

- Point functions batch 32 distinct, spread probes; mixed rows alternate
  present keys and interleaved absent keys. Costs are per complete function call.
- Iterator creation retains four cursors at 100k or eight otherwise. Consumption
  includes creation plus the whole traversal and an order-sensitive checksum.
  Seek rows include cursor creation and 16 entries, in the stated direction.
- `get` is key lookup; `find` is ordered predicate search. First/middle/last/missing
  rows verify the earliest result and exact callback count.
- Whole-map folds, transformations, clone, clear and construction run once.
  Core has direct equivalents except the documented `getEntry` and `find` adapters.

Counts include common loop, result-retention and checksum work. Allocation is
**cumulative GC-managed heap bytes**, including temporary objects and retained
results; it is not peak heap, live memory after GC or RSS. Keys/values remain
managed Motoko references borrowed by native kernels. These measurements do
not separately quantify retained payload memory. Reclaimed bytes inside the
synchronous interval are recorded; end-of-message GC is excluded.

## Correctness and limits

An untimed query checks original seeds, complete resulting bindings, sizes,
balanced-tree invariants, return values, iterator order/exhaustion and callback
counts against independently generated ordinal bindings. Checking seeds after
updates detects accidental clone aliasing. Clone outputs are mutated outside
timing to check independence. The summary rejects missing/duplicate/failed
trials and mismatched source, runner, Wasm or provenance hashes.

These rows compare full implementations and representations, including Core
adapters; they do not isolate compiler-plugin boundary overhead. All measured
rows remain visible. At 100k, `map` transformation takes 76,139,742 plugin
instructions versus 60,103,065 for Core (26.7% more), while allocating
5,842,432 versus 6,441,152 bytes. `size` and `isEmpty` are near parity. The matrix
covers 46 workloads, not every wrapper: for example keys/values, equality,
comparison, text formatting and Core pure-map conversion are unmeasured.

[Provenance](provenance.json) records the exact clean compiler, binary/runtime,
plugin source/package and locked dependency hashes. [Sources](sources/plugins/mutable-map)
and [harness](harness) preserve the measured inputs. See the
[parent report](../README.md) for reproduction and optimization history.
