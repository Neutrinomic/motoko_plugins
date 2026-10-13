# P256 signing and verification: fourth performance pass

The selected implementation reduces RFC6979 sample signing from 7,252,878 to
4,791,659 IC instructions (33.93%) and public-key derivation from 4,996,581 to
3,297,998 (33.99%). Direct verification falls from 12,541,922 to 11,961,908
(4.62%); prepared verification falls from 3,802,871 to 3,223,424 (15.24%).
The final matched 28-case cohort confirms these results: all 168 observations
passed, with no final instruction regressions or allocation changes. See the
[full comparison](comparison-final.md) and its [machine-readable evidence](comparison-final.json).

All comparisons use compiler `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`, actual
`moc` SHA-256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`,
the original RTS, identical Motoko actors and independent expected outputs.
Baseline source is `0e1e96a4c325bdfebc627f0c16d546cb39c16a70`. Every measured
case has three fresh canisters and all three instruction counts agree.
The runner measures deterministic IC counters, not host wall-clock speed.

| RFC sample workload | Baseline instructions | Selected instructions | Selected allocated bytes |
|---|---:|---:|---:|
| One preparation | 19,688,675 | 19,688,627 | 16,376 |
| One direct verification | 12,541,922 | 11,961,908 | 32 |
| One prepared verification | 3,802,871 | 3,223,424 | 32 |
| Preparation + one verification | 23,491,346 | 22,911,851 | 16,408 |
| Preparation + 10 verifications | 57,714,287 | 51,919,769 | 16,696 |
| Preparation + 100 verifications | 399,943,697 | 341,998,949 | 19,576 |
| 100 direct verifications | 1,254,167,648 | 1,196,166,248 | 3,200 |
| 100 prepared verifications | 380,255,222 | 322,310,522 | 3,200 |

Every row is the measured complete interval, not a per-call extrapolation.
Preparing a key still costs more than one direct check; repeated use amortizes
that setup. The modeled break-even remains three verifications for this
fixture (`ceil(prepare / (direct - prepared))`); measured cold workloads are
shown separately. The rare valid `x=n+3` prepared check improves from 1,754,864
to 1,179,938 instructions (32.76%), and the deliberately false field-wrap
signature stays rejected. Final linked actor size increases by 14,425 bytes.

## Bounded candidate sequence

Only the selected implementation remains in production. Frozen source archives
retain the intermediate experiments; no runtime tuning switch was added.

| Revision | Sign | Derive key | Direct verify | Prepare key | Prepared verify | SEC1 expand | Runtime Wasm bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Baseline | 7,252,878 | 4,996,581 | 12,541,922 | 19,688,675 | 3,802,871 | 581,934 | 125,436 |
| Fixed scalar inverse chain | 6,603,023 | 4,996,581 | 12,541,922 | 19,688,675 | 3,802,871 | 581,934 | 139,176 |
| Existing symmetric wide square | 6,490,242 | 4,996,581 | 12,542,112 | 19,688,675 | 3,803,061 | 581,934 | 130,004 |
| Static two-table secret comb | 5,281,869 | 3,788,208 | 12,541,547 | 19,688,627 | 3,803,061 | 581,887 | 134,104 |
| Static four-table secret comb | 4,791,659 | 3,297,998 | 12,541,547 | 19,688,627 | 3,803,061 | 581,887 | 141,060 |
| Inversionless verification, selected | 4,791,659 | 3,297,998 | 11,961,908 | 19,688,627 | 3,223,424 | 581,887 | 140,006 |

The square change adds 190 instructions to both verification controls before
the final predicate improvement. Small deterministic changes in unrelated
controls remain visible above; they are not dismissed as measurement noise.
Allocated bytes remain 120/sign, 96/derive, 32/direct verification,
16,376/preparation, 32/prepared verification and 128/SEC1 expansion.
Prepared-key payload remains 16,320 bytes. The final plugin runtime grows
14,570 bytes over baseline; linked actor growth is reported per case.

The first change ports the fixed Go/Brian Smith `n−2` addition chain using
existing scalar operations (254 squares, 38 multiplies). The second reuses
the pinned crypto-bigint symmetric wide-square primitive and the same Barrett
reduction. [The proof](scalar-chain/verify-chain.py) independently interprets
the exact Rust exponent schedule. Attribution and the required Go license are
also carried inside the vendored crate.

The selected secret comb has four immutable tables of 15 affine points,
3,840 bytes total. It performs 16 doubles and 64 complete mixed additions;
every selection scans all 15 entries, including zero digits. Public constants
are checked independently against Python arithmetic and OpenSSL. The
four-table choice saves another 490,210 instructions per sign/derive versus
two tables for 6,956 additional runtime bytes. Secret-dependent lookup
addresses or loop counts were not introduced.

Verification uses primeorder's actual homogeneous coordinates, `x=X/Z`.
For canonical `0<r<n<p<2n`, it compares `X=rZ` or `X=(r+n)Z`, rejecting
`Z=0`, checked-integer addition overflow, and `r+n>=p`. The second comparison
preserves valid rare `x>=n` signatures. Independent fixtures also construct
false signatures that would expose either field or 256-bit wrapping. Only
public verification data controls these branches. Secret signing and key
derivation retain their affine normalization and fixed operation paths.

## Evidence

- Incremental comparisons: [chain](comparison-c1-chain.md),
  [wide square](comparison-c2-wide-square.md),
  [two tables](comparison-c3-two-table.md),
  [four tables](comparison-c4-four-table.md),
  [projective predicate](comparison-c5-projective.md).
- [Combined six-case comparison](comparison-screen-combined.md); matching
  JSON files retain exact pins, output hashes, instruction/allocation ranges,
  sampled heap/Wasm capacity and reclaimed counters.
- [Final 28-case manifest](final-selected.json): representative signing and
  derivation boundaries, valid/low-S/incorrect/rare/wrap verification cases,
  and measured direct/hot/cold reuse at 1, 10 and 100 calls. Full adversarial
  coverage belongs in correctness tests rather than duplicated timing rows.
- [Projective proof and independent vectors](projective-check/research.md),
  [selected static table proof](../../../../plugins/p256/tests/vectors/p256-comb-proof.json),
  and [native regression tests](../../../../plugins/p256/runtime/src/projective_tests.rs).
- Native and build logs are archived as reproducible `.log.gz` files. They
  preserve upstream path-dependency warnings instead of claiming warning-free
  builds. The final native suite passed all 14 tests, including all 484 pinned
  Wycheproof cases through direct and prepared verification.
- The [independent audit](../../../../tests/crypto-audit/round4/p256/README.md)
  passed 18 tests in both native debug and release, including 1,085 exact
  Python square/inverse values, 512 key derivations, 43 independent RFC6979
  signatures and 184 direct/prepared equations. Its own Motoko fixture and
  both public fixtures passed source, IR, lowered and Wasm execution; Ash
  passed all 19 tests. Source and emitted-Wasm review checked the fixed table
  scans, scalar exponent schedule and inversionless predicate. A reserved
  identifier in the new Motoko fixture was corrected before its successful
  rerun; the failed log is preserved and no production change was needed.
  Final approval also independently rechecked all 168 benchmark outputs,
  frozen input hashes, metric ranges and deltas. Allocation and sampled memory
  are unchanged. Audited native scratch-stack bounds are 8,736 bytes for
  signing, 7,296 for derivation, 88,000 for preparation and 1,360 for hot
  verification; these are separate from Motoko heap allocation.

Frozen stages are under `../results/prepared-round4-p256-*` in the integration
evidence tree. Each stage has its original portable source archive, exact
compiler/runtime pins, compiled actors, frozen runner and raw observations.
The selected runtime SHA-256 is
`b4b1f17afd54c3928bf037da4f1ddea0f3bc44d7e5bcde19f61c22e32ad0f378`.
Sampled heap occupancy/capacity is not a peak-memory measurement. The prepared
representation and lifetime are unchanged from the separately audited
prepared-key pass; this round introduces no retained native state or cache.
