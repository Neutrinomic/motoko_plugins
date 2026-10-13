# P256 independent vectors

`encoding.json` contains focused OpenSSL encoding answers from
`generate-encoding.py`. Its 133 scalar pairs cover every DER output length from
8 through 72 bytes, the positive INTEGER sign-octet transition at every scalar
byte width, and normalization immediately below and above half the order.
OpenSSL's ASN.1 generator supplies the exact DER bytes. Its EC decoder supplies
28 compressed SEC1 membership/coordinate answers around zero, the scalar order
and the field prime, including both roots where a point exists. Regenerate with
`python3 generate-encoding.py --openssl /path/to/openssl`; `--check` checks both
the JSON and generated public Motoko fixture without writing them. The recorded
OpenSSL version is part of the fixture provenance.

Native tests check strict decoder errors independently of verification and
mutate sequence/integer lengths, required/redundant sign padding, truncations
and trailing bytes. The shared public `P256EncodingTests.mo` runs through both
the ordinary Motoko suite and Ash, including all SEC1 tags and truncations.
FFI tests separately cover byte offsets 1 through 8, exact output capacities,
zero initialization on errors, DER scratch tails, immutable input buffers and
permitted overlap between read-only verification inputs.

`wycheproof-ecdsa-secp256r1-sha256.json` is an unmodified copy of C2SP Wycheproof's
`testvectors_v1/ecdsa_secp256r1_sha256_test.json` at commit
`878e5366008753df2064d40c49f8e2f50f9c6af7` (484 test cases).

- [Pinned source](https://raw.githubusercontent.com/C2SP/wycheproof/878e5366008753df2064d40c49f8e2f50f9c6af7/testvectors_v1/ecdsa_secp256r1_sha256_test.json)
- SHA-256: `182db4f3e230f6f9fa9f800d2a614dede30284b8e8438bbfe1171905402e9332`
- License: Apache 2.0, preserved in `LICENSE.wycheproof` from the same commit.

The native runtime suite reads the full corpus. Public Motoko tests select 65
cases recorded in `selected-wycheproof-ids.json`: the first occurrence of every
flag/result pair plus additional signature malleability, ASN.1 length,
arithmetic, point duplication, infinity and unusual-coordinate cases.

The Motoko vectors use the corpus's uncompressed public keys and DER signatures
without alteration. Their 32-byte prehashes are independently computed using
Python `hashlib.sha256(bytes.fromhex(msg)).digest()`. Strict DER parsing of the
fixture supplies expected compact R/S bytes; scalar values must satisfy
`0 < scalar < n`. An invalid DER or scalar is a typed error; a valid encoding
whose ECDSA equation fails returns `#ok(false)`.

The RFC signing/key vectors in the Motoko suites are from
[RFC 6979 A.2.5](https://www.rfc-editor.org/rfc/rfc6979.html#appendix-A.2.5).
No Mops implementation supplies expected cryptographic answers.

`rfc6979-digest-boundaries.json` adds exact signatures for prehashes zero,
`n - 1`, `n` and `2^256 - 1`. Regenerate it with
`python generate-rfc6979-boundaries.py` in an environment containing
`cryptography==46.0.3`. The script validates the RFC appendix's `sample` and
`test` vectors, then independently calculates RFC6979 nonces using Python HMAC
and the ECDSA scalar equation using Python integers. OpenSSL derives nonce
points and separately performs deterministic ECDSA signing; the two paths must
produce identical signatures. The committed fixture records the library and
OpenSSL versions used.

RFC6979 [section 2.3.4](https://www.rfc-editor.org/rfc/rfc6979.html#section-2.3.4)
requires `bits2octets` hash reduction, which is used to seed the nonce generator
in [section 3.2](https://www.rfc-editor.org/rfc/rfc6979.html#section-3.2).
For these equal-width P-256/SHA256 values, this is reduction modulo `n`.
Consequently digest `n` and digest zero must produce identical signatures.

`generate-p256-comb.py` independently verifies the selected secret comb in
`runtime/src/secret_table.rs`. It reads that file's `TABLES` and `ROWS`
constants; the chosen format has four tables of 15 points and 16 rounds.
Table `t` contains the nonzero combinations of
`2^(16*t) G`, `2^(16*t+64) G`, `2^(16*t+128) G` and `2^(16*t+192) G`.
The generator checks the complete array dimensions and canonical Montgomery
coordinates, then requires every point to equal both independent Python
integer arithmetic and OpenSSL's public-key derivation for its exact scalar.
Regenerate the proof from this directory with
`python3 generate-p256-comb.py --output p256-comb-proof.json`; supply
`--openssl /path/to/openssl` when needed. `p256-comb-proof.json` records the
runtime table and generator hashes, dimensions, exact coefficients, encoded
points, Montgomery words and OpenSSL version. Each point stores `xR` and `yR`
modulo the field prime, with `R = 2^256` and four little-endian u64 limbs per
coordinate. All 60 public constants occupy 3,840 bytes of immutable data.
This checks table values; it does not establish constant-time behavior.
The runtime executes 16 doublings and 64 complete mixed additions, scanning
all 15 entries for every selection, including zero digits.
The native runtime also compares the comb against upstream multiplication for
1,284 zero/boundary, single-bit and deterministic SHA-256-derived scalars, and
checks compressed and uncompressed SEC1 outputs.

The scalar inversion uses a fixed addition chain for `n - 2` with 254
squarings and 38 multiplications, adapted from Go's implementation of Brian
Smith's chain. The [source proof](../../../../benchmarks/crypto/round4/p256/scalar-chain/verify-chain.py)
interprets the checked-in exponent schedule with Python integers. Scalar
squaring uses the pinned `crypto-bigint` symmetric wide square and the existing
Barrett reduction. Runtime tests compare inversion with generic binary
exponentiation, compare square with multiplication, and check inverse products
for nonzero scalars and the rejected-zero result separately.

Direct and prepared verification compare the resulting homogeneous point's
X coordinate without affine inversion. They reject infinity, compare
`X = r*Z`, and also compare `X = (r+n)*Z` only when `r+n < p`.
The second representative matters because `n < p < 2n`.
The [projective-check fixtures](../../../../benchmarks/crypto/round4/p256/projective-check/)
cover the rare second representative and the range boundary using independent
Python arithmetic. This verification path handles public inputs only.

`generate-prepared-comb.py` emits the private public-key comb table and matching
compiler output capacity together. It checks every generated point against
independent Python arithmetic and OpenSSL scalar multiplication, then encodes
canonical Montgomery coordinates with explicit little-endian u64 limbs.
The same proof includes the eight fixed odd multiples of G used by direct
verification. The generator now emits only the selected width-eight format. Frozen benchmark
inputs preserve the bounded comparison of widths 4, 6 and 8.
`prepared-comb-proof.json` records the chosen table, exact coefficients, words,
tool version and generated-source hashes. Runtime tests compare every point
and prepared linear combinations against upstream arithmetic, and run all
484 pinned Wycheproof cases through both direct and prepared verification.
