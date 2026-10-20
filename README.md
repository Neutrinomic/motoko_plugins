# Motoko plugins

Native compiler plugins for fast computation in Motoko. Each package
adds functions to `Prim`, specializes calls during compilation, and links its
optional Wasm runtime into the canister. Plugin code reads Motoko values through the
compiler's memory and GC helpers. The SDK also supports typed mutation of
caller-owned Motoko arrays and records through the ordinary GC write barriers.

Use the [`fast` Mops package](packages/fast/) for imports such as
`mo:fast/JSON`, `mo:fast/SHA256`, `mo:fast/Map`, and `mo:fast/Set`.

The Map and Set modules expose their Core counterparts' function interfaces,
including implicit comparators. Ordinary native key operations such as
`Map.get(map, Nat64.compare, key)` select native scalar ordering automatically,
including through aliases and generic wrappers. The compiler proves the
comparison from its body; unrecognized or effectful comparators retain their
callback behavior. The SDK provides one shared `Compare.dispatch` facility,
without changing closure layouts, GC representation, or ABI 1.
See the [package guide](packages/fast/) for the API and storage caveats:
switching an import does not migrate existing Core container values or stable
data.

## Current signature performance

Round four and the subsequent BLS optimizations improve the delivered plugins with the **same compiler and SDK**: `9f6ebeedc`, compiler ELF `24d8d0b9…`, original RTS, ABI 1. These are PocketIC instruction medians from three fresh canisters per workload and revision; wall-clock timings are not compared. The BLS row compares round six with round seven; other rows retain their round-four comparison.

| Direct operation | Delivered plugin | Selected plugin | Fewer instructions |
|---|---:|---:|---:|
| Ed25519 verify / 32 B | 2,308,542 | 2,169,138 | **6.04%** |
| Secp256k1 ECDSA sign | 3,618,719 | 2,295,959 | **36.55%** |
| Secp256k1 Schnorr sign | 5,099,447 | 2,681,582 | **47.41%** |
| P256 ECDSA sign | 7,252,878 | 4,791,659 | **33.93%** |
| RSA-3072 PSS sign / digest | 447,476,438 | 400,505,033 | **10.50%** |
| ML-DSA-44 verify / ACVP 4 | 3,810,844 | 3,656,399 | **4.05%** |
| BLS IC single verify | 127,630,963 | 107,949,293 | **15.42%** |

A [correctness followup](tests/crypto-audit/round5/README.md) fixes rare BIP340 signing boundaries and aligns portable ECDSA errors with the native contract. The Secp256k1 costs on this page include its **33 new observations across 11 unchanged workloads**. The [latest BLS optimization](benchmarks/crypto/bls-verify-round7/README.md) simplifies limb arithmetic, uses Karatsuba extension-field multiplication and shortens fixed group multiplication: **90 matched observations across 15 workloads**, with unchanged allocation and prepared layouts. Other scheme costs retain their round-four measurements.

Current public-operation costs follow. Prepared keys are opaque, immutable GC-managed values; preparation is separate from the hot call. ECDSA signing rows use the existing direct APIs; dashes mean no prepared-signing API was measured.

| Operation / input | Direct instructions | Preparation instructions | Prepared instructions | Payload B | Allocated B: direct / preparation / prepared |
|---|---:|---:|---:|---:|---:|
| Ed25519 sign / 32-byte message | 1,803,963 | 887,929 | 907,801 | 96 | 120 / 152 / 88 |
| Ed25519 verify / same message | 2,169,138 | 266,515 | 1,933,663 | 1,056 | 32 / 1,112 / 32 |
| Secp256k1 ECDSA sign / digest | 2,295,959 | — | — | — | 120 / — / — |
| Secp256k1 ECDSA verify / digest | 2,454,026 | 484,693 | 2,202,476 | 512 | 32 / 568 / 32 |
| Secp256k1 BIP340 sign / vector 0 | 2,681,582 | 1,308,292 | 1,375,508 | 64 | 120 / 120 / 120 |
| Secp256k1 BIP340 verify / vector 0 | 2,413,617 | 485,205 | 2,161,731 | 512 | 32 / 568 / 32 |
| P256 ECDSA sign / digest | 4,791,659 | — | — | — | 120 / — / — |
| P256 ECDSA verify / digest | 11,961,908 | 19,688,627 | 3,223,424 | 16,320 | 32 / 16,376 / 32 |
| RSA-3072 PSS sign / digest + salt32 | 400,505,033 | 6,138,602 | 396,540,393 | 1,840 | 440 / 1,896 / 440 |
| RSA-3072 PSS verify / same digest | 9,162,600 | 3,642,309 | 7,722,884 | 824 | 32 / 880 / 32 |
| ML-DSA-44 sign / ACVP 4 | 13,039,211 | 4,862,444 | 8,890,133 | 28,800 | 2,480 / 28,856 / 2,480 |
| ML-DSA-44 verify / ACVP 4 | 3,656,399 | 2,371,114 | 1,787,636 | 20,576 | 32 / 20,632 / 32 |
| BLS IC single verify | 107,949,293 | 22,573,839 | 85,442,830 | 19,680 | 64 / 19,736 / 64 |
| BLS Ethereum single verify | 141,664,860 | 5,564,301 | 136,101,721 | 144 | 64 / 200 / 64 |
| BLS Ethereum aggregate / 8 distinct keys | 1,643,095,683 | 1,133,318,606 | 509,781,620 | 1,152 | 181,112 / 1,688 / 181,552 |

Direct Ed25519 signing is unchanged. Secp256k1 Schnorr verification adds **534 instructions** per direct/prepared call (about 0.02%); other small candidate regressions are retained in the full report. ML-DSA costs depend on its rejection-sampling input; ACVP 4 uses a one-byte message and 59-byte context.

Setup matters: actual P256 preparation plus one check costs **22.91M** versus **11.96M** direct; preparation plus 100 checks costs **342.00M** versus **1,196.17M** direct. Actual Secp256k1 ECDSA preparation plus ten checks costs **22.51M** versus **24.54M** direct. These are measured batches, not setup-plus-hot estimates.

Round four reduced BLS allocation: IC single verification **19,672 → 64 B**, Ethereum single **39,280 → 64 B**, eight-key proof-of-possession preparation **315,416 → 1,688 B**, and that aggregate's direct verification **494,840 → 181,112 B**. Round seven preserves those allocation and payload sizes while shrinking its runtime **617,967 → 342,359 B** and every measured primitive canister by **275,053 B**. Sampled heap and Wasm capacity are unchanged. Ethereum aggregate preparation includes proof-of-possession verification for each key; plain single-key preparation does not.

Round-four runtime changes were **+26,909 B for Secp256k1**, **+14,570 B for P256**, **+948 B for RSA**, **+585 B for ML-DSA**, **+47,054 B for BLS**, and **−1,041 B for Ed25519**. The correctness followup adds 875 runtime bytes and 872 bytes to each measured Secp256k1 canister; direct/prepared Schnorr signing adds 218/236 instructions with unchanged allocation. Full round-four linked-canister size changes remain in its report.

The `ecdsa@8.0.1` library controls below are **reused from the preceding prepared-key run**, not rerun this round. They use the same compiler ELF and exact verification inputs; ratios use the current plugin costs.

| Verification | Reused pure Motoko instructions | Current direct / prepared | Motoko instruction ratio: direct / prepared | Allocated B: Motoko / direct / prepared |
|---|---:|---:|---:|---:|
| Secp256k1 ECDSA | 137,009,273 | 2,454,026 / 2,202,476 | **55.83× / 62.21×** | 10,903,256 / 32 / 32 |
| P256 ECDSA | 323,983,718 | 11,961,908 / 3,223,424 | **27.08× / 100.51×** | 23,927,448 / 32 / 32 |

Prepared ratios exclude setup. Library controls include byte parsing and validation, with reusable curve construction outside timing; P256 normalizes its high-S input internally. These valid-input comparisons do not establish identical error semantics. Allocation includes returned values and temporary garbage; payload excludes headers, and heap snapshots are not peaks or exact live-memory measurements. Ed25519 direct signing returns a Result while prepared signing returns a Blob. Digest rows exclude message hashing; schemes and security profiles differ.

The round-four **111 matched workloads / 666 fresh-canister observations** passed exact-output checks. All 23 plugin builds, packaging, combined composition, rejection and GC checks pass, alongside six independent internal scheme audits. Audits and regression tests are correctness evidence, not security guarantees.
[Full round-four results and evidence](benchmarks/crypto/round4/RESULTS.md) · [Reproduction](benchmarks/crypto/round4/README.md).

<details>
<summary>Earlier signature benchmark results</summary>

The [prepared-key measurements](benchmarks/crypto/prepared/RESULTS.md), [round three](benchmarks/crypto/round3/RESULTS.md), and [crypto API benchmark history](benchmark_crypto.md) remain archived. Their plugin costs are historical; the two explicitly identified pure Motoko controls above are reused because the compiler and inputs match.

</details>

## Current collection performance

The second optimization round reduces costs from the **already delivered
plugins**, with the same compiler `92b1bde`, original RTS, and ABI 1.
The Core 2.6.2 column is a separate library comparison; it is not the baseline
for the round-two percentage. Counts are instructions for the whole batch.

| Workload | Core instructions | Delivered plugin | Current plugin | Round-two change | Allocated B, Core / delivered / current |
| --- | ---: | ---: | ---: | ---: | ---: |
| Queue: 100,000 FIFO pairs at 100,000 entries | 167,500,519 | 135,668,063 | 118,680,429 | −12.52% | 9,600,000 / 440 / 408 |
| Queue: pop 100,000 entries from front | 71,200,385 | 79,812,686 | 66,525,182 | −16.65% | 0 / 0 / 0 |
| HistoryRing: 1,024 overwrites at capacity 1,000 | 1,901,859 | 1,713,443 | 1,150,243 | −32.87% | 98,304 / 0 / 0 |
| HistoryRing: ten 32-entry tail pages at capacity 1,000 | 2,671,942 | 67,514 | 50,314 | −25.48% | 4,160 / 2,800 / 2,800 |
| HistoryRing: drop 500 entries at capacity 1,000 | 285,553 | 64,206 | 4,221 | −93.43% | 0 / 0 / 0 |
| IndexedPriorityQueue: 256 Nat pops at 100,000 entries | — | 2,087,900 | 1,766,338 | −15.40% | — / 10,240 / 10,240 |
| IndexedPriorityQueue: 256 deadline pops at 100,000 entries | — | 3,749,491 | 3,620,488 | −3.44% | — / 10,240 / 10,240 |

These rows use three identical trials. Queue and HistoryRing have matched Core
Queue controls. History's Core page adapter scans forward, while the ring uses
its sequence index; Core can use reverse iteration for a tail-only page. IPQ
rows use deterministically shuffled priorities, with scalar Nat ordering and a
custom deadline-record comparator respectively. There is no fresh IPQ-versus-Core
run in this round; its previous library comparison remains below. Reports
include other sizes/distributions, repeated controls, and exact protocols.
Allocation includes temporary garbage and results, not retained live memory.

Tradeoffs remain. A fresh Queue singleton costs **2,831 versus Core's 1,307
instructions**, allocating **408 versus 96 B**; 16 pushes cost **10,976 versus
16,202 instructions**. Queue peeks, forward iteration, and full-chunk LIFO
churn still lose to Core. One-item HistoryRing pages and some nonzero drops
add small fixed instruction costs versus the delivered plugin. IPQ has small
push/equal-key regressions and unchanged allocation; generic callbacks retain
their observable behavior. Layout and algorithm gains can also be implemented
in Motoko; these measurements do not isolate plugin-boundary overhead.

Queue's matched heap probe with 4,096 separately allocated 4 KiB payloads fell from
**17,095,680 to 17,091,584 B** above its empty baseline: 32 B saved per chunk.
Its retained empty chunk after full drain shrank from 440 to 408 B;
`clear` returns to baseline.
These are controlled RTS heap observations, not a general live-memory claim.
Queue's packed metadata **changes its private stable storage shape**; old
experimental queues need explicit migration or recreation. No legacy adapter
was added. HistoryRing and IPQ retain their existing representations.

Final reports: [Queue](benchmarks/queue/OPTIMIZATION-ROUND-2.md),
[HistoryRing](benchmarks/history-ring/round2/README.md),
[IndexedPriorityQueue](benchmarks/indexed-priority-queue/round2/README.md).
Algorithm research: [Queue](benchmarks/queue/algorithm-research-round-2.md),
[HistoryRing](benchmarks/history-ring/algorithm-research-round-2.md),
[IndexedPriorityQueue](benchmarks/indexed-priority-queue/algorithm-research-round-2.md).

In the matched fourcans application screen, round-two Queue/HistoryRing save
**0.668% of instructions** (154.731 → 153.698 billion) and **0.043% of
allocation** (4.205152 → 4.203336 GB). Completion remains **57 rounds**;
throughput, latency, and aggregate linear-memory capacity are unchanged.
Physical calls rise from 2,423 to 2,429. This is one candidate run against an
inherited, byte-identical verified baseline, with unchanged settings and all
correctness checks passing; IPQ is unused. The
[application report](https://github.com/Neutrinomic/takt/blob/main/examples/reactor/fourcans/test/results/tuning/fast-collections-round-2/README.md)
includes sampled heap/GC counters and provenance. The original integration's
76-to-57-round gain below is historical, not an additional round-two gain.

The [current-library integration recheck](benchmarks/library-integration-round2/README.md)
separates plugin updates from structure changes: Takt and Reactor retain Map
deadlines; Takt adopts inline Queue reuse and Rechain adopts an insertion FIFO.

<details>
<summary>First-delivery application and Core comparisons (before optimization round two)</summary>

## Application workload

Using `Queue` and `HistoryRing` in Takt and Reactor cut full-drain completion
time by **25%** in the matched fourcans benchmark, with the same compiler, RTS,
and workload settings. The candidate changes five Takt files and two Reactor
Queue imports. This comparison includes the collection algorithms and their
integration; it does not isolate plugin call overhead.

| Metric | Control | Queue + HistoryRing | Change |
| --- | ---: | ---: | ---: |
| Completion rounds | 76 | 57 | −25.00% |
| Endpoint messages/s, full drain | 3,947.37 | 5,263.16 | +33.33% |
| Physical calls | 2,136 | 2,423 | +13.44% |
| Instructions | 199.17 billion | 154.73 billion | −22.31% |
| Workload allocation | 4.708 GB | 4.205 GB | −10.68% |
| Peak sampled heap, single canister | 312.10 MB | 200.99 MB | −35.60% |
| Final aggregate linear memory | 6.176 GB | 4.295 GB | −30.46% |
| Final aggregate sampled heap | 2.069 GB | 3.193 GB | **+54.29%** |

Decimal units. PocketIC ran 16 canisters with four execution partitions,
1,000 submitted root workflows/s for 30 feed rounds, then full drain, using the
existing tuned parameters. All 180,000 endpoint messages, 27,600 blocks,
594,000 visits, and 1,024 canonical-block/tip checks passed without traps or
rejections. This is one matched candidate observation; a fresh control
reproduced the original control's counters exactly. These are simulated workload
rates, not mainnet throughput estimates.

The heap samples include unreclaimed garbage and differ in collector progress;
they are **not retained live memory**. The final aggregate heap increased even
though peak sampled heap and linear memory decreased. Rechain source is
unchanged in this comparison; IndexedPriorityQueue is loaded but unused.
The [full report and reproduction evidence](https://github.com/Neutrinomic/takt/blob/main/examples/reactor/fourcans/test/results/tuning/fast-collections/README.md)
record exact source, compiler, RTS, plugin, and harness hashes.

## Queue, history, and priority costs

PocketIC comparisons with Core **2.6.2**, compiler `92b1bde`, and the original
release RTS. Each row measures the whole operation or batch shown; setup and
validation are outside the measured interval. Allocated bytes include results
and temporary garbage, not retained heap.

| Operation / workload | Native baseline | Native instructions | Plugin instructions | Native / plugin | Allocated B, native / plugin |
| --- | --- | ---: | ---: | ---: | ---: |
| Queue, 100,000 pushes | Core Queue | 99,300,314 | 64,828,362 | 1.53× | 9,600,000 / 1,375,000 |
| Queue, 100,000 FIFO pairs at 100,000 entries | Core Queue | 167,500,519 | 135,668,063 | 1.23× | 9,600,000 / 440 |
| Queue `toArray`, 100,000 entries | Core Queue | 27,201,860 | 8,785,756 | 3.10× | 800,160 / 800,024 |
| History, 10,000 overwrites at capacity 10,000 | Core Queue append-and-trim | 18,570,291 | 16,730,291 | 1.11× | 960,000 / 0 |
| History, ten 32-entry tail pages at capacity 10,000 | Core Queue forward scan | 26,431,942 | 67,514 | 391.50× | 4,160 / 2,800 |
| Priority queue, 256 pops at 100,000 Nat entries | Core PriorityQueue | 6,828,679 | 2,055,451 | 3.32× | 312,344 / 10,240 |
| Priority queue, 256 reschedules at 100,000 Nat entries | Core Map index adapter | 6,709,338 | 369,435 | 18.16× | 256,360 / 12,288 |

Queue and HistoryRing rows are medians of three identical trials. These IPQ
100,000-entry rows are single-trial observations; the report also repeats
selected 10,000-entry cases with identical counters. IPQ setup uses descending
priorities, and reschedules target the first inserted handles; this is a
specific workload, not a randomized average-case claim. Core PriorityQueue has
no cancellation/rescheduling handles, so those operations use a Map adapter.

Queue's storage savings come from its chunked layout, which can also be written
in Motoko. History paging compares indexed access with Takt Trace's previous
forward scan; Core `peekBack` is already O(1), and reverse iteration can improve
a tail-only scan. These compare complete implementations, not isolated plugin
boundary costs.

Small queues have a crossover: a fresh singleton push costs **3,002 versus
1,307 instructions**, allocating **440 versus 96 bytes**; 16 pushes cost
**11,702 versus 16,202 instructions**. Queue peek/pop, forward iteration, and
full-chunk LIFO churn remain slower than Core in this matrix. IPQ also has
tradeoffs: compared with Fast Map, pop costs 7.2% more at 100,000 Nat entries
and 25.3% more at 10,000 composite deadlines. Its `clear` visits every handle,
and handle/entry storage can cost more heap than simpler containers.

Separate memory probes check reference release across messages. Queue's sampled
RTS heap above a matched empty baseline was **17,095,680 versus 17,432,576 B**
with 4,096 separately allocated 4 KiB payloads; both returned to baseline after `clear`.
HistoryRing retained exactly 1,024 slots and 1 MiB of payload after 65,536
appends at capacity 1,024, then zero after `clear`. Its Wasm high-water matched
Core and its historical post-GC heap high-water was higher. IPQ's sampled heap
delta at 100,000 Nat entries was **16,579,360 versus 6,531,112 B** for Core
PriorityQueue, which has no handle index. These RTS samples include runtime
state and possibly unreclaimed garbage; they do not establish retained live
bytes or a universal memory-footprint improvement.

Full size/operation matrices, memory protocols, and three measured optimization
passes: [Queue](benchmarks/queue/README.md),
[HistoryRing](benchmarks/history-ring/README.md), and
[IndexedPriorityQueue](benchmarks/indexed-priority-queue/README.md).

</details>

## Candid size estimates

When exact bytes are unnecessary, `CandidX.estimateSize(value)` returns a fast,
conservative bound instead of allocating a Candid Blob. PocketIC measurements
on the plugin PR compiler compare it with `(to_candid(value)).size()`:

| Value | Native instructions | Estimate instructions | Native / estimate | Allocated bytes, native / estimate |
| --- | ---: | ---: | ---: | ---: |
| Fourcans-shaped Fanout request | 10,542 | 2,673 | 3.94× | 952 / 0 |
| Blob, 1 MiB | 2,098,590 | 481 | 4,362.97× | 2,097,256 / 0 |
| Fixed-width records, 10,000 | 8,111,467 | 585 | 13,865.76× | 420,152 / 0 |
| Text array, 1,024 | 328,822 | 79,477 | 4.14× | 24,664 / 0 |

Three identical trials per case. The estimate has slack: these are admission
checks with different accuracy contracts, not equivalent serialization work.
Near a limit, estimates can reject values that fit; function references and
depth/work limits return a rejection-sized sentinel. The
[full report](benchmarks/candid-size/README.md) includes returned sizes,
big integers, recursive values, raw samples, and reproduction instructions.

## Automatic comparator costs

Ordinary `Nat64.compare` lookups at **100,000 entries** now use **25.5–39.6%
fewer instructions** than the previous plugins. Core 2.5.0 uses **2.74–3.59×
as many instructions**. Explicit scalar helpers remain optional; the ordinary
API gets most of their benefit.

| Container | Core instructions | Previous plugin | Automatic | Explicit Nat64 | Core/automatic | Allocated B, Core / automatic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Mutable Map `get` | 7,242.72 | 3,556.09 | 2,648.03 | 2,590.03 | 2.74× | 117 / 0 |
| Pure Map `get` | 3,034.47 | 1,466.53 | 962.28 | 904.28 | 3.15× | 0 / 0 |
| Mutable Set `contains` | 6,945.38 | 3,346.47 | 2,325.91 | 2,267.91 | 2.99× | 117 / 0 |
| Pure Set `contains` | 2,754.91 | 1,272.53 | 768.28 | 710.28 | 3.59× | 40 / 0 |

Per-call averages of 32 probes; three identical PocketIC trials, each in a fresh
canister. Keys alternate between low `Nat64` values and values at or above `2^63`;
map values are `Nat`. Compiler `92b1bde` is compared with `fc7612098`, using
identical public modules, generated programs, RTS and measurement harness.
Setup and validation are outside the measured interval. Allocation is
cumulative bytes, including temporary garbage, not peak or retained memory.
Core comparisons measure complete container implementations.

The [full report](benchmarks/results/comparator-dispatch/README.md) covers
**864 samples**: construction, lookup, insertion and deletion at **1,000,
10,000 and 100,000 entries**, plus aliases, generic wrappers, custom callbacks,
and empty/singleton containers. Allocation is unchanged in all 84 before/after
cases. The tradeoffs are small fixed instruction costs: empty operations add
32–35 instructions, and the measured unknown-only callback lookups add 9.
Complete canister Wasm grows by 150–9,389 bytes (0.06–3.39%) across those cases;
this includes the RTS, harness and validation. The report also measures mixed
known/unknown comparator programs without treating them as an isolated
dispatch-cost measurement.

## Instruction and allocation costs

Recorded PocketIC measurements for the ABI 1 plugins, using the same compiler
and typed inputs within each comparison. Lower is better. For JSON/CBOR, the
comparison below uses the lowest instruction count among the three tested
native libraries for each row.

| Operation | Native Motoko library | Native instructions | Plugin instructions | Native/plugin | Native allocated bytes | Plugin allocated bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| JSON encode, 1,024 records | `json 1.4.0` | 53,258,267 | 5,044,780 | 10.56× | 7,145,616 | 194,176 |
| JSON decode, 1,024 records | `serde 3.5.0` | 763,222,636 | 18,210,769 | 41.91× | 136,203,896 | 172,816 |
| CBOR encode, 1,024 records | `cbor 4.1.0` | 49,934,053 | 5,395,241 | 9.26× | 2,452,232 | 174,160 |
| CBOR decode, 1,024 records | `cbor 4.1.0` | 152,527,112 | 7,324,274 | 20.82× | 11,545,504 | 173,128 |
| CandidX encode, 1,024 sparse records | CandidX `94c2868` | 88,379,476 | 6,057,260 | 14.59× | 3,578,064 | 22,600 |
| SHA-256, 1 MiB | `sha2 0.2.5` | 323,721,060 | 78,124,848 | 4.14× | 1,008 | 56 |

Three trials; medians shown. Counts include conversions between typed values
and each library's representation. Input setup, validation, reply encoding,
and message-end GC are excluded. These measure complete implementations,
not the isolated benefit of the plugin boundary or Wasm components.
Allocated bytes include results and temporary garbage during the measured call;
they measure allocation pressure, not peak memory or retained live bytes after
GC. The same library supplies native instruction and allocation counts, chosen
by instruction cost.
Measured results: [JSON](benchmarks/results/optimization-round-2/json/README.md),
[CBOR](benchmarks/results/optimization-round-2/cbor/README.md),
[CandidX](benchmarks/results/optimization-round-2/candidx/README.md), and
[SHA-256](benchmarks/results/optimization-round-2/sha256/README.md).
They include smaller inputs, large payloads, and the observed serde stack
overflows on 64 KiB JSON strings.
The [second optimization report](benchmarks/results/optimization-round-2/README.md)
compares each plugin and the SDK before/after, with independent audits and
tradeoffs. Large-integer JSON encoding uses 40.75% fewer instructions and 46.84%
less allocation; CBOR Nat/Int array decoding uses about 20% fewer instructions
and 79% fewer allocated bytes.
These are different workloads from the record comparison above. Repeated-variant
CandidX encoding uses about 38% fewer instructions and 94% fewer allocated bytes,
while three sparse 4,096-case variant workloads use 4–14% more instructions. SHA-256 is unchanged after rejecting
slower alternatives.
The [first optimization report](benchmarks/results/optimization-round/README.md)
and [original library comparison](benchmarks/results/codec-comparison/README.md)
retain their original measurements.

## Set costs

The [Set comparison](benchmarks/results/set-comparison/README.md) records
**162 isolated cases × three trials** at **1,000, 10,000 and 100,000 elements**.
`mo:fast/Set` implements Core's mutable Set API with a key-only B-tree;
`mo:fast/pure/Set` uses a persistent AVL tree that shares unchanged branches.
Both store elements directly, without dummy map values.

Selected **100,000-element** results follow, using small `Nat` keys, Core 2.5.0,
and compiler `fc7612098`, before automatic comparator selection. Point operations
are per-call averages of 32 probes;
construction, traversal and union rows measure the complete operation.

| Set | Operation | Core instructions | Plugin callback | Plugin native Nat | Core allocated B | Plugin allocated B |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Mutable | `contains`, hit | 6,922.00 | 3,310.31 | 2,383.84 | 117.00 | 0.00 |
| Mutable | `insert`, new element | 10,878.44 | 5,725.00 | 4,723.59 | 190.00 | 42.50 |
| Mutable | `delete`, present | 13,116.97 | 5,019.12 | 4,015.94 | 390.50 | 0.00 |
| Mutable | Shuffled build | 1,122,897,592 | 537,705,079 | 441,427,620 | 16,980,040 | 1,766,408 |
| Mutable | `values`, full traversal | 165,712,687 | 89,157,191 | — | 11,065,504 | 352 |
| Pure | `contains`, hit | 2,939.22 | 1,257.50 | 779.03 | 40.00 | 0.00 |
| Pure | `insert`, new element | 13,378.34 | 9,714.72 | 8,751.00 | 2,257.00 | 1,184.00 |
| Pure | `insert`, existing element | 10,894.91 | 1,391.66 | 913.19 | 1,854.50 | 0.00 |
| Pure | `delete`, absent | 16,865.22 | 2,676.78 | 1,795.78 | 3,112.00 | 0.00 |
| Pure | Shuffled build | 1,201,847,247 | 881,028,223 | 794,177,092 | 208,815,600 | 109,580,416 |
| Pure | `values`, full traversal | 141,121,330 | 66,201,770 | — | 21,600,176 | 336 |
| Pure | `union`, 50% overlap | 1,350,943,241 | 59,278,088 | — | 229,550,160 | 7,652,120 |

Medians of three identical trials. Callback and native allocation match where
both are shown. Allocation is cumulative, including temporary garbage; it is
not retained or peak memory. Setup and correctness checks are outside the
measured interval, except construction itself. Traversal includes an element
count and bounded checksum. Each case runs in a fresh canister.

All measured callback and native cases use fewer instructions than Core, with
no allocation regressions. These compare complete data structures and
algorithms, not just plugin dispatch overhead. The
[full tables](benchmarks/set-comparison/RESULTS.md) include every measured size,
operation and scalar comparison; the [archive](benchmarks/results/set-comparison/)
contains raw metrics, source hashes and reproduction details.

## Earlier callback optimization

The earlier [callback report](benchmarks/results/callback-round/README.md) measures
36 point workloads at 1,000, 10,000 and 100,000 entries, with **612 samples**
across before/after builds. Each implementation runs in its own fresh
canister. The same actor and inputs are used for both builds; Core and scalar
ordering controls are unchanged, as are all allocation/reclamation counts.

Selected **100,000-entry** results, in instructions per call:

| Map | Operation | Core | Plugin before | Plugin after that round | Reduction | Plugin allocated B |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Persistent | Lookup, hit | 3,324.09 | 2,524.38 | 2,410.75 | 4.50% | 0 |
| Persistent | Insert new key | 14,112.34 | 10,137.75 | 10,019.75 | 1.16% | 1,289.25 |
| Persistent | Overwrite | 12,817.72 | 6,056.12 | 5,942.50 | 1.88% | 1,143 |
| Mutable | Lookup, hit | 7,701.16 | 3,876.91 | 3,765.66 | 2.87% | 0 |
| Mutable | Insert new key | 12,818.78 | 5,497.94 | 5,382.94 | 2.09% | 40 |
| Mutable | Overwrite | 8,529.06 | 4,491.41 | 4,380.16 | 2.48% | 40 |
| Mutable | Remove, hit | 14,060.38 | 7,767.81 | 7,654.47 | 1.46% | 0 |

Three identical trials, averaging 32 calls per batch. Compiler `fc7612098`
removes redundant callback argument spills; both map plugins load each
comparison result's tag once. The [isolated SDK benchmark](benchmarks/results/callback-round/sdk/README.md)
measures **5 fewer instructions per two-argument callback**, without allocation.
ABI 1 and the public APIs are unchanged. Generic keys and values remain shared
Motoko references.

In that cohort, explicit scalar ordering saves more: lookup uses 1,345.19
instructions for the persistent map and 2,712.34 for the mutable map. That difference includes
comparator work and boxed-key handling, as well as dispatch. The current SDK
selects scalar ordering through ordinary proven comparators; general callback
inlining remains a separate opportunity.

The full matrices below retain their original compilers and measurement
protocols. The callback report includes a phase-order diagnostic: the earlier
apparent scalar-removal regression disappears when scalar ordering runs first
or in a fresh canister. Its exact cause is not isolated; fresh canisters avoid
that execution-history bias in those comparisons.

## Mutable map costs

The mutable plugin updates ordinary Motoko nodes in place; keys and values stay
shared references. The baseline here is **mutable `mo:core/Map` 2.5.0**.
These measurements use compiler `abfba892f`, ABI 1, boxed `Nat64` keys and `Nat`
values. The callback path uses the same Motoko comparator as Core. Scalar
ordering removes that callback while keeping values generic.

Selected results at **100,000 entries** follow. Point operations are averages
per call in a 32-call batch; scans, transformations and construction are whole
function calls. Each result is the median of three identical trials.

| Operation | Core instructions | Plugin callback instructions | Plugin scalar instructions | Core allocated B | Plugin allocated B | Core/callback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `get`, hit | 7,700.16 | 3,877.41 | 2,755.84 | 123.00 | 0.00 | 1.99× |
| `add`, new key | 12,818.28 | 5,499.44 | 5,046.28 | 324.00 | 40.00 | 2.33× |
| `add`, overwrite | 8,528.06 | 4,492.91 | 3,439.84 | 286.00 | 40.00 | 1.90× |
| `delete`, hit | 14,111.88 | 7,835.81 | — | 520.25 | 0.00 | 1.80× |
| `find`, full scan | 170,277,593.00 | 40,524,835.00 | — | 11,059,840.00 | 72.00 | 4.20× |
| `fromIter`, shuffled construction | 1,175,071,733.00 | 566,138,242.00 | — | 30,051,776.00 | 5,842,360.00 | 2.08× |
| `map`, full transform | 60,103,065.00 | 76,139,742.00 | — | 6,441,152.00 | 5,842,432.00 | 0.79× |

Allocation is cumulative allocated bytes, including temporary garbage and
results, **not peak or retained live memory**. Scalar allocation matches the
callback path in these headline rows. Setup, seed cloning, correctness checks,
and message-end GC are outside the measured interval; all 900 measured samples
had zero synchronous reclamation. Normal updates do not clone the map.
Core has no matching `find` or `getEntry` function; their baselines use the small
public-API adapters listed in the full table.

The plugin uses fewer instructions in 135 workloads, ties in two, and loses in
one; `size` and `isEmpty` are effectively at parity. The 100,000-entry `map`
transform uses **26.7% more instructions**, with fewer allocated bytes.
This archived run measured implementations sequentially in one canister per
workload/trial. Its apparent scalar-removal regression was sensitive to phase
order; the [fresh-canister comparison](benchmarks/results/callback-round/README.md)
above supersedes that conclusion, while preserving these original results.
These are comparisons of complete implementations, including
wrapper functions, rather than a measurement of plugin dispatch alone.

The [full report](benchmarks/results/mutable-map/README.md) records reproduction
commands, the [independent audit](benchmarks/results/mutable-map/audit/README.md),
and the [performance review](benchmarks/results/mutable-map/performance-review.md).
The tables below retain all **138 workloads** at **1,000, 10,000, and 100,000
entries**, plus **24 scalar comparisons**. They cover lookup, insertion,
replacement, removal, predicate search, iteration, folds, transforms, cloning,
clearing and construction. Sorted input is ascending; shuffled input uses a
fixed permutation of the same entries. These are 46 workload variants per
size, not a claim that every convenience wrapper was benchmarked.

<details>
<summary>Full mutable-map function and scalar comparison tables</summary>

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](benchmarks/results/mutable-map/final/README.md) for exact semantics and validation.

### Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |
| `Map.fromArray` | fromArray-shuffled | 10,000 | 98,357,223.00 | 47,262,036.00 | 2,460,400.00 | 591,264.00 | 2.08× |
| `Map.fromArray` | fromArray-shuffled | 100,000 | 1,175,072,361.00 | 566,138,870.00 | 30,051,928.00 | 5,842,512.00 | 2.08× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,210.00 | 3,960,904.00 | 196,568.00 | 59,256.00 | 2.10× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 98,356,595.00 | 47,261,408.00 | 2,460,248.00 | 591,112.00 | 2.08× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,175,071,733.00 | 566,138,242.00 | 30,051,776.00 | 5,842,360.00 | 2.08× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,305.00 | 3,397,773.00 | 222,216.00 | 65,400.00 | 1.92× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 81,252,701.00 | 42,662,313.00 | 2,617,368.00 | 656,296.00 | 1.90× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 996,350,488.00 | 514,898,108.00 | 32,024,568.00 | 6,559,048.00 | 1.94× |
| `Map.fromVarArray` | fromVarArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |
| `Map.fromVarArray` | fromVarArray-shuffled | 10,000 | 98,357,223.00 | 47,262,036.00 | 2,460,400.00 | 591,264.00 | 2.08× |
| `Map.fromVarArray` | fromVarArray-shuffled | 100,000 | 1,175,072,377.00 | 566,138,870.00 | 30,051,928.00 | 5,842,512.00 | 2.08× |

### Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 200.00 | 40.00 | 2.07× |
| `Map.add` | add-insert | 10,000 | 10,115.12 | 5,153.06 | 230.00 | 63.00 | 1.96× |
| `Map.add` | add-insert | 100,000 | 12,818.28 | 5,499.44 | 324.00 | 40.00 | 2.33× |
| `Map.add` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 230.00 | 40.00 | 1.92× |
| `Map.add` | add-overwrite | 10,000 | 6,920.69 | 4,066.25 | 230.00 | 63.00 | 1.70× |
| `Map.add` | add-overwrite | 100,000 | 8,528.06 | 4,492.91 | 286.00 | 40.00 | 1.90× |
| `Map.all` | all-true | 1,000 | 1,626,450.00 | 351,618.00 | 110,776.00 | 112.00 | 4.63× |
| `Map.all` | all-true | 10,000 | 16,250,883.00 | 3,510,212.00 | 1,104,912.00 | 112.00 | 4.63× |
| `Map.all` | all-true | 100,000 | 162,473,523.00 | 38,624,994.00 | 11,059,840.00 | 112.00 | 4.21× |
| `Map.any` | any-false | 1,000 | 1,626,450.00 | 320,465.00 | 110,776.00 | 72.00 | 5.08× |
| `Map.any` | any-false | 10,000 | 16,250,883.00 | 3,200,059.00 | 1,104,912.00 | 72.00 | 5.08× |
| `Map.any` | any-false | 100,000 | 162,473,523.00 | 35,524,792.00 | 11,059,840.00 | 72.00 | 4.57× |
| `Map.clear` | clear | 1,000 | 2,171.00 | 355.00 | 488.00 | 0.00 | 6.12× |
| `Map.clear` | clear | 10,000 | 2,171.00 | 371.00 | 488.00 | 0.00 | 5.85× |
| `Map.clear` | clear | 100,000 | 2,171.00 | 371.00 | 488.00 | 0.00 | 5.85× |
| `Map.clone` | clone | 1,000 | 483,718.00 | 274,607.00 | 66,104.00 | 23,656.00 | 1.76× |
| `Map.clone` | clone | 10,000 | 4,890,614.00 | 2,715,273.00 | 665,536.00 | 235,200.00 | 1.80× |
| `Map.clone` | clone | 100,000 | 46,303,078.00 | 27,726,005.00 | 6,441,152.00 | 2,268,456.00 | 1.67× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 5,334.41 | 2,565.41 | 95.00 | 0.00 | 2.08× |
| `Map.containsKey` | containsKey-mixed | 10,000 | 6,389.16 | 3,108.16 | 95.00 | 0.00 | 2.06× |
| `Map.containsKey` | containsKey-mixed | 100,000 | 7,939.84 | 3,911.09 | 125.00 | 0.00 | 2.03× |
| `Map.delete` | delete-hit | 1,000 | 10,289.19 | 3,873.62 | 357.75 | 0.00 | 2.66× |
| `Map.delete` | delete-hit | 10,000 | 11,314.97 | 6,486.53 | 360.25 | 0.00 | 1.74× |
| `Map.delete` | delete-hit | 100,000 | 14,111.88 | 7,835.81 | 520.25 | 0.00 | 1.80× |
| `Map.delete` | delete-miss | 1,000 | 6,936.62 | 2,921.78 | 320.00 | 0.00 | 2.37× |
| `Map.delete` | delete-miss | 10,000 | 8,066.88 | 5,480.22 | 320.00 | 0.00 | 1.47× |
| `Map.delete` | delete-miss | 100,000 | 10,433.16 | 6,947.97 | 464.00 | 0.00 | 1.50× |
| `Map.entries` | entries-consume | 1,000 | 1,696,599.00 | 945,701.00 | 110,776.00 | 352.00 | 1.79× |
| `Map.entries` | entries-consume | 10,000 | 16,951,848.00 | 9,447,915.00 | 1,104,912.00 | 352.00 | 1.79× |
| `Map.entries` | entries-consume | 100,000 | 169,477,640.00 | 104,840,203.00 | 11,059,840.00 | 352.00 | 1.62× |
| `Map.entries` | entries-create | 1,000 | 3,165.38 | 1,848.38 | 432.00 | 352.00 | 1.71× |
| `Map.entries` | entries-create | 10,000 | 3,167.38 | 1,850.38 | 432.00 | 352.00 | 1.71× |
| `Map.entries` | entries-create | 100,000 | 3,868.75 | 1,890.75 | 512.00 | 352.00 | 2.05× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 35,069.38 | 24,661.12 | 2,267.00 | 792.00 | 1.42× |
| `Map.entriesFrom` | entriesFrom-seek16 | 10,000 | 36,321.12 | 26,986.38 | 2,292.00 | 927.00 | 1.35× |
| `Map.entriesFrom` | entriesFrom-seek16 | 100,000 | 38,699.75 | 29,808.75 | 2,376.00 | 1,082.00 | 1.30× |
| `Map.filter` | filter | 1,000 | 4,476,594.00 | 1,851,216.00 | 204,784.00 | 32,288.00 | 2.42× |
| `Map.filter` | filter | 10,000 | 54,291,831.00 | 23,460,534.00 | 2,377,656.00 | 327,552.00 | 2.31× |
| `Map.filter` | filter | 100,000 | 634,923,429.00 | 307,720,064.00 | 26,747,752.00 | 3,280,048.00 | 2.06× |
| `Map.filterMap` | filterMap | 1,000 | 4,514,594.00 | 1,888,216.00 | 204,784.00 | 32,288.00 | 2.39× |
| `Map.filterMap` | filterMap | 10,000 | 54,671,831.00 | 23,830,534.00 | 2,377,656.00 | 327,552.00 | 2.29× |
| `Map.filterMap` | filterMap | 100,000 | 638,723,429.00 | 311,420,064.00 | 26,747,752.00 | 3,280,048.00 | 2.05× |
| `Map.find` | find-first | 1,000 | 5,101.00 | 2,027.00 | 544.00 | 72.00 | 2.52× |
| `Map.find` | find-first | 10,000 | 5,101.00 | 2,043.00 | 544.00 | 72.00 | 2.50× |
| `Map.find` | find-first | 100,000 | 5,788.00 | 2,448.00 | 624.00 | 72.00 | 2.36× |
| `Map.find` | find-last | 1,000 | 1,704,466.00 | 370,371.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.find` | find-last | 10,000 | 17,031,715.00 | 3,699,965.00 | 1,104,912.00 | 72.00 | 4.60× |
| `Map.find` | find-last | 100,000 | 170,277,507.00 | 40,524,763.00 | 11,059,840.00 | 72.00 | 4.20× |
| `Map.find` | find-middle | 1,000 | 856,010.00 | 186,188.00 | 55,904.00 | 72.00 | 4.60× |
| `Map.find` | find-middle | 10,000 | 8,521,210.00 | 1,852,989.00 | 552,800.00 | 72.00 | 4.60× |
| `Map.find` | find-middle | 100,000 | 85,147,713.00 | 20,294,803.00 | 5,528,224.00 | 72.00 | 4.20× |
| `Map.find` | find-missing | 1,000 | 1,704,552.00 | 370,453.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.find` | find-missing | 10,000 | 17,031,801.00 | 3,700,047.00 | 1,104,912.00 | 72.00 | 4.60× |
| `Map.find` | find-missing | 100,000 | 170,277,593.00 | 40,524,835.00 | 11,059,840.00 | 72.00 | 4.20× |
| `Map.foldLeft` | foldLeft | 1,000 | 1,696,555.00 | 388,927.00 | 110,776.00 | 72.00 | 4.36× |
| `Map.foldLeft` | foldLeft | 10,000 | 16,951,804.00 | 3,884,523.00 | 1,104,912.00 | 72.00 | 4.36× |
| `Map.foldLeft` | foldLeft | 100,000 | 169,477,596.00 | 42,370,980.00 | 11,059,840.00 | 72.00 | 4.00× |
| `Map.foldRight` | foldRight | 1,000 | 1,677,742.00 | 396,827.00 | 110,776.00 | 72.00 | 4.23× |
| `Map.foldRight` | foldRight | 10,000 | 16,768,200.00 | 3,963,521.00 | 1,104,912.00 | 72.00 | 4.23× |
| `Map.foldRight` | foldRight | 100,000 | 167,556,774.00 | 43,161,296.00 | 11,059,840.00 | 72.00 | 3.88× |
| `Map.forEach` | forEach | 1,000 | 1,821,462.00 | 547,990.00 | 110,776.00 | 112.00 | 3.32× |
| `Map.forEach` | forEach | 10,000 | 18,201,711.00 | 5,474,586.00 | 1,104,912.00 | 112.00 | 3.32× |
| `Map.forEach` | forEach | 100,000 | 181,977,503.00 | 61,871,056.00 | 11,059,840.00 | 112.00 | 2.94× |
| `Map.get` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 95.00 | 0.00 | 2.01× |
| `Map.get` | get-hit | 10,000 | 6,235.03 | 3,080.44 | 95.00 | 0.00 | 2.02× |
| `Map.get` | get-hit | 100,000 | 7,700.16 | 3,877.41 | 123.00 | 0.00 | 1.99× |
| `Map.get` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 96.00 | 0.00 | 2.01× |
| `Map.get` | get-miss | 10,000 | 6,471.53 | 3,183.72 | 96.00 | 0.00 | 2.03× |
| `Map.get` | get-miss | 100,000 | 8,177.69 | 3,986.66 | 128.00 | 0.00 | 2.05× |
| `Map.getEntry` | getEntry-hit | 1,000 | 5,290.91 | 2,536.59 | 135.00 | 0.00 | 2.09× |
| `Map.getEntry` | getEntry-hit | 10,000 | 6,407.03 | 3,065.44 | 135.00 | 0.00 | 2.09× |
| `Map.getEntry` | getEntry-hit | 100,000 | 7,872.16 | 3,862.41 | 163.00 | 0.00 | 2.04× |
| `Map.insert` | insert-mixed | 1,000 | 7,150.06 | 3,649.56 | 214.00 | 40.00 | 1.96× |
| `Map.insert` | insert-mixed | 10,000 | 8,927.03 | 4,686.22 | 244.00 | 63.00 | 1.90× |
| `Map.insert` | insert-mixed | 100,000 | 10,794.69 | 4,942.53 | 304.00 | 40.00 | 2.18× |
| `Map.isEmpty` | isEmpty | 1,000 | 267.09 | 267.09 | 0.00 | 0.00 | 1.00× |
| `Map.isEmpty` | isEmpty | 10,000 | 267.59 | 267.09 | 0.00 | 0.00 | 1.00× |
| `Map.isEmpty` | isEmpty | 100,000 | 267.59 | 266.09 | 0.00 | 0.00 | 1.01× |
| `Map.map` | map | 1,000 | 621,705.00 | 600,904.00 | 66,104.00 | 59,328.00 | 1.03× |
| `Map.map` | map | 10,000 | 6,270,601.00 | 6,000,018.00 | 665,536.00 | 591,184.00 | 1.05× |
| `Map.map` | map | 100,000 | 60,103,065.00 | 76,139,742.00 | 6,441,152.00 | 5,842,432.00 | 0.79× |
| `Map.maxEntry` | maxEntry | 1,000 | 5,108.09 | 1,451.59 | 544.00 | 0.00 | 3.52× |
| `Map.maxEntry` | maxEntry | 10,000 | 5,107.59 | 1,452.09 | 544.00 | 0.00 | 3.52× |
| `Map.maxEntry` | maxEntry | 100,000 | 5,969.09 | 1,873.59 | 624.00 | 0.00 | 3.19× |
| `Map.minEntry` | minEntry | 1,000 | 4,641.09 | 1,405.59 | 544.00 | 0.00 | 3.30× |
| `Map.minEntry` | minEntry | 10,000 | 4,641.09 | 1,406.09 | 544.00 | 0.00 | 3.30× |
| `Map.minEntry` | minEntry | 100,000 | 5,296.59 | 1,827.59 | 624.00 | 0.00 | 2.90× |
| `Map.remove` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 357.75 | 0.00 | 2.69× |
| `Map.remove` | remove-hit | 10,000 | 11,262.97 | 6,420.53 | 360.25 | 0.00 | 1.75× |
| `Map.remove` | remove-hit | 100,000 | 14,059.88 | 7,769.31 | 520.25 | 0.00 | 1.81× |
| `Map.remove` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 320.00 | 0.00 | 2.41× |
| `Map.remove` | remove-miss | 10,000 | 8,014.88 | 5,414.22 | 320.00 | 0.00 | 1.48× |
| `Map.remove` | remove-miss | 100,000 | 10,381.16 | 6,881.47 | 464.00 | 0.00 | 1.51× |
| `Map.replace` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 325.00 | 40.00 | 3.85× |
| `Map.replace` | replace-hit | 10,000 | 13,003.06 | 3,337.44 | 325.00 | 40.00 | 3.90× |
| `Map.replace` | replace-hit | 100,000 | 16,024.56 | 4,148.91 | 409.00 | 40.00 | 3.86× |
| `Map.replace` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 96.00 | 0.00 | 2.01× |
| `Map.replace` | replace-miss | 10,000 | 6,571.53 | 3,230.72 | 96.00 | 0.00 | 2.03× |
| `Map.replace` | replace-miss | 100,000 | 8,277.69 | 4,033.66 | 128.00 | 0.00 | 2.05× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,677,786.00 | 841,552.00 | 110,776.00 | 352.00 | 1.99× |
| `Map.reverseEntries` | reverseEntries-consume | 10,000 | 16,768,244.00 | 8,404,549.00 | 1,104,912.00 | 352.00 | 2.00× |
| `Map.reverseEntries` | reverseEntries-consume | 100,000 | 167,556,818.00 | 94,416,057.00 | 11,059,840.00 | 352.00 | 1.77× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 3,661.38 | 1,848.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntries` | reverseEntries-create | 10,000 | 3,663.38 | 1,850.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntries` | reverseEntries-create | 100,000 | 4,573.75 | 1,890.75 | 512.00 | 352.00 | 2.42× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 1,000 | 34,323.25 | 24,613.62 | 2,258.00 | 1,032.00 | 1.39× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 10,000 | 35,910.00 | 27,235.38 | 2,306.00 | 1,227.00 | 1.32× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 100,000 | 38,254.00 | 30,717.75 | 2,376.00 | 1,472.00 | 1.25× |
| `Map.size` | size | 1,000 | 253.09 | 253.09 | 0.00 | 0.00 | 1.00× |
| `Map.size` | size | 10,000 | 253.59 | 253.09 | 0.00 | 0.00 | 1.00× |
| `Map.size` | size | 100,000 | 253.59 | 252.09 | 0.00 | 0.00 | 1.01× |
| `Map.swap` | swap-hit | 1,000 | 5,856.56 | 3,107.09 | 230.00 | 40.00 | 1.88× |
| `Map.swap` | swap-hit | 10,000 | 6,977.69 | 4,149.25 | 230.00 | 63.00 | 1.68× |
| `Map.swap` | swap-hit | 100,000 | 8,585.06 | 4,576.41 | 286.00 | 40.00 | 1.88× |
| `Map.take` | take-hit | 1,000 | 10,270.19 | 3,891.62 | 357.75 | 0.00 | 2.64× |
| `Map.take` | take-hit | 10,000 | 11,295.97 | 6,504.53 | 360.25 | 0.00 | 1.74× |
| `Map.take` | take-hit | 100,000 | 14,092.88 | 7,853.81 | 520.25 | 0.00 | 1.79× |
| `Map.take` | take-miss | 1,000 | 6,923.62 | 2,929.78 | 320.00 | 0.00 | 2.36× |
| `Map.take` | take-miss | 10,000 | 8,053.88 | 5,488.22 | 320.00 | 0.00 | 1.47× |
| `Map.take` | take-miss | 100,000 | 10,420.16 | 6,955.97 | 464.00 | 0.00 | 1.50× |
| `Map.toArray` | toArray | 1,000 | 2,180,442.00 | 819,710.00 | 182,992.00 | 8,416.00 | 2.66× |
| `Map.toArray` | toArray | 10,000 | 21,782,195.00 | 8,187,172.00 | 1,825,128.00 | 80,416.00 | 2.66× |
| `Map.toArray` | toArray | 100,000 | 217,778,205.00 | 92,236,670.00 | 18,260,056.00 | 800,416.00 | 2.36× |
| `Map.toVarArray` | toVarArray | 1,000 | 2,339,758.00 | 819,710.00 | 191,016.00 | 8,416.00 | 2.85× |
| `Map.toVarArray` | toVarArray | 10,000 | 23,372,543.00 | 8,187,156.00 | 1,905,152.00 | 80,416.00 | 2.85× |
| `Map.toVarArray` | toVarArray | 100,000 | 233,678,905.00 | 92,236,638.00 | 19,060,080.00 | 800,416.00 | 2.53× |

### Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 3,337.81 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-insert | 10,000 | 10,115.12 | 5,153.06 | 4,182.72 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-insert | 100,000 | 12,818.28 | 5,499.44 | 5,046.28 | 324.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 2,307.03 | 230.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 10,000 | 6,920.69 | 4,066.25 | 3,136.88 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-overwrite | 100,000 | 8,528.06 | 4,492.91 | 3,439.84 | 286.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 1,835.03 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 6,235.03 | 3,080.44 | 2,151.06 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 7,700.16 | 3,877.41 | 2,755.84 | 123.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 1,899.53 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 6,471.53 | 3,183.72 | 2,213.38 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 8,177.69 | 3,986.66 | 2,834.34 | 128.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 3,090.56 | 357.75 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 10,000 | 11,262.97 | 6,420.53 | 5,494.69 | 360.25 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 100,000 | 14,059.88 | 7,769.31 | 8,884.69 | 520.25 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 2,096.47 | 320.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 10,000 | 8,014.88 | 5,414.22 | 4,445.62 | 320.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 100,000 | 10,381.16 | 6,881.47 | 7,262.44 | 464.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 2,090.03 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-hit | 10,000 | 13,003.06 | 3,337.44 | 2,408.06 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-hit | 100,000 | 16,024.56 | 4,148.91 | 3,138.34 | 409.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 1,946.53 | 96.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 10,000 | 6,571.53 | 3,230.72 | 2,260.38 | 96.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 100,000 | 8,277.69 | 4,033.66 | 2,881.34 | 128.00 | 0.00 | 0.00 |

### Core baseline details

Explicit adapters are used where Core has no matching public API. All direct baselines use mo:core/Map 2.5.0; find/getEntry use the listed small public API adapters.

| Workload | Core baseline | Note |
| --- | --- | --- |
| find-first | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-last | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-middle | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-missing | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| getEntry-hit | `get + optional pair` | Core.get mapped to the requested key; exact Nat64 key ordering makes keys equivalent. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](benchmarks/results/mutable-map/final/summary.csv).

</details>

## Persistent map costs

The complete matrix below covers **111 workloads** at **1,000, 10,000, and
100,000 entries**: 37 variants per size across 27 generic public functions and
three scalar helpers. Each reported count is the median of three identical trials.

The [second optimization round](benchmarks/results/optimization-round-2/pure-map/README.md)
refreshed 30 workloads: `get-hit/miss`, `getEntry-hit`, `containsKey-mixed`, all
construction rows, `add-overwrite`, `find-missing`, and `foldLeft` at each size.
These rows use compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f` and include
207 measurements per version. The remaining 81 workloads retain the
[previous full comparison](benchmarks/results/optimization-round/pure-map/README.md),
measured with compiler `f1ccbba5e445df9db03bbc35be557187ade9b436`.
Its [compiler audit](benchmarks/results/optimization-round/integrated/pure-map/audit.md)
confirms unchanged benchmark function bodies under `c320bf90d`; it adds no new
measurements. The original full run validated all 720 measurements.

The baseline is `core 2.5.0` pure Map. Keys are boxed `Nat64` values, with
the same input order for both implementations. The plugin callback path uses
the same ordinary Motoko comparator as Core; scalar ordering is shown separately.
Input setup is outside timing, and construction is measured separately from
operations on populated maps. Sorted input arrives in ascending key order;
shuffled input contains the same entries in a deterministic randomized order.
The plugin builds directly from sorted input, avoiding the sorting step needed
for shuffled input. `add` is put; `swap` also returns the previous
value. `find` is tested at the first, middle, last, and absent positions.
The iterator-related APIs tested are `fromIter`, `entriesFrom`, and the other names
shown below; there is no public `findIter` function.

This round reduces callback lookup instructions by 2.5–3.1%, scalar Nat64 lookup
by 4.7–5.7%, and shuffled construction by 3.4–4.5%, with allocation unchanged.
At 100,000 entries, shuffled `fromIter` now uses 2.34% fewer instructions and
65.9% fewer allocated bytes than Core. It still uses 3.38% more instructions at
1,000 entries and 2.92% more at 10,000. Core also uses fewer instructions for
cursor creation alone and full-map snapshot creation.

Both folds use fewer instructions than Core and allocate zero bytes. The prior
wrapper optimization reduced fold instructions by about 32% and full iterator
consumption by about 8.4%; bounded seek-and-consume workloads also improved.
Both libraries share unchanged branches. Plugin updates copy changed paths and
retain payload references; separate GC tests verify that updating a map with a
1 MiB payload allocates the same amount as with a 5-byte payload.
Core adapters are identified below where it lacks a matching public operation;
these compare complete algorithms and capabilities.

PocketIC 14 runs use fresh canisters and four forced GC increments before each
phase. Synchronous reclamation is reported separately; none occurred in these
measurements. End-of-message GC is outside the measured interval.

Three-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, split, and construction rows measure the complete function call. Snapshot creation is per captured root/snapshot. Core adapters are listed below; see [methodology](benchmarks/results/optimization-round/pure-map/README.md) for exact semantics and validation.

### Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 7,606,083.00 | 6,788,543.00 | 1,395,104.00 | 463,216.00 | 1.12× |
| `Map.fromArray` | fromArray-shuffled | 10,000 | 102,601,814.00 | 93,269,585.00 | 18,838,600.00 | 6,369,896.00 | 1.10× |
| `Map.fromArray` | fromArray-shuffled | 100,000 | 1,233,077,190.00 | 1,089,625,017.00 | 224,253,736.00 | 73,573,936.00 | 1.13× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 7,605,488.00 | 7,862,332.00 | 1,394,952.00 | 487,880.00 | 0.97× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 102,601,219.00 | 105,596,698.00 | 18,838,448.00 | 6,712,416.00 | 0.97× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,233,076,595.00 | 1,204,273,073.00 | 224,253,584.00 | 76,471,536.00 | 1.02× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 10,203,874.00 | 1,727,096.00 | 1,831,072.00 | 96,688.00 | 5.91× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 135,473,401.00 | 18,857,900.00 | 23,988,728.00 | 1,062,544.00 | 7.18× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 1,694,931,186.00 | 179,953,531.00 | 297,345,304.00 | 10,097,624.00 | 9.42× |

### Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 1,840.50 | 850.50 | 1.51× |
| `Map.add` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 2,034.50 | 1,107.00 | 1.35× |
| `Map.add` | add-insert | 100,000 | 14,112.34 | 10,148.47 | 2,524.25 | 1,289.25 | 1.39× |
| `Map.add` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 1,395.50 | 677.25 | 2.16× |
| `Map.add` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 1,816.75 | 913.50 | 2.10× |
| `Map.add` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 2,230.50 | 1,143.00 | 2.11× |
| `Map.alter` | alter-mixed | 1,000 | 11,258.12 | 5,561.62 | 1,647.00 | 822.75 | 2.02× |
| `Map.alter` | alter-mixed | 10,000 | 13,678.84 | 7,205.69 | 1,944.00 | 1,077.00 | 1.90× |
| `Map.alter` | alter-mixed | 100,000 | 16,945.25 | 8,521.84 | 2,422.75 | 1,281.75 | 1.99× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 2,183.69 | 1,644.38 | 0.00 | 0.00 | 1.33× |
| `Map.containsKey` | containsKey-mixed | 10,000 | 2,831.84 | 2,187.19 | 0.00 | 0.00 | 1.29× |
| `Map.containsKey` | containsKey-mixed | 100,000 | 3,450.09 | 2,581.88 | 0.00 | 0.00 | 1.34× |
| `Map.delete` | delete-mixed | 1,000 | 10,437.75 | 4,015.50 | 1,987.75 | 357.50 | 2.60× |
| `Map.delete` | delete-mixed | 10,000 | 14,751.44 | 5,245.69 | 2,885.00 | 467.75 | 2.81× |
| `Map.delete` | delete-mixed | 100,000 | 17,230.59 | 6,426.88 | 3,373.00 | 596.00 | 2.68× |
| `Map.entries` | entries-consume | 1,000 | 1,608,622.00 | 1,134,244.00 | 256,176.00 | 40,400.00 | 1.42× |
| `Map.entries` | entries-consume | 10,000 | 16,219,373.00 | 11,320,184.00 | 2,560,176.00 | 400,432.00 | 1.43× |
| `Map.entries` | entries-consume | 100,000 | 161,456,649.00 | 113,128,799.00 | 25,600,176.00 | 4,000,464.00 | 1.43× |
| `Map.entries` | entries-create | 1,000 | 1,072.38 | 2,363.38 | 176.00 | 400.00 | 0.45× |
| `Map.entries` | entries-create | 10,000 | 1,072.38 | 2,427.38 | 176.00 | 432.00 | 0.44× |
| `Map.entries` | entries-create | 100,000 | 1,108.75 | 2,519.75 | 176.00 | 464.00 | 0.44× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 794,041.00 | 25,771.38 | 131,432.00 | 1,072.00 | 30.81× |
| `Map.entriesFrom` | entriesFrom-seek16 | 10,000 | 7,819,157.12 | 27,718.00 | 1,283,656.00 | 1,104.00 | 282.10× |
| `Map.entriesFrom` | entriesFrom-seek16 | 100,000 | 77,630,138.25 | 28,683.00 | 12,804,424.00 | 1,136.00 | 2706.49× |
| `Map.entriesInRange` | entriesInRange-seek16 | 1,000 | 798,511.00 | 27,276.12 | 131,584.00 | 1,040.00 | 29.28× |
| `Map.entriesInRange` | entriesInRange-seek16 | 10,000 | 7,823,627.12 | 30,075.38 | 1,283,808.00 | 1,072.00 | 260.13× |
| `Map.entriesInRange` | entriesInRange-seek16 | 100,000 | 77,634,608.25 | 31,463.75 | 12,804,576.00 | 1,104.00 | 2467.43× |
| `Map.filterMap` | filterMap | 1,000 | 4,885,562.00 | 746,683.00 | 829,640.00 | 68,904.00 | 6.54× |
| `Map.filterMap` | filterMap | 10,000 | 65,605,684.00 | 7,101,817.00 | 11,134,592.00 | 614,448.00 | 9.24× |
| `Map.filterMap` | filterMap | 100,000 | 825,830,263.00 | 75,473,263.00 | 140,072,896.00 | 7,070,760.00 | 10.94× |
| `Map.find` | find-first | 1,000 | 11,292.00 | 1,927.00 | 2,224.00 | 112.00 | 5.86× |
| `Map.find` | find-first | 10,000 | 21,897.00 | 2,253.00 | 4,528.00 | 112.00 | 9.72× |
| `Map.find` | find-first | 100,000 | 24,253.00 | 2,645.00 | 5,040.00 | 112.00 | 9.17× |
| `Map.find` | find-last | 1,000 | 1,616,489.00 | 329,393.00 | 256,176.00 | 112.00 | 4.91× |
| `Map.find` | find-last | 10,000 | 16,299,240.00 | 3,288,081.00 | 2,560,176.00 | 112.00 | 4.96× |
| `Map.find` | find-last | 100,000 | 162,256,516.00 | 32,805,905.00 | 25,600,176.00 | 112.00 | 4.95× |
| `Map.find` | find-middle | 1,000 | 817,769.00 | 166,211.00 | 129,968.00 | 112.00 | 4.92× |
| `Map.find` | find-middle | 10,000 | 8,159,271.00 | 1,648,899.00 | 1,281,200.00 | 112.00 | 4.95× |
| `Map.find` | find-middle | 100,000 | 81,141,704.00 | 16,407,115.00 | 12,802,224.00 | 112.00 | 4.95× |
| `Map.find` | find-missing | 1,000 | 1,616,602.00 | 329,278.00 | 256,176.00 | 72.00 | 4.91× |
| `Map.find` | find-missing | 10,000 | 16,299,353.00 | 3,287,966.00 | 2,560,176.00 | 72.00 | 4.96× |
| `Map.find` | find-missing | 100,000 | 162,256,629.00 | 32,805,790.00 | 25,600,176.00 | 72.00 | 4.95× |
| `Map.foldLeft` | foldLeft | 1,000 | 315,007.00 | 312,965.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldLeft` | foldLeft | 10,000 | 3,204,063.00 | 3,127,653.00 | 0.00 | 0.00 | 1.02× |
| `Map.foldLeft` | foldLeft | 100,000 | 31,665,567.00 | 31,205,477.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldRight` | foldRight | 1,000 | 315,007.00 | 312,965.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldRight` | foldRight | 10,000 | 3,204,063.00 | 3,127,653.00 | 0.00 | 0.00 | 1.02× |
| `Map.foldRight` | foldRight | 100,000 | 31,665,567.00 | 31,205,477.00 | 0.00 | 0.00 | 1.01× |
| `Map.get` | get-hit | 1,000 | 2,041.19 | 1,604.38 | 0.00 | 0.00 | 1.27× |
| `Map.get` | get-hit | 10,000 | 2,736.97 | 2,129.44 | 0.00 | 0.00 | 1.29× |
| `Map.get` | get-hit | 100,000 | 3,324.09 | 2,524.38 | 0.00 | 0.00 | 1.32× |
| `Map.get` | get-miss | 1,000 | 2,237.69 | 1,710.88 | 0.00 | 0.00 | 1.31× |
| `Map.get` | get-miss | 10,000 | 2,942.59 | 2,248.19 | 0.00 | 0.00 | 1.31× |
| `Map.get` | get-miss | 100,000 | 3,518.72 | 2,649.88 | 0.00 | 0.00 | 1.33× |
| `Map.getEntry` | getEntry-hit | 1,000 | 2,213.19 | 1,742.38 | 40.00 | 40.00 | 1.27× |
| `Map.getEntry` | getEntry-hit | 10,000 | 2,908.97 | 2,267.44 | 40.00 | 40.00 | 1.28× |
| `Map.getEntry` | getEntry-hit | 100,000 | 3,496.09 | 2,662.38 | 40.00 | 40.00 | 1.31× |
| `Map.insert` | insert-mixed | 1,000 | 9,122.19 | 5,332.62 | 1,607.00 | 782.75 | 1.71× |
| `Map.insert` | insert-mixed | 10,000 | 11,000.25 | 6,976.69 | 1,904.00 | 1,037.00 | 1.58× |
| `Map.insert` | insert-mixed | 100,000 | 13,585.41 | 8,292.34 | 2,382.75 | 1,241.75 | 1.64× |
| `Map.map` | map | 1,000 | 629,222.00 | 504,947.00 | 88,112.00 | 72,072.00 | 1.25× |
| `Map.map` | map | 10,000 | 6,340,550.00 | 5,043,811.00 | 880,112.00 | 720,072.00 | 1.26× |
| `Map.map` | map | 100,000 | 63,111,408.00 | 50,442,421.00 | 8,800,112.00 | 7,200,072.00 | 1.25× |
| `Map.rank` | rank | 1,000 | 743,056.50 | 1,906.12 | 129,264.00 | 40.00 | 389.83× |
| `Map.rank` | rank | 10,000 | 7,449,898.00 | 2,962.38 | 1,281,776.00 | 40.00 | 2514.84× |
| `Map.rank` | rank | 100,000 | 74,044,883.88 | 3,350.88 | 12,802,192.00 | 40.00 | 22097.18× |
| `Map.replace` | replace-hit | 1,000 | 9,848.69 | 3,851.75 | 1,355.50 | 677.25 | 2.56× |
| `Map.replace` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 1,776.75 | 913.50 | 2.52× |
| `Map.replace` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 2,190.50 | 1,143.00 | 2.56× |
| `Map.replace` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 0.00 | 0.00 | 1.16× |
| `Map.replace` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 0.00 | 0.00 | 1.17× |
| `Map.replace` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 0.00 | 0.00 | 1.18× |
| `Map.replay` | replay-consume | 1,000 | 1,608,622.00 | 1,134,024.00 | 256,176.00 | 40,344.00 | 1.42× |
| `Map.replay` | replay-consume | 10,000 | 16,219,373.00 | 11,319,964.00 | 2,560,176.00 | 400,376.00 | 1.43× |
| `Map.replay` | replay-consume | 100,000 | 161,456,649.00 | 113,128,579.00 | 25,600,176.00 | 4,000,408.00 | 1.43× |
| `Map.replay` | replay-create | 1,000 | 1,072.38 | 2,143.38 | 176.00 | 344.00 | 0.50× |
| `Map.replay` | replay-create | 10,000 | 1,072.38 | 2,207.38 | 176.00 | 376.00 | 0.49× |
| `Map.replay` | replay-create | 100,000 | 1,108.75 | 2,299.75 | 176.00 | 408.00 | 0.48× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,608,628.00 | 1,134,352.00 | 256,176.00 | 40,400.00 | 1.42× |
| `Map.reverseEntries` | reverseEntries-consume | 10,000 | 16,219,379.00 | 11,320,292.00 | 2,560,176.00 | 400,432.00 | 1.43× |
| `Map.reverseEntries` | reverseEntries-consume | 100,000 | 161,456,655.00 | 113,128,907.00 | 25,600,176.00 | 4,000,464.00 | 1.43× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 1,078.38 | 2,471.38 | 176.00 | 400.00 | 0.44× |
| `Map.reverseEntries` | reverseEntries-create | 10,000 | 1,078.38 | 2,535.38 | 176.00 | 432.00 | 0.43× |
| `Map.reverseEntries` | reverseEntries-create | 100,000 | 1,114.75 | 2,627.75 | 176.00 | 464.00 | 0.42× |
| `Map.select` | select | 1,000 | 753,479.12 | 1,069.38 | 129,264.00 | 40.00 | 704.60× |
| `Map.select` | select | 10,000 | 7,554,302.62 | 1,481.62 | 1,281,776.00 | 40.00 | 5098.66× |
| `Map.select` | select | 100,000 | 75,094,764.50 | 1,702.38 | 12,802,192.00 | 40.00 | 44111.76× |
| `Map.snapshot` | snapshot-create | 1,000 | 229.38 | 443.38 | 0.00 | 56.00 | 0.52× |
| `Map.snapshot` | snapshot-create | 10,000 | 229.38 | 443.38 | 0.00 | 56.00 | 0.52× |
| `Map.snapshot` | snapshot-create | 100,000 | 267.75 | 479.75 | 0.00 | 56.00 | 0.56× |
| `Map.splitLookup` | splitLookup | 1,000 | 11,357,872.75 | 7,113.75 | 2,084,524.00 | 898.00 | 1596.61× |
| `Map.splitLookup` | splitLookup | 10,000 | 147,468,978.00 | 10,385.75 | 26,562,892.00 | 1,420.00 | 14199.17× |
| `Map.splitLookup` | splitLookup | 100,000 | 1,826,728,244.33 | 14,913.33 | 325,209,429.33 | 1,496.00 | 122489.60× |
| `Map.swap` | swap-hit | 1,000 | 8,044.25 | 4,016.75 | 1,355.50 | 717.25 | 2.00× |
| `Map.swap` | swap-hit | 10,000 | 10,408.78 | 5,236.44 | 1,776.75 | 953.50 | 1.99× |
| `Map.swap` | swap-hit | 100,000 | 12,734.72 | 6,317.84 | 2,190.50 | 1,183.00 | 2.02× |
| `Map.take` | take-hit | 1,000 | 10,700.91 | 5,910.31 | 2,060.75 | 717.25 | 1.81× |
| `Map.take` | take-hit | 10,000 | 15,427.75 | 7,725.25 | 3,014.00 | 931.00 | 2.00× |
| `Map.take` | take-hit | 100,000 | 17,354.00 | 9,607.38 | 3,402.50 | 1,187.50 | 1.81× |
| `Map.update` | update-mixed | 1,000 | 11,186.12 | 5,514.62 | 1,607.00 | 782.75 | 2.03× |
| `Map.update` | update-mixed | 10,000 | 13,606.84 | 7,158.69 | 1,904.00 | 1,037.00 | 1.90× |
| `Map.update` | update-mixed | 100,000 | 16,873.25 | 8,474.84 | 2,382.75 | 1,241.75 | 1.99× |

### Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 5,824.16 | 1,840.50 | 850.50 | 850.50 |
| `Map.addNat64` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 7,575.50 | 2,034.50 | 1,107.00 | 1,107.00 |
| `Map.addNat64` | add-insert | 100,000 | 14,112.34 | 10,148.47 | 8,919.41 | 2,524.25 | 1,289.25 | 1,289.25 |
| `Map.addNat64` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 3,052.16 | 1,395.50 | 677.25 | 677.25 |
| `Map.addNat64` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 4,031.53 | 1,816.75 | 913.50 | 913.50 |
| `Map.addNat64` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 4,876.94 | 2,230.50 | 1,143.00 | 1,143.00 |
| `Map.getNat64` | get-hit | 1,000 | 2,041.19 | 1,604.38 | 891.78 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 2,736.97 | 2,129.44 | 1,174.53 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 3,324.09 | 2,524.38 | 1,345.19 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 2,237.69 | 1,710.88 | 955.53 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 2,942.59 | 2,248.19 | 1,248.75 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 3,518.72 | 2,649.88 | 1,420.81 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 9,848.69 | 3,851.75 | 3,139.16 | 1,355.50 | 677.25 | 677.25 |
| `Map.replaceNat64` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 4,118.53 | 1,776.75 | 913.50 | 913.50 |
| `Map.replaceNat64` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 4,964.44 | 2,190.50 | 1,143.00 | 1,143.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 1,423.59 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 1,776.44 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 2,008.06 | 0.00 | 0.00 | 0.00 |

### Core baseline details

Explicit adapters are used where Core has no matching public API. Seek, rank, selection, and split differences include additional plugin algorithms and subtree metadata, not just plugin boundary overhead.

| Workload | Core baseline | Note |
| --- | --- | --- |
| alter-mixed | `get + callback + add/remove` | Core has no alter: call callback once after get, then add/remove; unchanged absence keeps the original root. |
| entriesFrom-seek16 | `entries + Iter.dropWhile` | Core has no seek: ordered iterator scans the prefix, then both consume 16 entries. |
| entriesInRange-seek16 | `entries + Iter.dropWhile + Iter.takeWhile` | Core has no bounded seek: scan to lower bound and stop at upper bound; both consume 16 entries. |
| find-first | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-last | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-middle | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-missing | `Iter.find(entries)` | Ordered scan adapter; threshold lies above every key. |
| fromArray-shuffled | `fromIter(array.values())` | Core has no fromArray; array iterator creation is included in its adapter. |
| getEntry-hit | `get + optional pair` | Core.get mapped to the requested key; equivalent for exact Nat64 ordering. |
| rank | `ordered entries count` | Core lacks subtree counts; scan ordered entries until the probe key. |
| replay-consume | `entries(retained root)` | Full snapshots are prepared before timing; both create an iterator and consume it completely. |
| replay-create | `entries(retained root)` | Full snapshots are prepared before timing; Core replays a retained root with entries. |
| select | `entries + index scan` | Core lacks rank selection; consume the ordered iterator to the requested index. |
| snapshot-create | `retain persistent map root` | Full-map snapshot only: Core root capture is already persistent; plugin snapshot additionally stores rank/range metadata. |
| splitLookup | `entries + add into two maps` | Core has no split: one ordered pass reconstructs left/right maps with public add; plugin shares untouched branches. |
| swap-hit | `swap` | Both return the old optional value; this is put-with-old-value semantics. |
| update-mixed | `get + callback + add/remove` | Same adapter as alter, returning the original optional value. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in the
[round 2 CSV](benchmarks/results/optimization-round-2/pure-map/functions/after.csv)
and the [prior full CSV](benchmarks/results/optimization-round/pure-map/functions/after.csv)
for rows not remeasured this round.

The [new before/after tables](benchmarks/results/optimization-round-2/pure-map/functions/costs.md),
[validation record](benchmarks/results/optimization-round-2/pure-map/functions/validation.json),
and [independent audit](benchmarks/results/optimization-round-2/pure-map/audit.md)
provide the current changes, including empty and small lookup checks. The
[prior full comparison](benchmarks/results/optimization-round/pure-map/functions/costs.md)
retains every original measurement, including losses.
The [updated point](benchmarks/results/optimization-round/pure-map/point/costs.md)
and [bulk tables](benchmarks/results/optimization-round/pure-map/bulk/costs.md)
also cover `remove`, retained histories, and set operations. Intersecting a
256-entry map with a small map remains a weak case: **57,509 instructions /
6,016 allocated bytes** for the Core adapter versus **80,690 / 12,184** for
the plugin. The [earlier report](benchmarks/results/pure-map/README.md) remains
available as historical evidence.

## Plugins

| Plugin | `mo:fast` module | Description |
| --- | --- | --- |
| [CandidX](plugins/candidx/) | `CandidX.encode(...)` → `#ok Blob` / `#err Text` | Canonical Candid encoding from typed Motoko values |
| [ICWire](plugins/icwire/) | `ICWire.encode(value)`, `ICWire.decode<T>(bytes)`, `ICWire.estimateSize(value)` | Raw positional binary payloads with compile-time schemas, bounded decoding and allocation-free admission sizing |
| [CBOR](plugins/cbor/) | `CBOR.encode(value)`, `CBOR.decode<T>(bytes)` | Deterministic CBOR encoding and typed decoding with `#ok`/`#err` results |
| [JSON](plugins/json/) | `JSON.encode(value)`, `JSON.decode<T>(text)` | Typed JSON encoding/decoding with `#ok`/`#err` results |
| [Mutable map](plugins/mutable-map/) | `Map.get`, `Map.add`, `Map.remove` | In-place ordered maps with generic keys/values, shared payloads, and managed GC writes |
| [Pure map](plugins/pure-map/) | `pure/Map`: `get`, `add`, `remove` | Persistent ordered maps with generic keys/values, Motoko callbacks, and native scalar comparisons |
| [Mutable set](plugins/mutable-set/) | `Set.contains`, `Set.add`, `Set.remove` | Core-compatible mutable Set API, with key-only B-tree nodes and native scalar comparisons |
| [Pure set](plugins/pure-set/) | `pure/Set`: `contains`, `add`, `remove` | Persistent key-only AVL trees with shared subtrees, rank/select, and split/join |
| [SHA-256](plugins/sha256/) | `SHA256.digest(bytes)` | One-shot SHA-256 with direct Blob access |
| [BLAKE3](plugins/blake3/) | `BLAKE3.digest`, `keyedHash`, `deriveKey` | BLAKE3 hashing, streaming snapshots, and seekable extended output |
| [SHA-512](plugins/sha512/) | `SHA512.digest`, `digest384`, `Digest` | SHA-512 and SHA-384 with bounded streaming state |
| [RIPEMD-160](plugins/ripemd160/) | `RIPEMD160.digest`, `Digest` | RIPEMD-160 and incremental hashing for Bitcoin HASH160 |
| [HMAC](plugins/hmac-sha2/) | `HMAC.sha256`, `sha512`, `prepareSha512` | HMAC-SHA256/SHA512, reusable keys, and streaming |
| [secp256k1](plugins/secp256k1/) | `Secp256k1.signPrehash`, `verifyPrehash`, `schnorrVerify` | Bitcoin curve operations, deterministic ECDSA, BIP340 Schnorr, and key tweaks |
| [P-256](plugins/p256/) | `P256.signPrehash`, `verifyPrehash`, `publicKey` | NIST P-256 keys, deterministic ECDSA, and signature encoding |
| [Ed25519](plugins/ed25519/) | `Ed25519.derivePublicKey`, `sign`, `verify` | Ed25519 signatures from 32-byte seeds, with strict public-key and signature validation |
| [RSA](plugins/rsa/) | `RSA.derivePublicKey`, `signPrehash`, `verifyPrehash` | RSA-3072 PSS with SHA-256, fixed exponent 65537, and an OpenSSL key import tool |
| [ML-DSA](plugins/ml-dsa/) | `MLDSA.publicKey`, `sign`, `signRandomized`, `verify` | ML-DSA-44 post-quantum signatures, including seed expansion and context support |
| [Base58](plugins/base58/) | `Base58.encode`, `decode`; `Base58Check` | Bitcoin Base58 and composed double-SHA256 checksums |
| [Bech32](plugins/bech32/) | `Bech32.encode`, `decode`; `Segwit` | Bech32/Bech32m, bit conversion, and validated witness addresses |
| [BLS12-381](plugins/bls12-381/) | `BLS12381.g1Mul`, `pairingCheck`, `verifyIC`, `verifyEthereum` | Group arithmetic, MSM, hash-to-curve, and distinct IC/Ethereum BLS profiles |
| [Queue](plugins/queue/) | `Queue.pushBack`, `Queue.popFront` | Core-compatible double-ended queue with lazy managed chunks |
| [History ring](plugins/history-ring/) | `HistoryRing.append`, `HistoryRing.get`, `HistoryRing.page` | Bounded history with direct sequence lookup and shared payloads |
| [Indexed priority queue](plugins/indexed-priority-queue/) | `IndexedPriorityQueue.push`, `reschedule`, `peekPriority` | Priority scheduling with cancellation and rescheduling handles |

The compiler support is proposed in
[Motoko PR #6443](https://github.com/caffeinelabs/motoko/pull/6443).
This repository is independent of the compiler checkout. It is not a submodule.

The cryptographic primitives compose in `mo:fast/Bitcoin/Hash`, `Bip32`,
`Address`, `Script`, and `Transaction`. These Motoko modules provide public
BIP32 derivation, legacy/SegWit/Taproot addresses, transaction serialization,
legacy/BIP143/BIP341 signature hashes, and local Taproot key-path signing. The [package guide](packages/fast/)
lists the plugins required by each module. Benchmarks compare the actual Mops
implementations and complete Bitcoin workflows, with independent expected
outputs. The [crypto API benchmark table](benchmark_crypto.md) covers every
public crypto function and Bitcoin helper, with native Motoko counterparts
where available. The [optimization report](benchmarks/crypto/round2/RESULTS.md)
records improvements, regressions, allocation and code-size tradeoffs against
the previous plugin implementations; [full evidence](benchmarks/crypto/)
includes the pinned inputs and reproduction commands.

## Build and use

Use a compiler checkout with the plugin API; the tested revision is recorded in
[`toolchains/motoko.json`](toolchains/motoko.json). Enter that checkout's Nix
development shell. With this repository at `../plugins`:

```sh
cd /path/to/motoko
nix develop
make -C rts
../plugins/scripts/build.sh --motoko "$PWD"
(cd ../plugins/packages/fast && mops install)
bin/moc --plugin ../plugins/dist/candidx \
        --plugin ../plugins/dist/sha256 \
        --plugin ../plugins/dist/json \
        --plugin ../plugins/dist/cbor \
        --plugin ../plugins/dist/pure-map \
        --plugin ../plugins/dist/mutable-map \
        --plugin ../plugins/dist/mutable-set \
        --plugin ../plugins/dist/pure-set \
        --plugin ../plugins/dist/queue \
        --plugin ../plugins/dist/history-ring \
        --plugin ../plugins/dist/indexed-priority-queue \
        --package fast ../plugins/packages/fast/src \
        --package core ../plugins/packages/fast/.mops/core@2.5.0/src \
        app.mo -o app.wasm
```

```motoko
import CandidX "mo:fast/CandidX";
import SHA256 "mo:fast/SHA256";
import JSON "mo:fast/JSON";
import CBOR "mo:fast/CBOR";
import Map "mo:fast/pure/Map";
import MutableMap "mo:fast/Map";
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";

switch (CandidX.encode({ value = 42 })) {
  case (#ok bytes) { let digest = SHA256.digest(bytes) };
  case (#err message) { /* handle the encoding error */ };
};
type User = { name : Text; age : Nat8 };
let user = JSON.decode<User>("{\"name\":\"Ada\",\"age\":37}");
let binary = CBOR.encode({ name = "Ada"; age = 37 : Nat8 });
let key : Nat64 = 42;
let original = Map.empty<Nat64, Text>();
let updated = Map.addNat64(original, key, "answer");
assert Map.getNat64(updated, key) == ?"answer";
let mutable = MutableMap.empty<Nat64, Text>();
MutableMap.addNat64(mutable, key, "answer");
assert MutableMap.getNat64(mutable, key) == ?"answer";
let members = Set.empty<Nat64>();
Set.addNat64(members, key);
assert Set.containsNat64(members, key);
let oldMembers = PureSet.empty<Nat64>();
let newMembers = PureSet.addNat64(oldMembers, key);
assert PureSet.isEmpty(oldMembers);
assert PureSet.containsNat64(newMembers, key);
```

The [`fast` Mops package](packages/fast/) provides these modules. To use it from
a local checkout, add `fast = "../plugins/packages/fast"` under `[dependencies]`
in your application's `mops.toml`, then run `mops install` and use `mops sources`
for the compiler package flags. It is not published to the registry yet. Load
only the native plugins used by your imported modules; Mops resolves source
imports, while `--plugin` loads the matching compiler extension.

Tripwire emits memory32 by default; `--wasm64` selects memory64. Plugin values,
kernel pointers and object layouts retain their 64-bit ABI on both targets.
The compiler lowers memory and table addressing after linking its Wasm64 RTS
and plugin kernels, so the same built plugin package supports either target.
Keep the existing Wasm64 Rust kernel build target; building those kernels as
Rust wasm32 would change their signatures and layouts. Memory32 reserves the
last 64-KiB page and allows at most 4 GiB minus that page of linear memory.
The [five-plugin target tests](tests/wasm32/) cover ICWire, Map, Queue,
HistoryRing and SHA256, including wire identity and confirmed garbage collection.

The build creates a matching dynamically linked native compiler and independent
packages in `dist/<name>/`, each containing `plugin.cmxs`. Kernel-based packages
also contain `runtime.wasm`; the collection packages emit managed Wasm directly.
To build selected plugins, append their names:

```sh
../plugins/scripts/build.sh --motoko "$PWD" sha256
```

Prebuilt packages load with `--plugin` without rebuilding the compiler. Native
compiler modules must match the compiler interfaces, OCaml toolchain, and host
platform; incompatible packages produce an unsupported-plugin error. Rebuild
packages when changing the compiler. The development SDK uses ABI 1; all plugin
functions use the same specialization mechanism and can return managed Motoko
values. Static Linux/musl and JavaScript compiler builds cannot load native
`.cmxs` files.

## Repository layout

```text
plugins/
  candidx/
    plugin.json       package and build metadata
    compiler/         registration, code generator, interpreter reference
    runtime/          Rust crate compiled to Wasm
    tests/            plugin-specific Motoko tests and fuzz adapter
  json/
    ...
  cbor/
    ...
  pure-map/
    compiler/         generated managed Wasm and interpreter reference
    tests/            differential, sharing, and GC checks
  mutable-map/
    compiler/         native B-tree operations and interpreter reference
    tests/            differential, aliasing, GC, and upgrade checks
  pure-set/
    compiler/         key-only AVL operations and interpreter reference
    tests/            persistence, nullable elements, and GC checks
  mutable-set/
    compiler/         key-only B-tree operations and interpreter reference
    tests/            structural updates, type rejection, and invariants
  queue/
    compiler/         managed chunk operations and interpreter reference
  history-ring/
    compiler/         sequence-indexed retention and interpreter reference
  indexed-priority-queue/
    compiler/         indexed heap operations and interpreter reference
  sha256/
    ...
packages/fast/        Mops package metadata, README, and license
  src/                codec, hash, Map, Set, Queue, HistoryRing, IndexedPriorityQueue modules
    pure/             persistent Map and Set libraries
  tests/              public import, rejection, and trap checks
    ash/              public API and GC canister tests on PocketIC
scripts/              shared build and test commands
tests/integration/    tests combining plugins and exercising GC
benchmarks/           PocketIC harness and recorded results
docs/                 architecture and authoring guide
toolchains/           compiler revision used by CI
dist/                 generated loadable packages (ignored)
_build/               generated intermediates (ignored)
```

Each plugin owns its implementation and tests. Shared tools discover plugin
manifests so adding another plugin does not require a new build script. See
[adding a plugin](docs/adding-a-plugin.md).

## Validation and performance

From the Motoko checkout's Nix shell:

```sh
../plugins/scripts/test.sh --motoko "$PWD"
```

The suite exercises source and IR interpretation, compiled Wasm, diagnostics,
package loading, native kernels, and GC behavior. The
[benchmark guide](benchmarks/README.md) covers PocketIC instruction counts and
the CandidX repository's conformance and fuzz tests.

The [public module suite](packages/fast/tests/ash/) contains **308 Ash checks** across
twenty plugins and shared Core/Fast API consumers: reference models,
independent codec/hash vectors, malformed inputs, boundary cases, structural sharing,
composition, and incremental GC. Run from this repository with an Ash toolchain
using the matching compiler:

```sh
scripts/test-ash.sh
# For an Ash source checkout with canister mocArgs support:
scripts/test-ash.sh --ash-source /path/to/ash
```

These correctness tests are separate from the performance measurements above.
Per-module API inventories and execution requirements are in the
[test guide](packages/fast/tests/ash/README.md).

The [managed-mutation SDK audit](docs/audits/managed-mutation-sdk/README.md)
records independent tests across four execution engines and mutation during
incremental marking, evacuation, and pointer updating. Container and assignment
type checks happen during compilation; runtime bounds and GC barriers remain.

The [JSON optimization report](benchmarks/results/json-optimized/README.md)
records a 22.8% instruction reduction and 90.6% less allocation when decoding
1,024 records. Its [independent audit](plugins/json/tests/audit/README.md)
includes 9,263 syntax cases, 765 scalar/binary/Unicode cases, and regressions
for error paths, excessive scratch allocation, and GC.

Earlier [CandidX conformance and fuzz results](benchmarks/results/typed-results/README.md)
and [historical benchmarks](benchmarks/results/README.md) retain their original
artifact hashes and ABI labels.

## Design and licensing

The [design document](docs/design.md) describes compiler specialization, memory
borrowing, compatibility, and the relationship to Wasm components. Plugins are
trusted compiler extensions; the shared-memory interface is not a sandbox.
The [persistent-map research](docs/pure-map-research.md) compares structurally
shared trees and records the SDK options considered. The implementation uses
integrated synchronous callbacks and optional native scalar ordering. Point
updates copy changed paths and share untouched branches and payloads.

Existing licenses are preserved. CandidX carries MIT licenses in its compiler
and runtime directories. Other extracted material uses the Motoko license in
[LICENSE](LICENSE). See [NOTICE](NOTICE) for extraction provenance.
