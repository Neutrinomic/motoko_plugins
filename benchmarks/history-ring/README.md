# HistoryRing: instruction, allocation, and retention measurements

The final plugin reduces bounded-history append/overwrite instructions by about
10% versus Core Queue append-and-trim, while avoiding per-node allocation.
Indexed sequence lookup and paging also avoid scanning the retained prefix;
those larger gains come from the data structure as well as native code.

The table shows medians of three fresh-canister PocketIC trials. Counts are
operations per measured call; a page returns up to 32 entries. Allocation is
new bytes allocated by the measured loop, **not retained memory**. Inputs and
construction are outside the measurement. Full results, including capacity
0/1/64/65 and wrapped pages, are in [operations.csv](results/operations.csv).

| Capacity | Operation | Count | Core instructions | Plugin instructions | Core / plugin | Core / plugin allocation |
|---:|---|---:|---:|---:|---:|---:|
| 1,000 | append | 1,000 | 1,355,240 | 1,220,398 | 1.11× | 96,000 / 8,944 B |
| 1,000 | overwrite | 1,024 | 1,901,859 | 1,713,443 | 1.11× | 98,304 / 0 B |
| 1,000 | get_middle | 100 | 13,290,984 | 87,936 | 151.14× | 9,600 / 0 B |
| 1,000 | page_tail_32 | 100 | 26,714,002 | 669,254 | 39.92× | 41,600 / 28,000 B |
| 1,000 | drop_half | 500 | 285,553 | 64,206 | 4.45× | 0 / 0 B |
| 10,000 | append | 10,000 | 13,550,240 | 12,174,478 | 1.11× | 960,000 / 87,664 B |
| 10,000 | overwrite | 10,000 | 18,570,291 | 16,730,291 | 1.11× | 960,000 / 0 B |
| 10,000 | get_middle | 10 | 13,209,804 | 9,546 | 1383.81× | 960 / 0 B |
| 10,000 | page_tail_32 | 10 | 26,431,942 | 67,514 | 391.50× | 4,160 / 2,800 B |
| 10,000 | drop_half | 5,000 | 2,850,553 | 634,330 | 4.49× | 0 / 0 B |
| 100,000 | append | 100,000 | 135,500,240 | 121,629,718 | 1.11× | 9,600,000 / 866,936 B |
| 100,000 | overwrite | 100,000 | 185,700,291 | 167,300,291 | 1.11× | 9,600,000 / 0 B |
| 100,000 | get_middle | 10 | 132,009,804 | 9,546 | 13828.81× | 960 / 0 B |
| 100,000 | page_tail_32 | 10 | 264,031,942 | 67,514 | 3910.77× | 4,160 / 2,800 B |
| 100,000 | drop_half | 50,000 | 28,500,553 | 6,335,262 | 4.50× | 0 / 0 B |

Core 2.6.2 uses a linked Queue here. Middle lookup traverses its iterator, and
paging follows the current Takt Trace pattern of scanning forward to a sequence.
Core `peekBack` is already O(1); a reverse iterator can also improve a special
last-page-only implementation. These results do not imply every equivalent
Motoko implementation must scan. Both paths perform append-and-trim with the
same capacities, sequence results, payloads, and output checksums.

Small operations are not universal wins: the first append at capacity one costs
2,513 plugin instructions versus 1,595 for Core. Empty reads/pages and zero-item
drops are also slower. The zero-capacity Core reference still performs append
then trim; callers can special-case disabled retention. No such rows are used as
headline evidence. The plugin retains arbitrary `Nat` sequences; the timing
matrix uses compact sequences, with large-sequence correctness covered by tests.

## Retention

A separate multi-message probe allocates fresh 1 KiB Blob payloads in 64 batches
of 1,024 appends at capacity 1,024, validates every byte of the retained values,
and periodically advances GC. At every nonempty checkpoint the ring held exactly
16 chunks, 1,024 occupied payload slots, and 1,048,576 payload bytes, despite
65,536 total appends. Clearing left zero directory entries, chunks, slots, or
payload bytes reachable from the ring. All retained bytes and checksums matched
Core. The 16 chunks contain 1,024 allocated physical slots for this capacity.

| After 64 batches | Core Queue | HistoryRing |
|---|---:|---:|
| Retained entries | 1,024 | 1,024 |
| Total allocation since canister install | 619,909,560 B | 613,644,552 B |
| Reclaimed by GC | 582,878,592 B | 582,543,544 B |
| Current managed heap at checkpoint | 37,030,968 B | 31,101,008 B |
| Wasm memory high-water | 256 MiB | 256 MiB |
| Historical post-GC heap high-water (`maxLive`) | 63,480,352 B | 66,283,824 B |

Payload construction and benchmark messages dominate this probe's total
allocation; it is a retention check, not a container-only allocation benchmark.
The identical Wasm high-water and higher plugin `maxLive` show why these counters
must not be presented as a universal memory-footprint win. Current heap still
contained partition garbage after clear: 37,171,160 B for Core and 31,241,200 B
for the plugin. Structural inspection establishes that the ring retained no
payload references then. Raw `storage` fields inspect the ring only; their zero
values during the Core run describe the unused ring, not Core's memory usage.

`heap` is current managed heap, including garbage in partitions not yet
reclaimed. Wasm memory and `maxLive` are historical high-water counters;
`maxLive` is not an exact count of reachable payload bytes. Partial drops release
empty chunks and payload references but keep the directory's high-water length;
clearing or removing the final item releases that directory too.

## Reproduction and evidence

- [Final results](results/final/results.json) and [final build provenance](results/final/build.json).
- [Original implementation under the same final harness](results/final-baseline/results.json).
- [Three measured optimization passes](OPTIMIZATION.md), including their regressions and decisions.

Compiler `92b1bdecb`, original release RTS, ABI 1, Core 2.6.2, and PocketIC 10.0.0
are pinned by hashes in each report. Build inputs are hashed before compilation,
checked afterward, and checked against copied source/plugin archives. Original
and final sources use one private fixed plugin build path. Shared plugin outputs
are untouched during these comparisons. The runner verifies its own hash and
the archived Wasm before installing it.

`main.mo` and the compiler/RTS paths stay fixed across the final original/final
comparison. Wrapping Nat32 checksums avoid introducing bigint allocation when
accumulating 100,000 results. Dispatch, loop, and counter overhead is included;
reply serialization and end-of-message GC are excluded. No measured operation
reclaimed memory synchronously. Three trials alternate implementation order.

To reproduce the current final plugin in a new immutable stage:

```sh
python3 benchmarks/history-ring/build.py --stage my-run
bun benchmarks/history-ring/run.mjs --stage my-run --trials 3 --churn yes
python3 benchmarks/history-ring/summarize.py
```

The optional `--plugin-root` build argument selects an isolated plugin repository
for before/after experiments. Stages cannot overwrite existing build archives.
The summarizer rebuilds the published `final` versus `final-baseline` CSV.
