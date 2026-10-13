# BLS verification optimization, round six

Measured 2026-10-13. The selected runtime reduces IC single verification by
**39.42% direct / 39.51% with a prepared key**, with unchanged managed allocation
and prepared-key sizes. Ethereum verification and aggregate workloads improve
by similar amounts. No compiler, SDK, public API or prepared-key layout changed.

The current baseline is the runtime deployed at plugins commit `e53c68c`, not
the older prepared-key implementation. The selected source is integration commit
`429eed269a58481be04cac7ef07097bc03261c54`. Both revisions use the same compiler,
RTS, public modules, fixtures, independent expected outputs and measurement code.

## Final instruction costs

Each entry is **before → after**, measuring one complete operation. Every row
has three fresh-canister observations per revision, and all three values were
identical. All **90 final primitive observations** passed their output oracle.

| Operation | Direct verification | Verification with prepared keys | Key preparation |
|---|---:|---:|---:|
| IC single | 210,673,356 → **127,630,963** | 167,427,790 → **101,276,827** | 43,312,942 → **26,421,512** |
| Ethereum single | 274,974,367 → **167,544,868** | 263,831,154 → **161,204,207** | 11,144,375 → **6,341,823** |
| IC aggregate, 2 distinct messages | 291,392,273 → **176,889,136** | 204,848,489 → **124,128,212** | 86,625,804 → **52,842,944** |
| Ethereum aggregate, 2 distinct keys | 915,594,594 → **559,152,229** | 365,647,166 → **224,063,799** | 549,948,940 → **335,089,942** |
| Ethereum aggregate, 8 distinct keys | 3,175,970,967 → **1,941,213,088** | 976,180,848 → **600,858,961** | 2,199,794,662 → **1,340,358,670** |

Preparation is separate from the prepared verification interval. Ethereum
aggregate preparation verifies a proof of possession for every key; single-key
Ethereum preparation only decodes and validates the key. IC preparation creates
the pairing coefficient table. Aggregate setup includes all keys in that row.

[Full 12-case comparison](final-comparison.md) and
[Ethereum eight-key comparison](eth8-comparison.md) retain exact per-operation
reductions, allocation, Wasm sizes and min/max ranges. Their JSON counterparts
also retain all memory snapshots and provenance:
[main matrix](final-comparison.json), [eight-key matrix](eth8-comparison.json).

## Allocation and memory

These numbers are identical before and after:

| Operation | Allocated B: direct / prepared / preparation | Prepared payload B |
|---|---:|---:|
| IC single | 64 / 64 / 19,736 | 19,680 |
| Ethereum single | 64 / 64 / 200 | 144 |
| IC aggregate, 2 messages | 40,552 / 544 / 39,512 | 39,360 |
| Ethereum aggregate, 2 keys | 60,392 / 60,600 / 440 | 288 |
| Ethereum aggregate, 8 keys | 181,112 / 181,552 / 1,688 | 1,152 |

Allocation is cumulative managed allocation, including temporary objects; it
does not include native scratch or measure peak/retained heap. Prepared payload
sizes exclude normal object, array and variant overhead. Every sample reported
zero synchronous reclamation. Occupied-heap and Wasm-capacity snapshots before
the call, after its message, and after four additional GC increments were also
identical between revisions; these snapshots are not a retained-live-heap proof.

The plugin runtime shrinks **655,629 → 617,967 bytes**. Every measured primitive
canister shrinks by **36,519 bytes**. Thus the speedup does not trade for larger
runtime code or additional persistent/prepared tables.

## Certified-data relay

The unchanged [certificate investigation](../ic-certified-relay/README.md) was
rerun with the final BLS artifact: **45 observations and 12 rejection controls
passed**. These are authentic PocketIC NNS-to-subnet-to-canister certificates,
with a 32-byte record and an application witness for the indicated tree size.

| Verification path | Tree entries | Previous instructions | Final instructions | Allocated B, unchanged |
|---|---:|---:|---:|---:|
| Cold, both BLS signatures | 1,000 | 423,376,817 | **257,292,031** | 102,320 |
| Cached delegation and prepared subnet key | 1,000 | 168,737,010 | **102,586,047** | 65,408 |
| Cached authenticated application root | 1,000 | 565,546 | **565,546** | 26,176 |
| Cold, both BLS signatures | 100,000 | 423,716,169 | **257,631,383** | 117,552 |
| Cached delegation and prepared subnet key | 100,000 | 169,076,362 | **102,925,399** | 80,640 |
| Cached authenticated application root | 100,000 | 904,898 | **904,898** | 41,408 |

Cached-root verification and the diagnostic parse/hash-only cases are exactly
unchanged because they perform no BLS operation. The full report also measures
a prepared root key, a raw cached subnet key, subnet-key preparation, and
state-tree reconstruction plus single-signature verification. Those component
rows must not be confused with bare BLS verification or a complete verifier.

The recorded compiler, all eight relay source files, fixtures, SHA256 artifact,
methodology and negative controls match the earlier run. The copied
[baseline](relay-baseline.json), [final results](relay-results.json),
[checked comparison](relay-comparison.json), [source/build pins](relay-build.json)
and [frozen source archive](relay-sources.tar.gz) preserve the evidence. The
comparison is reproduced by `python3 benchmarks/crypto/bls-verify-round6/summarize-relay.py`
after moving aside the generated comparison file; it refuses to overwrite it.

This remains a bounded classic-certificate research verifier. It does not become
a production certificate library through this optimization. Input Candid decoding,
cache setup, replay bookkeeping and business operations are outside its timer;
the original report describes format coverage, authorization, freshness and replay
limitations. Reusing a certified application root avoids pairings only while the
proof refers to that already authenticated root and the application's freshness
policy permits it.

## Selected changes and isolated screens

The benchmark screened independent candidates before combining them:

| Candidate | IC direct instructions | IC prepared instructions | Reduction vs baseline, direct / prepared |
|---|---:|---:|---:|
| Baseline | 210,673,356 | 167,427,790 | — |
| Direct modular field subtraction | 207,767,445 | 165,014,413 | 1.38% / 1.44% |
| Shorter equivalent pairing final exponent | 205,184,551 | 161,938,985 | 2.61% / 3.28% |
| Field subtraction + fixed 32-bit-halves multiply-add | 131,276,175 | 104,922,039 | 37.69% / 37.33% |
| All selected changes | 127,630,963 | 101,276,827 | 39.42% / 39.51% |

The four screen cohorts account for **24 additional observations**. Their strict
comparisons are [subtraction](field-sub-comparison.md),
[pairing](pairing-comparison.md) and [multiply-add](field-mac-comparison.md).
The combined result was measured independently; improvements are not added or
modeled. The multiply-add helper avoids expensive Wasm lowering of a generic
128-bit expression while retaining fixed work. The pairing change computes the
same target-group result with fewer field operations. Validation, canonical
decoding, subgroup/nonidentity checks and proof-of-possession requirements remain.
The [remaining widening-multiply helper call](remaining-multi3.json) is in checked
allocator-size arithmetic, outside field multiplication and pairing loops. That
allocator arithmetic was left unchanged.

## Reproduction and provenance

- Compiler: source `9f6ebeedc`; exact ELF SHA256
  `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
- PocketIC 10.0.0; runner records server hash, loaded JS dependency hashes, compiler,
  RTS, fixture, plugin, compiled-canister and frozen-source identities.
- Baseline BLS runtime:
  `ebc5fa2fd9fc6ed3698bd523f5101d4883ef51c0e7bf4783f4b2da64d691972c`.
- Selected BLS runtime:
  `a2b0689d10224ffea6478e266fad65a32bd7b69911124b93fbd4fb9202fab4c1`.
- Rust: `1.99.0-nightly (da86f4d07 2026-07-24)` from the Motoko Nix shell.

The existing [prepared builder](../prepared/build.py),
[runner](../prepared/run.mjs) and [strict revision comparison](../round4/compare.py)
are reused. A fresh canister is configured for each case/trial; four GC increments
precede measurement. Output validation and serialization execute after the
counters. No empty-loop subtraction or per-operation division is applied.

Build [final-cases.json](final-cases.json) with a JSON `--plugin-roots` map pointing
`bls12-381` at the chosen built source checkout, and use a new immutable stage name:

```sh
python3 benchmarks/crypto/prepared/build.py \
  --manifest benchmarks/crypto/bls-verify-round6/final-cases.json \
  --stage prepared-bls6-reproduction \
  --evidence-root benchmarks/crypto/bls-verify-round6 \
  --bundle /path/to/matching/compiler-and-rts \
  --moc /path/to/matching/compiler-and-rts/moc \
  --plugin-roots /path/to/plugin-roots.json
node benchmarks/crypto/prepared/run.mjs \
  --build benchmarks/crypto/bls-verify-round6/results/prepared-bls6-reproduction/build.json \
  --out benchmarks/crypto/bls-verify-round6/results/prepared-bls6-reproduction/results.json \
  --trials 3
```

For the additional Ethereum matrix, use `prepared/bls12-381/cases.json` with
`--filter '^bls12-381-aggregate-ethereum-distinct-n8-(direct|prepare|prepared)$'`.
The [source store](source-store.json) deduplicates all completed frozen cohorts;
[integrity verification](evidence-integrity.json) checks those source and artifact
pins. Restore it with the existing prepared `restore-sources.py` utility and
`--evidence-root benchmarks/crypto/bls-verify-round6`.

Earlier interrupted work is retained locally: the initial field snapshot contained
truncated files and was replaced by a new detached worktree. An initial candidate
freeze then correctly rejected a different compiler ELF with the same source
version, before any measurement. Its [failure record](results/prepared-bls6-screen-field-sub/failure.json)
remains; the plugin was rebuilt against the exact original compiler host. Successful
stages, result files and source pins were never overwritten to resolve either issue.
The resumed screen baseline also had a truncated compressed source archive. All
948 frozen inputs matched their recorded hashes; a replacement portable archive
was reconstructed exclusively from those inputs. The original truncated archive
remains local and its hash and recovery procedure are recorded in
[archive-recovery.json](results/prepared-bls6-screen-baseline/archive-recovery.json).
The measured build, Wasm, results and input pins are unchanged.
