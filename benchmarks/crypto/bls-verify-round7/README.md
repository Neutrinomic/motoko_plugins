# BLS verification optimization, round seven

Measured 2026-10-13 against the already optimized round-six runtime at plugins
commit `8ea797e`. The selected implementation uses **15.42% fewer instructions
for IC verification, or 15.63% fewer with a prepared key**. Ethereum single and
aggregate verification improves by about 15%. Managed allocation, prepared-key
sizes and sampled memory are unchanged. No compiler, SDK, API or prepared-key
layout changed.

The selected source is integration commit
`56baf39e72d5e80fe0df19affab1f5d46ba6e2d6`. Both revisions use the same compiler,
RTS, public modules, fixtures, independent output oracles and measurement code.
A fresh baseline rerun exactly reproduced all 15 round-six final instruction and
allocation counts; see [baseline reproduction](baseline-reproduction.json).

## Final instruction costs

Each entry is **before → after**, measuring one complete operation. Every row has
three fresh-canister trials per revision, with identical observations in each
triple. All **90 final primitive observations** passed their output oracle.

| Operation | Direct verification | Verification with prepared keys | Key preparation |
|---|---:|---:|---:|
| IC single | 127,630,963 → **107,949,293** | 101,276,827 → **85,442,830** | 26,421,512 → **22,573,839** |
| Ethereum single | 167,544,868 → **141,664,860** | 161,204,207 → **136,101,721** | 6,341,823 → **5,564,301** |
| IC aggregate, 2 distinct messages | 176,889,136 → **150,133,148** | 124,128,212 → **105,067,570** | 52,842,944 → **45,147,598** |
| Ethereum aggregate, 2 distinct keys | 559,152,229 → **472,864,770** | 224,063,799 → **189,536,356** | 335,089,942 → **283,329,926** |
| Ethereum aggregate, 8 distinct keys | 1,941,213,088 → **1,643,095,683** | 600,858,961 → **509,781,620** | 1,340,358,670 → **1,133,318,606** |

Preparation is outside the prepared verification interval. Ethereum aggregate
preparation verifies a proof of possession for every key; single-key Ethereum
preparation only decodes and validates the key. IC preparation creates the
pairing coefficient table. Aggregate preparation includes all keys in that row.

The [full comparison](final-comparison.md) retains all 15 rows, exact reductions,
allocation and Wasm sizes. Its [JSON](final-comparison.json) also preserves the
min/max ranges, memory snapshots and provenance. All measured operations improve;
the smallest reduction is 12.26% for single Ethereum key preparation.

## Allocation and memory

These values are identical before and after:

| Operation | Allocated B: direct / prepared / preparation | Prepared payload B |
|---|---:|---:|
| IC single | 64 / 64 / 19,736 | 19,680 |
| Ethereum single | 64 / 64 / 200 | 144 |
| IC aggregate, 2 messages | 40,552 / 544 / 39,512 | 39,360 |
| Ethereum aggregate, 2 keys | 60,392 / 60,600 / 440 | 288 |
| Ethereum aggregate, 8 keys | 181,112 / 181,552 / 1,688 | 1,152 |

Allocation is cumulative managed allocation, including temporary objects. It
excludes native scratch and does not measure peak or retained live heap. Prepared
payload excludes ordinary object, array and variant overhead. All trials report
zero synchronous reclamation. Occupied heap and Wasm capacity snapshots before
the call, after its message and after four additional GC increments are identical
between revisions; these snapshots are not a retained-live-heap proof.

The BLS runtime shrinks **617,967 → 342,359 bytes**, a reduction of **275,608 B**.
Every measured primitive canister shrinks by **275,053 B**. The speedup therefore
does not require larger code or larger prepared tables.

## Certified-data relay

The unchanged [certificate investigation](../ic-certified-relay/README.md) was
rerun with the selected BLS artifact: **45 observations and 12 rejection controls
passed**. The comparison uses the round-six optimized runtime as its baseline,
not the older original relay cost. Inputs are authentic PocketIC NNS-to-subnet-to-
canister certificates, a 32-byte record and an application witness for each tree.

| Verification path | Tree entries | Before instructions | After instructions | Allocated B, unchanged |
|---|---:|---:|---:|---:|
| Cold, both BLS signatures | 1,000 | 257,292,031 | **217,928,691** | 102,320 |
| Cached delegation and prepared subnet key | 1,000 | 102,586,047 | **86,752,050** | 65,408 |
| Cached authenticated application root | 1,000 | 565,546 | **565,546** | 26,176 |
| Cold, both BLS signatures | 100,000 | 257,631,383 | **218,268,043** | 117,552 |
| Cached delegation and prepared subnet key | 100,000 | 102,925,399 | **87,091,402** | 80,640 |
| Cached authenticated application root | 100,000 | 904,898 | **904,898** | 41,408 |

The cached-root and diagnostic parse/hash-only controls are exactly unchanged:
they perform no BLS operation. The other relay rows include a prepared root key,
a raw cached subnet key, subnet-key preparation, and tree reconstruction plus
single-signature verification. Component rows are not bare BLS costs or complete
verifiers.

The [baseline](relay-baseline.json), [selected results](relay-results.json),
[checked comparison](relay-comparison.json), [build pins](relay-build.json) and
[source archive](relay-sources.tar.gz) preserve the evidence. All eight relay
sources, fixtures, compiler, SHA256 artifact, methodology and rejection controls
match the prior run. The copied [comparison script](summarize-relay.py) reproduces
the checked comparison after moving aside its output; it refuses to overwrite it.

This is still a bounded classic-certificate research verifier. Input Candid
decoding, cache initialization, replay tracking and application logic are outside
its timer. The original report explains format coverage, authorization, freshness
and replay limitations. Reusing an authenticated root avoids pairings only while
the proof targets that root and the application's freshness policy permits it.

## Selected changes and isolated screens

Five independent candidates were tested before combining them. Every candidate
uses the round-six implementation as its baseline; the combined result was
measured separately and is not a sum of the individual gains.

| Candidate | IC direct instructions | IC prepared instructions | Reduction, direct / prepared |
|---|---:|---:|---:|
| Baseline | 127,630,963 | 101,276,827 | — |
| Fixed-width subtraction with borrow | 123,600,354 | 98,004,009 | 3.16% / 3.23% |
| Rearranged multiply-add carry arithmetic | 117,714,781 | 94,517,393 | 7.77% / 6.67% |
| Fp2 Karatsuba multiplication | 125,010,880 | 99,524,479 | 2.05% / 1.73% |
| Fp6 Karatsuba multiplication | 125,992,239 | 99,638,103 | 1.28% / 1.62% |
| Fixed signed-x group multiplication chain | 127,261,053 | 101,113,468 | 0.29% / 0.16% |
| Combined selection | **107,949,293** | **85,442,830** | **15.42% / 15.63%** |

The screen baseline plus five candidates account for **36 additional primitive
observations**, all passing. Strict isolated comparisons retain exact input and
memory checks: [subtraction](field-comparison.md), [multiply-add](field-mac-comparison.md),
[Fp2](fp2-comparison.md), [Fp6](extension-comparison.md), [group chain](pipeline-comparison.md).
All five screened candidates improved and were selected; there was no rejected
measured candidate or failed benchmark stage in this round.

The field helpers preserve full-width arithmetic while avoiding costly Wasm
lowering. Karatsuba reduces the number of underlying field products; the old
interleaved implementation remains only as a test oracle. The fixed group chain
removes redundant group additions. Canonical decoding, subgroup/nonidentity
checks, ciphersuites and proof-of-possession requirements remain unchanged.

The [independent audit](../../../tests/crypto-audit/round7/bls12-381/README.md)
passed **138 vendor tests, 32 runtime tests, six public Motoko programs and six
Ash methods** against this source/artifact. It also checked the arithmetic
identities, carry bounds, group chain and preserved validation requirements.

## Reproduction and provenance

- Compiler: source `9f6ebeedc`, exact ELF SHA256
  `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
- PocketIC 10.0.0. The runner records server, loaded JS dependency, compiler, RTS,
  fixture, plugin, compiled-canister and frozen-source hashes.
- Baseline runtime SHA256:
  `a2b0689d10224ffea6478e266fad65a32bd7b69911124b93fbd4fb9202fab4c1`.
- Selected runtime SHA256:
  `d75badd132b617ef215a24e0106a9de823490376f6479ab88baace690e6feb86`.
- Rust: `1.99.0-nightly (da86f4d07 2026-07-24)` from the original Motoko Nix shell.

The existing [prepared builder](../prepared/build.py), [runner](../prepared/run.mjs)
and [strict comparison](../round4/compare.py) are reused. Every trial creates a
fresh canister. Setup and four GC increments precede measurement; output checking
and serialization follow the counters. There is no empty-loop subtraction or
per-operation division.

Build [final-cases.json](final-cases.json) with a JSON plugin-root map pointing
`bls12-381` at the selected built checkout, and choose an unused stage name:

```sh
python3 benchmarks/crypto/prepared/build.py \
  --manifest benchmarks/crypto/bls-verify-round7/final-cases.json \
  --stage prepared-bls7-reproduction \
  --evidence-root benchmarks/crypto/bls-verify-round7 \
  --bundle /path/to/matching/compiler-and-rts \
  --moc /path/to/matching/compiler-and-rts/moc \
  --plugin-roots /path/to/plugin-roots.json
node benchmarks/crypto/prepared/run.mjs \
  --build benchmarks/crypto/bls-verify-round7/results/prepared-bls7-reproduction/build.json \
  --out benchmarks/crypto/bls-verify-round7/results/prepared-bls7-reproduction/results.json \
  --trials 3
```

The [source store](source-store.json) deduplicates the eight completed cohorts.
[Integrity verification](evidence-integrity.json) checks archived sources,
metadata, all declared plugin inputs and local binary hashes. Use the existing
prepared `restore-sources.py` and `verify-evidence.py` with
`--evidence-root benchmarks/crypto/bls-verify-round7` to restore or verify it.
The [portable-only check](portable-integrity.json) also passes using only the
files staged for Git, without local frozen inputs or binaries. Frozen binaries
and absolute local plugin-root maps are excluded from Git.
