# Independent P256 round-four audit

Approved for the frozen candidate at source checkpoint `989c6c4`, with the public
fixture identifier correction tested afterward. No production correctness or
changed-code constant-time blocker was found. This is a source, generated-code
and test review, not a formal proof of the entire cryptographic dependency stack.
Earlier prepared-key and round-three evidence is preserved unchanged.

The tested runtime SHA-256 is
`b4b1f17afd54c3928bf037da4f1ddea0f3bc44d7e5bcde19f61c22e32ad0f378`
(140,006 bytes); compiler ELF is
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
`approval.json` and the execution reports retain the exact source, plugin,
compiler, original release/debug RTS, fixture and log hashes. No compiler/SDK,
public API, native allocation policy or prepared-payload layout changed.

## Arithmetic and emitted code

The scalar inversion follows the [pinned Go addition chain](https://go.googlesource.com/go/+/2c659bb4db1ff06c819f8b4cd6decc71e4d5b36e/src/crypto/internal/fips140/nistec/p256_ordinv.go).
`scalar_chain.py` independently evaluates the actual Rust expressions and proves
exponent n−2 with 254 squares and 38 multiplies. Zero retains `CtOption::none`.
The added wide square reuses [`crypto-bigint` 0.5.5](https://raw.githubusercontent.com/RustCrypto/crypto-bigint/v0.5.5/src/uint/mul.rs),
with the existing Barrett reducer. The half-grid, diagonal and carry schedules
use fixed four-limb bounds; its internal variable-time shift receives constant 1.
Exact Python integer expectations cover 1,085 squared values and inverses,
including zero, order boundaries, powers of two and adjacent values.

The secret generator comb has four tables of 15 nonidentity points, 16 rounds,
64 complete mixed additions and 16 doublings. An independent affine arithmetic
oracle reproduces all 60 canonical Montgomery points and checks that the digit
schedule covers every scalar bit exactly once. Emitted Wasm has only the three
fixed scan/table/round branches in the comb: every digit scans all 15 entries,
including zero digits; table addresses depend only on public counters.

`wasm_review.py` preserves the nine reviewed function bodies and checks the
selected binary. All 31 calls to the scalar-square loop supply positive literal
counts. Its only branch is the fixed countdown; scalar multiply/reduction,
complete mixed addition, doubling and the word-multiply helper have no conditional
branches in this artifact. Signing retains its existing input validation,
RFC6979 rejection and rare signature-result rejection paths. This review does
not claim that the entire signing function is branch-free.

The projective representation is homogeneous: x=X/Z and y=Y/Z. Verification
rejects Z=0 and compares X=rZ or X=(r+n)Z; n<p<2n makes these candidates exhaustive.
`NonZeroScalar` bounds r, checked addition prevents 256-bit wrap, and canonical
field decoding rejects r+n≥p. The helper has no inversion or affine conversion.
Branches in this helper depend on public verification inputs. Independent tests
exercise valid x=n+3 and x=p−3, false field wrap at r+n=p, false carry wrap at
r+n=2^256, identity cancellation, high-S signatures and reduced digests.

## Execution

| Gate | Result |
|---|---|
| Native debug and release | 18/18 each, including the owner's 484-case Wycheproof suite |
| Independent oracle corpus | 1,085 scalar square/inverse cases, 512 derivations, 43 exact RFC6979 signatures, 184 direct/prepared verification equations |
| Motoko independent suite | Source interpreter, IR interpreter, lowered IR and generated Wasm all pass |
| Public module suites | Both existing P256 and new projective-boundary fixtures pass all four engines |
| Public Ash suite | 19/19, with sanity checks and forced GC |
| Emitted stack audit | All 43 functions covered; no unresolved/indirect calls or recursive call graph |

The Motoko corpus includes all 184 verification equations and 43 exact signatures,
plus 72 compressed/uncompressed derivations chosen around comb partition and
scalar boundaries. Native tests additionally use offset-one input/output buffers,
canaries and prepared-input immutability checks.

Conservative maximum native stack paths are 8,736 bytes for signing, 7,296 for
key derivation, 3,344 for direct verification, 1,360 for prepared verification,
and 88,000 for preparation. Prepared payload remains 16,320 bytes. These are
native temporary stack bounds, distinct from Motoko heap allocation.
The unchanged nominal type/managed Blob layout retains the prior GC audit;
the public Ash suite also rechecks retained aliases, collection, drop and reprepare.

The first public gate caught a test-only reserved identifier (`label`) and a
missing local core dependency. The owner renamed it `name`, and the audit linked
the pinned local dependency temporarily. Both failures and the successful rerun
are retained; the temporary link was removed. No runtime correction was needed.
Native logs retain upstream vendored deprecation/attribute warnings; no
warning-free build claim is made.

## Benchmark acceptance

`benchmark.py` independently checks all 916 baseline and 922 candidate frozen
inputs, source/artifact parity, identical compiler/RTS/dependencies/actor sources
and compile flags, every output, and all summary arithmetic. All 168 observations
(28 cases × two revisions × three fresh canisters) pass; each trial's counters
are identical within its case/revision.

| Representative operation | Baseline instructions | Candidate instructions | Reduction |
|---|---:|---:|---:|
| Sign RFC6979 sample | 7,252,878 | 4,791,659 | 33.93% |
| Derive compressed public key | 4,996,581 | 3,297,998 | 33.99% |
| Direct verification | 12,541,922 | 11,961,908 | 4.62% |
| Prepared verification | 3,802,871 | 3,223,424 | 15.24% |
| Prepare + 100 verifications | 399,943,697 | 341,998,949 | 14.49% |

These are measured whole intervals. Allocation, prepared payload and all sampled
memory counters are unchanged. Runtime Wasm grows by 14,570 bytes; linked actors
grow by 14,425 bytes. Occupancy snapshots are neither peak nor retained-live
memory measurements. The paired final report, not intermediate candidate screens,
is the source of these claims. Full case metrics are in
[`comparison-final.md`](../../../../benchmarks/crypto/round4/p256/comparison-final.md).
