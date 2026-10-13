# Latest collections in Takt, Reactor and Rechain

The latest Queue and HistoryRing improve existing integrations. Replacing an
already-native Map with IndexedPriorityQueue is a separate decision: the real
operation mix, allocation and ordering requirements matter more than a single
heap microbenchmark. All comparisons use compiler `92b1bde`, its original RTS,
and ABI 1; no compiler or plugin implementation changes are part of this recheck.

**Adopted:** Takt reuses its outermost inline-admission Queue; Rechain uses an
internal insertion FIFO in its cache. Published source matches the tested
candidates. Takt and Reactor keep their current Map deadline indexes.

## Updating the bundle in existing integrations

Trace compares the previously delivered and latest complete bundles. Reactor
changes only the Queue native plugin and matching public module; its other
plugins stay current on both sides. Current application source is fixed in each
comparison. These are not Map-versus-IPQ results. All counters cover the complete
stated operation or workload.

| Actual library workload | Previous → latest instructions | Change | Allocated bytes, previous → latest |
| --- | ---: | ---: | ---: |
| Takt Trace, overwrite 128 events at retention 512 | 331,262 → 250,110 | −24.50% | 12,288 → 12,288 |
| Takt Trace, first page of 128 events at retention 512 | 106,567 → 99,589 | −6.55% | 14,648 → 14,648 |
| Reactor healthy transport, 10,000 requests and replies | 1,516,217,974 → 1,501,906,537 | −0.94% | 37,900,200 → 37,888,072 |

Three trials per variant agree exactly. Trace's one-event pages add 16
instructions; its allocation is unchanged and heap was not measured. Reactor
still drains in 13 ticks. Its largest sampled single-canister heap rises by
2,872 bytes, with unchanged 406-page Wasm high-water and no reclamation. This is
an instruction saving, not a throughput or retained-memory improvement.

Evidence: [Takt Trace](https://github.com/Neutrinomic/takt/blob/main/research/ApplicationPluginRecheck/Trace.md)
and [Reactor transport](https://github.com/Neutrinomic/reactor/blob/main/research/performance/collections/optimized-integration/README.md).

## Choosing structures with the latest bundle fixed

Both sides of these experiments use the latest plugins. Their percentages are
not additional bundle-update gains and must not be added to the preceding table.

| Current-library question | Measured finding | Decision / status |
| --- | --- | --- |
| Takt wake index: fast Map → IPQ | At 2,048 wakes, 1,024 minimum reads cost 1,473,790 → 432,382 instructions (−70.7%, zero allocation); removing 64 due wakes costs 630,337 → 730,062 (+15.8%), allocating 0 → 2,560 B. | Keep Map: separate operation wins do not establish a whole-Engine benefit. |
| Takt admission: reuse the outermost inline Queue | 32 local admissions cost 7,366,884 → 7,249,064 instructions (−1.60%) and 491,248 → 467,336 allocated B (−4.87%). | Adopted; combined application result below. |
| Reactor Scheduler: Map → Entry-valued IPQ | At 8 workers, rescheduling 4 earlier costs 80,732 → 72,099 instructions (−10.69%), allocating 3,240 → 3,432 B. Due drain saves 0.30%; unchanged refreshes cost 0.18% more. | Keep Map: modest small-index benefit, higher allocation; due drain at 10,000 workers costs 2.72% more. |
| Rechain cache: global insertion-order Map → internal FIFO | At 100,000 records, 1,000 oldest-evicting inserts cost 44,715,210 → 34,402,815 instructions (−23.06%) and 244,672 → 243,360 allocated B. | Plain FIFO adopted; combined application result below. |

Takt's wake keys retain exact `{at : Int; ticket : Nat}` order. IPQ cancellation
and minimum reads improve, but insertion allocates more and due removal can be
slower. The probe excludes Engine dispatch and reconstruction; it does not
measure their operation frequency. Inline Queue reuse retains a header and one
empty chunk per used engine: **560 B of direct storage derived from the compiler
layout**, not measured live heap. Its first-admission counters exclude the
152-byte header moved to engine construction. Nested admissions use separate
queues and every retained payload slot is cleared.

Rechain's FIFO uses managed links and the existing lookup/per-chain fast Maps;
this is an application algorithm change, not a new native plugin gain. At 100,000
records its mutation batches save 16.65–25.32% instructions, but prefix deletion
allocates 3,816 → 16,200 B and per-chain churn 217,616 → 223,864 B. The 10,000-record
read batch costs 2.08% more; small-cache churn also allocates more. IPQ is a poor
fit for this index: at 100,000 records eviction costs 192.40% more instructions
and replacement 44.87% more than Map. Equal-pressure released heap samples differ
by only 40 B for FIFO versus Map; this is comparable reclamation evidence, not a
memory-footprint win.

Evidence: [wake index](https://github.com/Neutrinomic/takt/blob/main/research/ApplicationPluginRecheck/WakeIndex.md),
[inline admission](https://github.com/Neutrinomic/takt/blob/main/research/ApplicationPluginRecheck/InlineQueue.md),
[Takt overview](https://github.com/Neutrinomic/takt/blob/main/research/ApplicationPluginRecheck/README.md),
[actual Reactor Scheduler](https://github.com/Neutrinomic/reactor/blob/main/research/performance/collections/optimized-scheduler/README.md),
and [Rechain cache](https://github.com/Neutrinomic/rechain/blob/main/test/benchmarks/cache-collections-round2/README.md).
Reactor’s separate healthy-transport IPQ screen saves only 0.072% instructions
and arms no future deadlines; it does not exercise active deadline repair. In
the actual Scheduler payload-release test, all variants return to their matched
empty heap sample after releasing workers and leases; a retained-payload control
confirms release of the payload set. This establishes no general live-heap saving.
Allocation is cumulative operation allocation, including garbage; sampled heap
and linear-memory high-water are separate counters, not retained live bytes.
Full reports preserve scope, correctness checks, raw samples and frozen hashes.

## Combined application check

The two adopted library changes together reduce fourcans instructions from
**153,698,078,774 to 153,475,711,072 (−0.145%)** and allocation from
**4,203,336,424 to 4,187,964,552 B (−0.366%)**. Completion remains **57 rounds**
with unchanged full-drain throughput. This is one candidate observation against
an inherited control whose rebuilt outputs are byte-identical to the previous
measurement, using fixed settings and the same latest plugins. All application
correctness checks pass. The two contributions were not measured separately.

Memory is mixed: replica dirty-page accounting increases **144,052,224 B
(+1.196%)**, and aggregate Wasm linear memory grows **64 KiB**. Lower allocation
does not imply less dirty-page work or lower live heap; the increase cannot be
assigned to either library change alone. The
[full application report](https://github.com/Neutrinomic/takt/blob/main/examples/reactor/fourcans/test/results/tuning/library-integration-recheck/README.md)
records exact source, harness and artifact hashes, correctness counts, sampled
heap and GC counters. These gains must not be added to the earlier plugin-update
percentages.

## If IPQ is not the best fit

Keep the current Map where it wins. The Rechain experiment supports testing an
addressable FIFO when only insertion order and arbitrary unlink are needed.
It is implemented in ordinary Motoko; a future public FIFO plugin would need a
separate benchmark justification. Native Map minimum removal could avoid a
second tree traversal without handles. A small cached-min vector could suit
Reactor's few-driver deadline index; exact timestamp buckets need evidence that
deadlines share timestamps. Minimum removal, vectors and buckets remain
unmeasured proposals, not new SDK requirements. Preserve arbitrary integer
deadlines, tie ordering, cancellation, GC reference release and reconstruction.

See the [operation-driven alternatives](alternatives.md) and
[independent integration audit](audit.md). Historical Core-versus-plugin and
initial fourcans gains remain in the [repository overview](../../README.md).
