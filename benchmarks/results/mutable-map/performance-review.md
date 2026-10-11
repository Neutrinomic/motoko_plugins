# Mutable-map performance and simplicity review

The bounded optimization round is approved. It keeps one order-32 B-tree,
ordinary Motoko heap objects, generic payload references, and the existing
typed SDK operations. No SDK change, raw heap write, alternate tree algorithm,
callback lock, or iterator-version machinery was added during this review.
The final three-trial performance matrix is independently validated;
correctness and release approval remain subject to the separate audit and
test results.

## Changes retained

- Cache the immutable `entries` array reference once per node search and the
  array reference once per shift. These are managed references; array bounds,
  forwarding, and write barriers remain in place.
- Decrement the structural map size through the SDK's checked `Nat` to
  `word64` conversion, subtraction, and managed conversion/store. Previously,
  adding signed `-1` forced the compiler's boxed bignum path on every successful
  deletion. A realizable tree has fewer than `2^64` entries; oversized forged
  metadata traps instead of truncating. The reference implementation enforces
  the same structural bound.
- Determine leaf status once in folds, predicate search, and structural map.
  Leaf traversal no longer recursively visits a null child for every entry.
- Read stored optional tuples directly in predicate search and extrema.
  Destructure the fixed tuple return in seek comparisons and invariant checks
  instead of rebuilding a tuple just to project its key. This removes
  unnecessary tuple allocations without copying keys or values.

The generic and scalar paths still share the algorithm. The scalar entry
points remove comparator dispatch, while values remain arbitrary Motoko
references. There is no new family of specialized tree implementations.

## Measured optimization evidence

These are one-trial engineering comparisons, not the final three-trial
headline results. Both sides of each comparison use identical actor source,
compiler commit `abfba892fe4bd8fa2bc88e25dca0b895d35c1962`, ABI 1, and compiler
binary SHA-256
`a5a68803ecc8d48509c77052889f05eb8b5e3e983ee55b2027e9689939d79498`.
Archived sources and provenance identify each candidate exactly.

For the native point kernels, the following rows use 100,000-entry maps.
Point-operation counts are complete batches of 32 distinct keys;
construction is one complete constructor call.

| Workload | Before instructions | After instructions | Before allocated B | After allocated B |
| --- | ---: | ---: | ---: | ---: |
| Get hit, 32 calls | 137,213 | 124,029 | 0 | 0 |
| Add new keys, 32 calls | 208,116 | 175,918 | 1,280 | 1,280 |
| Overwrite, 32 calls | 156,893 | 143,709 | 1,280 | 1,280 |
| Delete hit, 32 calls | 375,697 | 250,634 | 6,912 | 0 |
| Delete miss, 32 calls | 258,608 | 222,271 | 0 | 0 |
| Shuffled `fromIter`, 100,000 entries | 685,168,784 | 566,138,210 | 5,842,360 | 5,842,360 |

Sources: [initial pilot](pilot-1/summary.csv),
[native candidate](pilot-2/summary.csv). The combined actor grows by 24 bytes,
from 443,451 to 443,475 bytes; this is an actor-level size comparison, not an
isolated plugin size claim.

The traversal cohorts separate leaf handling from direct tuple reuse:

| Complete call on 100,000 entries | Original instructions / allocated B | Leaf handling instructions / allocated B | Direct tuple reuse instructions / allocated B |
| --- | ---: | ---: | ---: |
| Find last | 81,716,460 / 4,000,072 | 60,126,703 / 4,000,072 | 40,524,747 / 72 |
| Find missing | 81,716,686 / 4,000,072 | 60,126,771 / 4,000,072 | 40,524,819 / 72 |
| Fold left | 62,643,773 / 72 | 42,370,964 / 72 | 42,370,964 / 72 |
| Fold right | 63,434,089 / 72 | 43,161,280 / 72 | 43,161,280 / 72 |
| Structural map | 79,876,842 / 5,842,432 | 76,139,758 / 5,842,432 | 76,139,758 / 5,842,432 |

Sources: [original wrapper](wrapper-before/summary.csv),
[leaf handling](wrapper-after/summary.csv),
[direct slot access](wrapper-direct-slot/summary.csv).
The wrapper actor grows from 384,652 to 385,846 bytes across these changes.

The final 1,000-entry API pilot confirms the remaining tuple fixes:

| Workload | Original allocated B/call | Final allocated B/call |
| --- | ---: | ---: |
| Minimum or maximum entry | 40 | 0 |
| Forward seek and 16 entries | 1,192 | 792 |
| Reverse seek and 16 entries | 1,437 | 1,032 |
| Full forward or reverse traversal | 352 | 352 |
| `toArray` or `toVarArray` | 8,416 | 8,416 |

Sources: [API baseline](api-pilot/summary.csv),
[final API pilot](api-final-pilot/summary.csv).
Traversal and array conversion already reuse stored tuples. `keys` and
`values` were reviewed as thin projections over that iterator but were not
separately benchmarked; no separate cost claim is made for them.

## Evidence checks and limits

This review independently reran the archived strict validators for all seven
pilot cohorts, reproduced their CSV summaries, and checked paired actor bytes.
The native and wrapper optimization pairs have exactly equal Core control
measurements. The final API pair has unchanged allocation controls, but 33 of
46 Core instruction controls differ by 16–48 instructions per complete batch.
The exact cause of that small cross-artifact drift was not isolated. The raw
measurements are retained; they were not subtracted or adjusted. The final
comparison measures both implementations within one frozen actor.

The [final matrix](final/summary.csv) also independently passes the archived
strict validator: 138 workloads, 24 additional scalar comparisons, and 900
measurements across three trials, with no failures. Its CSV was reproduced
byte-for-byte. The compiler revision and binary hash match those above, and
every archived plugin source hash matches the frozen production source.

Allocated bytes are cumulative allocation, including retained results and
temporary objects. They are not peak memory, live heap size, or a promise of
immediate reclamation. Clear removes the root; deletion and shifts clear
vacated slots. Collection remains the Motoko runtime's responsibility.

Core's mutable map is also an order-32 B-tree. The measured gains do not imply
an asymptotic advantage. The predicate-search baseline is explicitly
`Iter.find(Core.entries(...))`, because Core has no direct public `find`.
Structural map remains a weaker case: the final 100,000-entry row uses
60,103,065 Core instructions versus the plugin's 76,139,742, despite the
plugin allocating 5,842,432 bytes versus Core's 6,441,152. This is the final
matrix's only generic instruction loss; `size` and `isEmpty` are near parity.
The final report must retain weak rows.

Top-down insertion may split a full ancestor even when replacing an existing
key. Overwrite is therefore not guaranteed to allocate exactly one pair.
Clone copies the tree's mutable structure and shares immutable entry tuples
and payload references. The reusable iterator arrays were retained; adding
alternate cursor implementations, extra lookup passes, bulk builders, or more
specialized kernels was not justified by this bounded review.
