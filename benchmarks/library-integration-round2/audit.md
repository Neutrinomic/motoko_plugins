# Current-library integration: independent design and method audit

Status: approved, including final source publication. The reviewer changed only
this report; no production edits, benchmark builds or PocketIC reruns were
performed by the reviewer.

## Comparison contract

Structural candidates must compare with the **current library implementations
using the latest plugins on both sides**: Queue `c6e89270…`, HistoryRing
`f71c15ec…`, IndexedPriorityQueue `87627cd0…`, the current Map, compiler
`92b1bde…`, and original RTS. A previous-bundle versus latest-bundle comparison
is useful separately, but cannot serve as the baseline for a new Map-to-IPQ
integration decision.

Use immutable private input trees and the same compilation paths. Pin source,
native artifacts, compiler/RTS, emitted Wasm, build script and actual executed
runner. Fail if inputs change or an existing result would be overwritten.
Preserve full work/output equivalence, not only additive checksums. Count
instruction/allocation work separately from setup, output validation and
message-end GC. Sampled RTS heap and Wasm high-water are not exact live memory.

## Takt

The Trace recheck uses the same current Takt source with old and latest plugin
bundles. It is explicitly plugin-update evidence, not an IPQ structural
comparison. The independent review found and closed two harness gaps: exact page
order is now checked outside timing, and executed runner/build-script identities
and overwrite protection are recorded. All 27 cases / 162 calls pass, with
21 improvements and six one-entry-page regressions of 16 instructions.
Frozen current source, selected installed plugin identities, Wasm, table
arithmetic and scope caveats verify. Constructor/GC/heap/throughput claims are
not inferred from this probe. This recheck is approved.

The separate wake-index probe is approved. All 81 frozen inputs, current Map/IPQ
bundle and Engine sources, Wasm/flags, executed runner, 72 samples and two semantic
guards verify. The timed IPQ path includes authoritative key, handle and holder
allocation. Exact popped/remaining entries and large keys are checked. The report
discloses its synthetic 11-bucket deadlines, increasing tickets, 20% expiration
and low-ID cancellations. Keeping Map is justified: this probe demonstrates no
whole-Engine benefit and does not measure reconstruction or operation frequency.

A private Engine admission-queue candidate reuses the outermost queue while
keeping separate queues for nested admissions and popping all deferred work
during flush. Focused source/oracle reviewers own its detailed reentrancy checks.
The performance comparison must distinguish moving the 152-byte queue header to
Engine construction from warm per-admission savings. The owner documents an
estimated 560 bytes retained per used Engine (152-byte header plus one 408-byte
empty chunk), excluding closure capture; this is not a measured live-heap bound
or a claim of lower idle footprint. The combined application adoption gate is reported below and has passed.

## Rechain

Before publication, production `Transactions.mo` and the captured baseline both
hashed to `4b73c4cd…`. The published FIFO is `d98868f1…`, as verified below.
The candidate changes only the global eviction index: private doubly linked
FIFO nodes replace its sequence-to-key Map. Data lookup and per-chain ordered
ID maps remain.

Required semantics are insertion FIFO globally, lowest ID per chain, and no
refresh on reads. A valid replacement removes the old entry and becomes newest;
zero-record-limit or oversized writes return before removing an existing entry.
Sparse/out-of-order IDs, arbitrary `Nat` IDs, and simultaneous byte/record bounds
must preserve these behaviors.

Early source review found no confirmed link/lifetime defect. Unlink rewires both
neighbors and endpoints, clears both links of the removed node, and removes the
data-map entry. Nodes do not escape through the public API, so an additional
nullable payload field is unnecessary: no owner retains a detached node after
the operation. Active cycles use normal managed Motoko references.

The draft build/runner required consistent new paths and freezing candidate
source/probe/runner bytes before compilation rather than hashing only afterward.
These were sent to the owner before final measurements. Fixed shared payloads
measure structural allocation only. Variable payload identity/charge checks and
separate fresh-payload retention evidence are needed before claiming release or
memory benefit. Exact membership, eviction order, byte accounting and per-chain
counts must agree with an independent model outside timing.

The owner has corrected paths, frozen authored bytes before compile with an
after-build hash guard, asserted baseline equality, added fresh actors per size
and trial, and added weighted-payload/one-victim eviction traces. The separate
forced-GC probe retains empty/filled/cleared snapshots. A minimum reclaimed-byte
threshold by itself cannot identify which objects were freed: construction
garbage may contribute. Match empty state or use retained-payload controls before
describing exact payload reclamation; do not infer live bytes from counters.

The completed five-way matrix passes independent numerical/input checks: 315
samples cover Map, IPQ, Map.take, FIFO and FIFO-take at 1,000/10,000/100,000
entries, seven phases and three exact repetitions. All 177 frozen inputs and
18 authored/Wasm hashes match, including production-baseline equality checked
before publication. Fifty
policy traces contain 355 individually checked operations. Plain FIFO saves
18.7–19.8% on fill and 23.1–26.5% on global eviction. Negative cases matter: its
10,000-entry read batch costs 2.08% more, and some deletion phases allocate more;
IPQ at 100,000 entries costs 192.4% more for eviction and 44.9% more for replacement.
Map.take reduces several deletion costs but adds fill overhead and allocation.
These operation results supported the private application candidate; the final
adoption result is recorded below.

The supplemental retention comparison uses equal rejected oversized Candid input
to create collection pressure without altering cache membership. Retained and
cleared actors show actual reclaimed-counter progress and a sampled-heap
difference. This control keeps the entire cache, including payloads and indexes;
its difference is not an exact payload-byte measurement. Earlier empty-actor GC
ticks alone did not force enough collection, and no unsupported reclamation
threshold is used in the accepted report. Final evidence retains the executed scripts and post-run source/runner/Wasm hash
verification. All 30 published table rows, percentages, small-case tradeoffs and
durable/raw report identities were verified. The benchmark report is approved. Focused integration tests and the combined
application screen subsequently passed their separate adoption gates below.

## Reactor

The normal Scheduler deadline index contains library drivers, not every
workflow. Actual small-driver and unchanged-deadline cases therefore matter.
Larger synthetic driver sets are scaling evidence. Preserve composite
`{at; driver}` order, arbitrary reschedule/cancel, owner-false cleanup, ready
queue generation checks and timer behavior.

The scheduler's `updateAll` can enqueue overdue ready drivers in ID order before
the deadline-index scan. The oracle must preserve actual baseline behavior;
globally sorting all overdue execution by deadline is not the current API.

An additional private candidate stores the existing Scheduler Entry as the IPQ
value, avoiding a second entries-map lookup on due pop. Early lifetime review
found this sound: insertions require membership; remove deletes the heap handle
and clears `entry.deadline` before deleting the entries-map item; due pop detaches
the handle and clears the field before calling update, which rechecks membership.
The active Entry/handle/queue cycle uses managed references and adds no extra
live driver beyond the entries Map. Retained Lease closures already capture
Scheduler helpers in the baseline, so whole-scheduler reclamation must not be
expected while retaining leases. Actual reclamation probes correctly discard
all lease and state references; cancellation tests may retain a lease to check
that it cannot revive removed work.

The final healthy-transport screen is approved: all nine runs have identical
work and no armed deadlines. The small IPQ differences are overhead/equivalence
evidence, not proof of faster heap repair, rescheduling or direct-Entry due-pop
behavior. The separate six-run Queue update comparison changes only the Queue
native artifact and matching module, with current Reactor source and all other
inputs fixed. Its instruction reduction is 0.94389%, allocation falls 12,128 B,
and sampled peak heap increases 2,872 B; ticks and Wasm high-water are unchanged.
All raw counters, repeated work, frozen input/runner/Wasm identities and table
calculations were independently verified. This is plugin-update evidence, not
a structural IPQ gain.

The Scheduler harness initially hashed the executing runner only at finish and
did not pin its copied scripts. The owner corrected this before final evidence:
launch-time hash must match the archive, scripts are pinned in the build manifest,
finish-time hashes must remain unchanged, and existing outputs are refused.
Earlier incomplete runs remain separate. Exact maintenance-phase scheduler state
and no premature execution are now checked in addition to final drain order.

The final actual-Scheduler report is approved. All 140 frozen input hashes,
current production baseline equality, same-path compilation with only Scheduler
source changed, harness/Wasm identities, 36 timed rows with exact three-trial
counters, nine late-wake traces and 18 retention cases verify. Table arithmetic
and operation counts agree with raw evidence. For eight workers, Entry-valued
IPQ saves 9.76%/10.69% on later/earlier rescheduling, adds 0.18% to unchanged calls,
and saves 0.30% on timer drain while several operations allocate more. At 10,000
workers, drain costs 2.72% more. Keeping the existing Map is well supported.

Released-worker heap samples return exactly to their matched empty baselines in
all three variants; the retained-blob controls are 4,229,088 B higher. The report
correctly separates occupied heap, cumulative allocation/reclamation and Wasm
high-water. This matched control supports payload-release evidence without
claiming exact live-byte counts. All leases and stable state references are
dropped before this measurement; saved removed-lease tests serve semantics only.

## Final gate

Only adopt a measured candidate that preserves semantics and has a useful
workload-level benefit. Keep Map if IPQ loses; global FIFO, native Map minimum
removal and small-index specialization are separate options, not reasons to
weaken ordering or accumulate stale references. See [alternatives](alternatives.md)
for operation-driven proposals. Individual Trace, wake-index, Reactor
transport/Scheduler, Rechain cache and combined application reports have passed
independent method, numerical and provenance review. The tested inline-queue and
FIFO changes were adopted; both scheduler deadline indexes retain Map.

The consolidated integration README is approved for the completed measurements.
It explicitly separates full-bundle Trace updates, Queue-only Reactor updates,
and latest-bundle structural comparisons. Table values, negative cases and
allocation/heap caveats match their approved source reports. The combined
application result and exact publication identities are recorded below.

## Combined application adoption gate

The combined inline-queue/FIFO application screen passes independent review. Both
212-source/29-toolchain frozen inputs and complete source archives verify; only
Takt `Engine.mo` (`83a4ae1…`) and Rechain `Transactions.mo` (`d98868f1…`) change.
Compiler commands, original RTS, plugin artifacts and 183 harness input hashes
match. The inherited baseline is valid because recompiling the current baseline
reproduced every previously measured output byte-for-byte. It is explicitly an
inherited observation, not a newly repeated control.

The same work drains in 57 rounds with empty queues, 18,000 roots, 1,200 children,
180,000 endpoint messages, 27,600 blocks, 594,000 graph visits and zero errors.
Instructions fall 222,367,702 (0.14468%) and allocation falls 15,371,872 bytes
(0.36571%). Peak sampled single-canister heap falls 666,864 bytes (0.33197%), but
replica dirty-page accounting rises 144,052,224 bytes (1.19621%) and final aggregate
Wasm capacity rises one 65,536-byte page. The report prominently preserves these
negative results; it makes no throughput or live-memory improvement claim.

Replica heap delta accumulates dirty Wasm/stable pages across successful message
executions, including pages dirtied again in later messages. It is neither
allocation nor retained heap. The source of the increased writes cannot be
attributed to either library edit from this combined experiment. These are one
candidate observation and an inherited matching control, not statistical
estimates or separated per-change application effects.

An additional independent metric review verified every dirty-page analysis
calculation and its pinned replica source definitions. The first ten rounds have
identical captured business progress but 13,082,624 extra dirty bytes before the
first sampled reclamation/outstanding copies; this does not exclude unobserved
collector work. Exhausted partition iterations rise from five to seven while
whole runnable-limited rounds fall from five to three. Over 99.96% of dirty bytes
occur in partitions assigned several canisters, so per-canister or per-library
causal attribution is unavailable. The report states these limits accurately.

The Rechain focused gate also passes: all 159 frozen files and three log hashes
verify the measured FIFO source, 31 tests across storage/store-fuzz/multichain pass,
and all 205 Muck obligations are satisfied. Takt's separately owned inline tests
and reentrancy/upgrade review were approved before this screen. After publication,
all 24 Takt source hashes matched the tested candidate, and the recorded convention
log/full-report hashes verified 1,121 satisfied obligations with zero violations
or inconclusive results. The two small
library changes are reasonable to adopt given the local operation gains and the
modest application CPU/allocation gain, with unchanged completion time and the
extra dirty-page work disclosed. After root authorized publication, direct hashes
of production Takt `src/Engine.mo` and Rechain `src/storage/Transactions.mo`
matched the exact tested candidate bytes, respectively
`83a4ae1bdc02a511f6fdf142639c28984f1b9ee0b560bc5f185bfa7b83036265` and
`d98868f1b3d57b3a59817a7ff5fd228134649e3d5ff298fa8dfcabd2466beadf`.
No compiler, SDK or plugin source change was needed for this application round.
