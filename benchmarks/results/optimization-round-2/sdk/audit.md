# Independent SDK audit: second optimization round

Approved production candidate: `src/codegen/compile.ml` SHA-256
`740aad1f0e886564fb2ccdffcd71f3ec1f3132f27b7cac8886ac7e0dc0fb4b4b`.
The only implementation change removes the two payload shifts from
`Backend.Compare.scalar` for Nat8/16/32, Int8/16/32, and Char. No unresolved
production findings. No ABI, API, allocation, GC, or interpreter changes.

## Representation and type proof

For a small scalar of payload width `n`, its vanilla value is the payload
shifted by `k = 64 - n` plus the fixed type tag `d`, where `0 <= d < 2^k`.
Unsigned comparison therefore orders `x * 2^k + d` exactly as `x`.
For signed payloads the signed i64 interpretation is the same affine formula
with signed `x`: its minimum remains at least `-2^63`, its maximum remains
below `2^63`, and its slope is positive. Equality is preserved as well.
Char uses unsigned comparison, including codepoints above `0x100000` whose
shifted payload sets bit 63. Signedness and stack operand order remain correct.

Reviewed `TaggingScheme.tag_of_typ`, `TaggedSmallWord` literal/tag/shift helpers,
`StackRep.adjust`, Candid decoding, ordinary scalar operators, SDK argument
lowering, and the production pure-map schema/generator. Small scalar values
are immediate values, including those loaded from heap containers. Plugin
arguments use vanilla representation. The frontend and IR checker retain
specialization/type validation; aliases promote to the same primitive type.
Nothing removes input-dependent checks. The removed shift helpers never
performed sanity checks. Bool normalization, boxed 64-bit values, and bignum
comparison must remain separate and are unchanged. No allocations, stores,
forwarding operations, callbacks, or GC safepoints were added or removed.

## Independent execution checks

Two evidence-only fixtures in `audit/` passed with `--sanity-checks`:

- `run/scalar-paths.mo`: source, IR, lowered IR, and Wasm execution. Checks
  source-order index ranks instead of deriving expected results from the
  target scalar's comparison. Covers all seven affected types, signed and
  unsigned endpoints, Char surrogate-gap and high-codepoint boundaries,
  aliases, generic functions, mutable cells, closure reads, and arithmetic
  conversions before the plugin boundary.
- `run-drun/scalar-candid-gc.mo`: Candid round-trip of typed scalar arrays,
  retained across message suspension and forced collection, then the same
  independent rank checks. Confirms more than 32 MiB was actually reclaimed.

The owner additionally exercised all 65,536 pairs in each eight-bit domain,
wider boundary vectors, the full 46-fixture SDK suite, packaging, native/JS
Dune targets, and Dune tests. The independent fixtures required correcting
only their initial warning/syntax/expectation setup; final logs record both
passing. Expected drun output was generated through `test-runner -a`, then
verified without acceptance.

## Benchmark evidence

`audit/verify-evidence.py` independently verifies every expected phase and
trial, exact source/cases/runner/Wasm hashes, output hashes, absence of errors,
and zero reclamation. Both versions contain all 216 scalar and 108 map raw
measurements combined; each case/phase has three trials per version. There is
no successful-only filtering. Cumulative allocated bytes are identical for
all paired samples, including the checksum harness's own allocations.

Each affected comparison saves exactly **4 IC instructions**: 168 instructions
for 42 comparisons, or 688,128 for 172,032 comparisons. Empty loops and all
Bool/Nat64/Int64/Nat/Int controls are unchanged. These are absolute savings,
not a claim of a large percentage improvement in the allocation-heavy scalar
checksum workload.

Prebuilt Nat32/Int32 maps at 1,000/10,000/100,000 entries use 4.03–5.52% fewer
instructions for the measured hit/miss batches, and 1.29–1.41% fewer for
overwrite batches. Each batch performs 1,000 operations. Inputs/setup are
outside timing. Lookup/missing results are checked; overwrite validation
reads the retained maps after timing and verifies every updated value.
This isolates the SDK change against unchanged pure-map sources; it does not
measure the independently optimized round-two map candidate.

The initial scalar benchmark incorrectly used native equality on a deliberately
noncanonical true representation from `fixtureTrue()`. That oracle produced
the same six failed controls in both versions; the original data is retained
under `rejected-oracle/`. The final oracle compares logical truth with
conditionals. Both final versions have zero failed measurements, and the Bool
instruction/allocation control remains identical. This was an evidence bug,
not a production SDK defect.

## Committed-binary confirmation

Rechecked commit `128a41c060d473e4307dbfcce88b4587312a29b6` after its clean
rebuild (compiler SHA-256
`c5bb31568300df2bf982779755a202f290e81c3350cb35f08e149a060fab7ec3`).
The approved production and regression-test source hashes are unchanged.
Fresh three-trial scalar/map candidate cohorts pass the independent verifier;
every accepted instruction, allocation, reclamation, and output measurement
is identical to the preserved `precommit/` cohorts. Baseline provenance and
Wasm hashes remain unchanged. The committed actor Wasm hashes were checked
against the actual files; the version-dependent binaries were freshly measured,
not treated as identical through metadata normalization. Approval stands.
