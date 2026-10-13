# HistoryRing optimization passes

Three accepted passes preserve the public API, chunk layout, arbitrary `Nat`
sequences, and conservative `?Any` writes through the SDK's GC barriers.
The compiler and SDK are unchanged.

These exploratory measurements use the same benchmark Motoko source, compiler
`92b1bdecb`, release RTS, Core 2.6.2, and PocketIC 10.0.0. Each case has one trial
per implementation in a fresh canister. Setup and explicit GC increments are
outside the measured operation; instruction counts include the benchmark loop
and dispatch, but exclude reply encoding and end-of-message GC. Allocations are
bytes allocated during that operation, not retained memory.

| Pass | Accepted change and measured batch | Instructions before → after | Reduction | Allocated bytes before → after |
|---|---|---:|---:|---:|
| 1 | Cache page directory, width, span, and starting position; 100 pages of 32 entries, capacity 1,000 | 1,999,354 → 1,128,454 | 43.6% | 71,200 → 71,200 |
| 2 | Compact subtraction fast path; 100 sequence lookups, capacity 1,000 | 300,824 → 88,824 | 70.5% | 21,600 → 0 |
| 2 | Same subtraction change; 100 pages of 32 entries, capacity 1,000 | 1,128,454 → 704,454 | 37.6% | 71,200 → 28,000 |
| 3 | Reuse resolved chunks/slots; append 10,000 entries into an empty ring | 15,327,823 → 12,284,478 | 19.9% | 87,664 → 87,664 |
| 3 | Same slot reuse; overwrite 10,000 entries, capacity 10,000 | 22,920,291 → 16,840,291 | 26.5% | 0 → 0 |
| 3 | Bulk drop with local cursor and one metadata update; discard 5,000 of 10,000 entries | 4,303,762 → 634,305 | 85.3% | 0 → 0 |

Each row compares the immediately preceding pass. Raw measurements, hashes, and
source archives are under [baseline](results/baseline/results.json),
[pass1](results/pass1/results.json), [pass2](results/pass2/results.json), and
[pass3](results/pass3/results.json).

Pass 1 leaves checked array access and output allocation intact. Pass 2 uses
machine subtraction only when both operands are compact `Nat` values; each
caller establishes that the result is nonnegative. Larger values retain the
existing arbitrary-precision path, with additional tag checks. Pass 3 keeps the
wrapped-tail release condition: crossing a chunk boundary alone does not prove
that its chunk is empty.

The measured tradeoff is a zero-element drop on a nonempty capacity-one ring:
588 → 873 instructions, an extra 285 instructions from cached setup and metadata
writes. Allocation remains zero. Small and empty operations can still cost more
than Core Queue. The benchmark Wasm shrank from 283,111 to 282,085 bytes overall;
pass 2 temporarily added 765 bytes before pass 3 removed duplicated work.

The exploratory `get_tail` case implements generic sequence lookup by a forward
scan in Core Queue. It is not a comparison against `Queue.peekBack`, which is
already O(1). At capacity 100,000, the original `Nat` checksum also introduces
bigint work in both implementations; its allocation is not all container
allocation. The corrected `final-baseline`/`final` comparison uses a wrapping
`Nat32` checksum, middle sequence lookup, and an additional wrapped-page case.
Those final three-trial results are complete and published in [README.md](README.md);
headline comparisons use them, not the exploratory values.

The implementation owner passed the baseline tests. Native model and generic
tests passed again after passes 2 and 3, including sequence boundaries around
2^30, 2^60, 2^61, 2^64, and 2^140. The independent final source audit found no remaining defect. Final benchmark
validation passed all 42 paired cases in three trials and the 64-batch retention probe. The exploratory heap readings include uncollected
partition garbage; they do not establish exact live retention. Final retention
checks also inspect retained chunk, slot, and payload-byte counts.
