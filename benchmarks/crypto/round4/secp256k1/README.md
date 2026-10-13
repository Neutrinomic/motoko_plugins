# Secp256k1 signing and verification: round four

This pass reduces ECDSA signing by **36.5%**, direct Schnorr signing by **47.4%**,
and prepared Schnorr signing by **46.8%** relative to the previously optimized
plugin. APIs, validation, deterministic signatures, caller-supplied auxiliary
randomness and prepared-key formats are unchanged. The generator table is
immutable; no lazy initialization or mutable global cache is added.

The final comparison covers **17 unique matched case pairs and 102 PocketIC
observations**: 11 individual-operation cases and six ten-call batches, each
measured with the baseline and final plugin in three fresh canisters. Another
66 observations cover the two intermediate optimization screens. All 168
observations passed, and every instruction/allocation triple was identical.
The [final comparison](final-comparison.json)
pins both complete result/build manifests and runtime hashes. These are retained
independent RFC6979 and official BIP340 fixtures; costs are input-specific.

| Operation | Before instructions | Final instructions | Reduction | Allocation per call |
|---|---:|---:|---:|---:|
| ECDSA sign | 3,618,719 | 2,295,959 | 36.55% | 120 B |
| Schnorr sign | 5,099,447 | 2,681,364 | 47.42% | 120 B |
| Prepared Schnorr sign | 2,584,269 | 1,375,272 | 46.78% | 120 B |
| Derive compressed public key | 2,517,895 | 1,308,861 | 48.02% | 128 B |
| ECDSA verify | 2,618,931 | 2,454,026 | 6.30% | 32 B |
| Prepared ECDSA verify | 2,367,381 | 2,202,476 | 6.97% | 32 B |
| Schnorr verify | 2,413,083 | 2,413,617 | -0.022% | 32 B |
| Prepared Schnorr verify | 2,161,197 | 2,161,731 | -0.025% | 32 B |

Preparation is measured separately, including result construction. The exact
prepared payload and observed allocation are different quantities.

| Preparation | Before instructions | Final instructions | Payload | Allocation |
|---|---:|---:|---:|---:|
| ECDSA public key | 484,693 | 484,693 | 512 B | 568 B |
| Schnorr public key | 485,205 | 485,205 | 512 B | 568 B |
| Schnorr secret key | 2,517,394 | 1,308,308 | 64 B | 120 B |

All measured allocations are unchanged. Runtime Wasm grows from **154,876 to
180,910 bytes**, an increase of **26,034 bytes**. Most growth is the immutable
generator table. Full canister Wasm sizes and outside-interval heap/capacity
snapshots are retained in the raw results; snapshots do not measure peak heap
or isolate retained live bytes. No secure erasure of managed secrets is claimed.

## Including preparation and ten uses

These are measured complete batches using the final plugin. Prepared calls
include one factory call inside the measured interval, followed by ten uses.
The [extra comparison](extra-comparison.json) also pins matched measurements
of these six workloads with the previous plugin.

| Operation | Ten direct calls | Prepare + ten calls | Saving from preparation | Direct / prepared allocation |
|---|---:|---:|---:|---:|
| ECDSA verify | 24,539,878 | 22,508,855 | 8.28% | 320 / 888 B |
| Schnorr verify | 24,135,788 | 22,101,917 | 8.43% | 320 / 888 B |
| Schnorr sign | 26,812,948 | 15,060,120 | 43.83% | 1,200 / 1,320 B |

Compared with the previous plugin's same preparation-plus-ten batches,
ECDSA verification improves 6.83% and Schnorr signing improves 46.90%.
Schnorr verification increases by 5,340 instructions per ten-call batch
(0.024%), matching the small hot-call regression above. Allocations are unchanged.

## Three narrow changes

1. **Fixed-generator multiplication.** Adapt k256's existing signed radix-16
   schedule to an immutable affine table. Full eight-entry constant-time scans
   replace per-call table setup, and four doublings replace 128. Existing scalar
   recoding and complete addition formulas remain. The table has 264 points,
   representing 16,896 bytes of canonical coordinates; generated constants are
   independently reproducible. Arbitrary-point multiplication remains unchanged.
   [Measured increment](c1-fixed-generator.json).
2. **ECDSA coordinate comparison.** Check homogeneous `X = rZ`, or `X = (r+n)Z`
   only when `r < p-n`, instead of inverting Z to recover affine X. Explicit
   identity and strict field-boundary checks preserve the verification equation.
   This saved 165,617 instructions per measured ECDSA verification before the
   final squaring change. [Measured increment](c2-inversionless-verify.json).
3. **Dedicated scalar squaring.** Reuse pinned crypto-bigint's existing wide
   square with unchanged k256 modular reduction and inversion addition chain.
   It saves another 113,666 ECDSA signing instructions and 183 runtime bytes.
   Small deterministic regressions are retained: +712 instructions per ECDSA
   verification, +534 per Schnorr verification and +89 per Schnorr signature,
   at most 0.033%. [Measured increment](c3-specialized-square.json).

| Stage | Runtime Wasm bytes | Increment |
|---|---:|---:|
| Previous optimized baseline | 154,876 | — |
| Fixed generator | 179,508 | +24,632 |
| Inversionless ECDSA verification | 181,093 | +1,585 |
| Specialized scalar square, final | 180,910 | -183 |

## Validation and reproduction

The final native suite passes **19 tests in debug and release**. It includes
1,283 fixed-generator comparisons against unchanged generic multiplication,
1,283 scalar-square comparisons against general multiplication, official
BIP340 and independent RFC6979 signatures, prepared-key equivalence, validation
errors, and constructed rare `x >= n` / forbidden field-wrap / identity cases.
The independent audit passes **22 native tests in both profiles, 19 all-engine
fixtures and nine nominal-type rejection checks**. It independently checks
280 embedded generator points, 1,283 scalar-square expectations and 231 FFI
cases, including 36 constructed ECDSA points. Review of emitted Wasm confirms
fixed table scans and fixed-offset squaring without secret-dependent branches
in the changed routines. All four comparison summaries match the raw counters.
Evidence is under [`tests/crypto-audit/round4/secp256k1`](../../../../tests/crypto-audit/round4/secp256k1/).

The SDK, runtime bridge, borrowing rules and prepared layouts are unchanged;
the [previous actual-GC lifecycle audit](../../../../tests/crypto-audit/prepared/secp256k1/)
remains applicable.

The SDK is unchanged: commit `9f6ebeedc`, compiler executable SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`,
with its original RTS. Plugin baseline is `0e1e96a`. Final runtime SHA-256 is
`1b34c5dc19da1421e64d1fa2e55e94401616efd06b3e4cba161ea1a29ab62ce7`.

`generate.py` emits the matched 11-case cohort using the shared prepared
benchmark protocol. `generate_extra.py` reuses the six retained direct10/cold10
workload sources without changing the original screen fixtures. The shared builder freezes source, plugin artifacts,
compiler, RTS, dependency locks and independent expected outputs before
compilation. Retained stages are `prepared-round4-secp256k1-c1-baseline`,
`prepared-round4-secp256k1-c1-candidate`, `prepared-round4-secp256k1-c2-candidate`
and `prepared-round4-secp256k1-c3-candidate`; the extra paired stages are
`prepared-round4-secp256k1-extra-baseline` and `prepared-round4-secp256k1-extra-final`.
`summarize.py` checks exact cohort,
compiler, source and oracle equality before creating incremental summaries.

Primary algorithm references are the [upstream k256 fixed-base schedule](https://raw.githubusercontent.com/RustCrypto/elliptic-curves/k256/v0.13.4/k256/src/arithmetic/mul.rs),
[libsecp256k1's two-coordinate ECDSA check](https://github.com/bitcoin-core/secp256k1/blob/master/src/ecdsa_impl.h)
and [crypto-bigint's wide square](https://github.com/RustCrypto/crypto-bigint/blob/v0.5.5/src/uint/mul.rs).
The exact vendored delta and file hashes remain in the plugin's `exact.patch`
and `upstream-source.json`. This work has regression and independent internal
review coverage; it has not received an external cryptographic audit.
