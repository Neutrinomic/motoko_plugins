# ML-DSA round-four optimization

Two small changes reduce instructions without changing the API, prepared key
layout, signatures, validation rules, arithmetic, or SDK. Matrix sampling reads
one SHAKE128 rate block at a time instead of three bytes per candidate. Prepared
key decoding fills an initialized vector directly instead of building nested
arrays with redundant generated copies.

The final candidate is source `f4da0c8`, runtime
`d2ad769ca27e92e62d74f9e3a185fc5d4459964b5f0525cc817ab64c102af869`.
The delivered baseline is `0e1e96a`, runtime `07ae7543`. Both use SDK
`9f6ebeedc`, exact compiler executable `24d8d0b9`, unchanged RTS, actors and
NIST ACVP expected bytes. Three fresh PocketIC canisters run each case and
revision. The final comparison covers 25 cases and 150 fresh-canister
observations, plus 39 observations isolating the first candidate. Every exact
official answer passed. All three instruction observations in each measured row
are identical.

## Measured screen

Official case 4 has a one-byte message and 59-byte context. These are whole
one-call intervals; signing includes seed expansion in the direct row and
excludes separately measured preparation in the prepared row.

| Operation | Previous instructions | Final instructions | Reduction |
|---|---:|---:|---:|
| Public key from seed | 5,107,151 | 4,952,706 | 3.02% |
| Direct sign | 13,193,656 | 13,039,211 | 1.17% |
| Prepare secret key | 5,016,889 | 4,862,444 | 3.08% |
| Prepared sign | 9,076,804 | 8,890,133 | 2.06% |
| Direct verify | 3,810,844 | 3,656,399 | 4.05% |
| Prepare public key | 2,525,559 | 2,371,114 | 6.12% |
| Prepared verify | 1,920,986 | 1,787,636 | 6.94% |

For the 1,188-byte case 6, prepared signing drops
from 21,885,571 to 21,698,900 instructions (0.85%). Prepared verification drops
from 2,016,127 to 1,882,777 (6.61%). These are fixed official inputs, not a
universal estimate of signing cost; FIPS 204 rejection sampling varies by input.
Signing retry counts were not instrumented.

Separating the candidates makes attribution explicit. Rate-block sampling saves
154,445 instructions on each screened operation that expands a matrix, while
prepared hot controls remain identical. Direct vector decoding then saves 186,671 per
prepared sign and 133,350 per prepared verify on both fixtures, while direct and
factory controls remain identical. It does not reduce Keccak permutations.

The final addendum covers an 8,192-byte message with a 255-byte context (case 11)
and hedged signing with explicit randomness (case 362). Prepared signing changes
from 4,652,024 to 4,465,353 instructions in case 11 (4.01%), and 14,226,247 to
14,039,576 in case 362 (1.31%). Prepared verification improves by 5.17% and
6.72%, respectively. Reader savings remain exactly the same; matrix-sampling
savings are 154,369 for case 362, illustrating their dependence on the seed's
coefficient rejection pattern.

Across all four fixtures, direct signing improves by 0.59–1.76%, prepared
signing by 0.85–4.01%, direct verification by 3.45–4.05%, and prepared
verification by 5.17–6.94%.

Full matched tables and raw/source-pinned evidence:

- [Original → final](../results/prepared-round4-mldsa-c2-candidate/comparison-baseline.md)
- [Rate-block sampling alone](../results/prepared-round4-mldsa-c1-candidate/comparison.md)
- [Vector decoding alone](../results/prepared-round4-mldsa-c2-candidate/comparison-incremental.md)
- [Large message and hedged signing](../results/prepared-round4-mldsa-finalextra-candidate/comparison.md)

## Memory and generated code

Allocation is unchanged: 2,480 bytes per signing result, 32 per verification
result, 28,856 for secret preparation, and 20,632 for public preparation. Cache
payloads remain 28,800 and 20,576 bytes. These allocation measurements are not
peak or retained-live-heap claims; the unchanged layout retains the earlier
[independently reviewed GC and paired occupied-heap evidence](../../prepared/ml-dsa/report.md).

Conservative additional Wasm shadow-stack bounds improve from 121,312 to
104,960 bytes for prepared signing and 138,624 to 114,048 for prepared verification. The overall
maximum becomes 137,984 bytes, in direct signing; other direct/factory bounds
are unchanged. Independent emitted-Wasm analysis covers all 38 functions and
159 calls without imports, recursion or indirect calls.

Runtime Wasm grows from 123,026 to 123,611 bytes (585 bytes). The redundant
1,024-byte vector copy chains disappear; 4,096-byte result copies and existing
matrix construction copies remain. This is a bounded decode simplification,
not elimination of every cache copy.

## Correctness evidence

Native debug and release suites each pass all ten groups, including official
keygen, deterministic and hedged signature bytes, verification, prepared parity,
malformed signatures, context/error boundaries and guarded unaligned ABI inputs.
Two sampler tests compare 1,024 seed/nonce/mode combinations with the previous
three-byte reader and explicitly exercise rejections before/after rate-block
boundaries and in the final partial block.

The source-level design and primary references are in [proposal.md](proposal.md).
[Native logs and artifact pins](native/candidate2-validation.json) retain exact
commands and initial isolated vendor-test setup failures. The independent audit
passes three private sampler/decoder tests in debug and
release, reruns all ten native groups in both modes, and passes the two public
run fixtures plus its independently authored fixture through every engine. Its
[review and raw evidence](../../../../tests/crypto-audit/round4/ml-dsa/) cover
rate-block boundaries, signed unaligned decoding, production dependency pins,
Wasm stack bounds and unchanged validation semantics. No production issue was
found. Earlier actual-GC retention evidence applies to the unchanged prepared
representation; this round adds no new retained-heap claim.
