# HistoryRing additional optimization round

This round starts from the **delivered current plugin**, generator SHA-256
`26762844620d56539dc4f40ac589b6724cbf47d16c19408c8801ca01b809c311`.
It does not reuse the original pre-optimization implementation from round one.
Candidates are cumulative and use one private plugin path. Exploratory builds
left shared plugin outputs unchanged. The accepted source was subsequently built
and published to the shared plugin output; its separate native artifact emits
byte-identical benchmark Wasm, documented in
[publication equivalence](results/published-equivalence/equivalence.json).
The compiler, SDK, public module, and original round-one reports remain unchanged.

The four exploratory candidates used the same actor and runner. Each of the
first three candidates and the baseline completed 72 paired Core/plugin cases
(capacities 0, 1, 65, 1,000; 18 operations; one trial). The fourth measured its
32 affected lookup/drop/pop cases. Archive hashes, result checksums, sequence
bounds, counts, and unchanged Core instruction/allocation results were checked
independently. Final matched trials add a stronger retained-value/slot oracle.

| Candidate | Change | Measured result against preceding candidate | Decision |
|---|---|---|---|
| `fused-targeted` | Fuse full-ring overwrite into one operation | At capacity 1,000, append 1,000: 1,220,398 → 1,146,398 instructions; overwrite 1,024: 1,713,443 → 1,150,243. Allocation unchanged. | Retain. Capacity-zero appends add one instruction each. |
| `cursor-targeted` | Walk page chunks with a cached cursor | At capacity 1,000, ten 32-entry pages: 67,514 → 50,314 instructions; ten 1,000-entry pages: 1,790,508 → 1,240,078. Allocation unchanged. | Retain. Nonempty one-entry pages add 16–23 instructions each. |
| `drop-targeted` | Clear boundary fragments and detach fully removed chunks | At capacity 1,000, dropping half: 64,206 → 4,202 instructions; wrapped half: 64,250 → 2,246. No allocation. Full drops remain constant cost. | Retain. Final exact retained-order/slot checks and independent model tests passed. |
| `smallops-targeted` | Use end-relative lookup, short-circuit empty/zero drops, remove unused generator code | At capacity 1,000, ten lookups: 9,546 → 8,806 instructions. Nonempty zero-drop: 900 → 537. Empty drop: 1,078 → 521, removing its 24-byte allocation. | Retain. Nonzero drops add 19 instructions; full-drop cost rises 1.76%. |

One-item page and full-drop regressions are explicit tradeoffs, not hidden by an
aggregate score. Pop cost is unchanged, and the plugin remains slower
than Core Queue for the measured full-drain pop workload. Empty reads and tiny
first allocations also deserve separate interpretation from steady-state work.

The exact comparison CSVs are in `results/{fused,cursor,drop,smallops}-comparison.csv`.
Each stage includes source snapshots, the compiled plugin, benchmark Wasm, build
manifest, environment hashes, and raw samples. Binary snapshots use `.archive`
suffixes so they are retained outside ignored build directories.
