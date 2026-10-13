# Independent Secp256k1 round-four audit

Approved production commit `1185c2f`. No production correctness defect was found.
The selected runtime SHA-256 is
`1b34c5dc19da1421e64d1fa2e55e94401616efd06b3e4cba161ea1a29ab62ce7`;
the compiler-plugin hash is
`9dfc4d91e856d3553301cf40d909cf65b8cae6c1c6e17554acef2a07149d8ae4`.
The SDK executable remains `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.

Passed against those frozen artifacts:

- **22 native tests in both debug and release.** These include the owner's
  arithmetic/signature regressions and independent Python expectations for
  32 prepared key/signature sets, 1,283 full-width scalar squares, and 231
  additional FFI vectors with prepared-verifier replays. Inputs, output canaries,
  initialized errors and null predicate outputs are checked.
- **19 all-engine fixtures:** source, IR and lowered interpreters, actual Wasm64,
  and Wasm validation. The existing direct/prepared corpus includes 476 Wycheproof
  cases, official BIP340/RFC6979 vectors, and independently generated signatures.
  New fixtures cover 29 fixed-base scalar patterns and 36 constructed ECDSA
  verification points, including 12 forbidden field-wrap attacks. Both signature
  S polarities and both direct/prepared APIs are exercised.
- **Nine meaningful nominal rejections**, including explicitly typed Blob
  forgeries, scheme/secret substitutions, backing-Blob disclosure, shared
  parameters and stable fields.
- **All 264 fixed-base constants and 16 verification-table constants** match
  independent integer curve multiplication and canonical field encodings.
  The balanced-radix reconstruction is checked for 1,283 boundary/random scalars.

[Execution evidence](evidence/evidence.json), [generated-case counts](evidence/generated.json),
[constant checks](generator-evidence.json), and [retained logs/fixtures](evidence/retained-files.json)
pin the exact inputs and results. The runner reuses prior generators as read-only
inputs; their hashes are in [protocol-dependencies.json](protocol-dependencies.json).

## Source and emitted-code review

The immutable generator table follows the existing radix-16 schedule. Even and
odd digit sums reconstruct the scalar with four final doublings. Full eight-entry
selection uses `subtle`; table row addresses depend only on public loop counters.
Existing complete mixed-add formulas handle zero digits and cancellation.
Generic arbitrary-point multiplication remains unchanged.

The ECDSA check uses the actual homogeneous convention `x = X/Z`. It rejects
infinity, compares field differences modulo p, and only tests `(r+n)Z` under the
strict `r < p-n` bound. This prevents field-wrap acceptance. Parsing order,
typed errors and high-S acceptance are preserved. The variable-time helper is
called only from public ECDSA verification.

Scalar squaring delegates to pinned crypto-bigint's full-width square and the
unchanged k256 reduction. Limb-loop limits and the one-bit wide shift are public;
no custom carry arithmetic is added. The emitted scalar-square function has ten
wide multiplication calls and no conditional branches. Its reduction and wide
multiplication helpers are also branch-free. Fixed-base selection has all eight
fixed-offset scans and no conditional branches; multiplication has three public
counter loop exits. [Pinned Wasm excerpts](wasm-review/wasm-review.json) retain
the reviewed functions. This targeted review is not a formal constant-time or
host timing certification.

[Vendor provenance](vendor-evidence.json) verifies all 34 original archive files,
eight modified upstream files and three added source files. Applying the exact
patch without fuzz reproduces every source byte.

The compiler bridge, borrowed-Blob rules and 512/64-byte prepared layouts are
unchanged. The coordinator therefore reused the [previous actual-GC lifecycle
audit](../../prepared/secp256k1/gc/README.md); it was not rerun in this round.
No isolated live-heap or managed-secret erasure claim is made.

## Performance evidence

[Independent numeric review](numeric-review.json) recomputes all **132** raw
PocketIC observations and all four incremental/final comparisons. Compiler,
runtime, source, compiled-Wasm, oracle and result hashes match; all triples are
identical. Relative to the previous optimized plugin, the measured fixtures use
36.55% fewer instructions for ECDSA signing, 47.42% fewer for direct Schnorr
signing, and 46.78% fewer for prepared Schnorr signing. ECDSA verification improves
6.30% directly and 6.97% prepared. Schnorr verification increases by 534
instructions. Managed allocation is unchanged; runtime Wasm grows by 26,034 bytes.
These are fixture-specific instruction counts, not host-throughput estimates.

The [additional numeric review](extra-numeric-review.json) verifies all **36**
paired ten-call observations, bringing the reviewed total to **168**. All three
README reuse rows match the raw counters. With preparation inside the measured
interval, ten ECDSA verifications cost 22,508,855 instructions versus 24,539,878
directly (8.28% saving); Schnorr verification costs 22,101,917 versus 24,135,788
(8.43%); Schnorr signing costs 15,060,120 versus 26,812,948 (43.83%). The additional
allocation is exactly one preparation: 568 bytes for either public key or 120
bytes for the secret key. No additional runtime changes or tests were needed.

## Reproduction

Use the matching SDK Nix shell and a coordinator execution slot:

```sh
python3 /absolute/plugin-checkout/tests/crypto-audit/round4/secp256k1/run.py \
  --plugin /absolute/plugin-checkout/dist/secp256k1 \
  --motoko /srv/shared/code/motoko_experiments/prepared-crypto/sdk \
  --out /absolute/plugin-checkout/_build/round4-audit-final
```

`review_wasm.py`, `check_vendor.py` and `review_benchmarks.py` separately reproduce
the emitted-code, pinned-source and numeric checks. Each accepts an explicit
input/output path; no global compiler, SDK source or old evidence is modified.
