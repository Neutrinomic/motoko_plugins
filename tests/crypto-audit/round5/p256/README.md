# P256 round-five audit

Found and fixed one interpreter/runtime mismatch in the generic ECDSA signer
shared by P256 and secp256k1. After RFC6979 supplied a valid nonce, the portable
reference retried if the resulting signature had zero r or s; both native
backends instead returned `invalidSignature`. P256 already documents that native
behavior. The reference now returns the same error, preserving nonce-candidate
rejection/reseeding, normal deterministic signature bytes, high-S/low-S behavior
and validation precedence. This aligns the existing plugin contract; it does not
claim to implement RFC6979's separate recommendation to retry an invalid
signature result.

The production change is three replacements and a comment in
`plugins/secp256k1/compiler/secp256k1_reference.ml`, also used through P256's
compiler symlink. It has an independent review. Neither native implementation,
the compiler SDK nor the prepared-key format changes in this lane.

## Regression evidence

`rare-signature.py` compiles temporary copies of the production implementations,
replacing only nonce selection with a guarded, counted test seam. For d=k=1,
choosing digest `n - Gx` forces s=0. Before the fix, both reference curves returned
a signature after two nonce requests: six assertions failed. After the fix, all
18 checks pass, including both real result wrappers, one nonce request, ordinary
nonzero controls and invalid-input precedence. Two native tests execute P256's
actual signing arithmetic and FFI wrapper with nonce 1: the zero-s result is
rejected, the 64-byte output is initialized, and adjacent canaries survive.

Run `tests/crypto-audit/round5/p256/run-native.sh` in the compiler Nix environment.
It bounds build/test concurrency at two and keeps outputs under ignored `_build`.
`rare-signature-evidence.json` records before/after source and injected-source
hashes, exact reference checks and the native result. The synthetic seam proves
the policy branch; it is not a natural RFC6979 preimage or a zero-r point witness.

## Added maintained coverage

OpenSSL independently generates 133 exact DER scalar pairs and 28 SEC1 decoder
answers in `plugins/p256/tests/vectors/encoding.json`. They cover every DER
length from 8 through 72 bytes, sign padding at every scalar byte width,
normalization around half the order, and field/scalar coordinate boundaries.
The generator checks both JSON and generated Motoko answers with `--check`.
Native malformed-DER tests assert the decoder's typed error itself, avoiding the
gap where an accepted malformed encoding could merely fail later verification.

`P256EncodingTests.mo` is shared by the normal Motoko fixture and three new Ash
methods. It checks all unsupported SEC1 tags, all truncations, trailing bytes,
canonical coordinate conversions and preparation, exact DER/normalization,
validation precedence and retained short output values. Five native FFI tests
cover byte offsets 1–8, exact capacities, immediate adjacent guards, every
output export's error initialization, short-DER scratch tails, input immutability
and permitted read-only input overlap. They never violate output-disjointness
requirements or fabricate prepared handles.

## Execution and scope

- Native debug and release: 22/22 tests pass in each, including all 484 existing
  Wycheproof cases and the existing comb, scalar and projective arithmetic tests.
- New public encoding fixture: source, IR, lowered IR and generated Wasm pass
  with sanity checks using the unchanged baseline artifact.
- Forced rare-signature regression: baseline fails as intended; fixed reference
  passes 18/18, native passes 2/2. OCaml compilation treats enabled warnings as
  errors. Existing vendored Rust deprecation/attribute warnings remain.
- OpenSSL fixture regeneration check and `git diff --check` pass.
- Integration owns rebuilding both affected reference plugins, their ordinary
  signature/public gates, and the combined 22-method P256 Ash run with forced GC.

`execution.json` records commands and hashes. Large logs remain under `_build`.
An initial new-fixture run caught a tuple-projection parsing error in the test;
the corrected fixture passes. No compiler or native defect caused that failure.

Review also covered SEC1/DER parsing, digest reduction, high-S rules, prepared
and direct paths, native bounds/borrowing, managed output rooting and signing's
secret-dependent operations. Existing round-four evidence already covers rare
x≥n, projective infinity, carry boundaries, exact RFC6979 outputs, scalar
inversion and emitted constant-time table scans; this audit does not duplicate
those corpora or assert a new whole-program constant-time proof. The native
production implementation is unchanged, so no new performance claim is made.
