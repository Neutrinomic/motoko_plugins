# Secp256k1 test coverage

The Ash suite and `tests/run/crypto-secp256k1.mo` execute the same cases from
`tests/lib/Secp256k1Tests.mo`. Both load only the secp256k1 plugin. Ash cases use
update methods so cryptographic validation has the update instruction budget.

| Ash test | Behavior checked |
| --- | --- |
| `test_sec2_points_and_tweaks` | SEC2 generator, compressed/uncompressed SEC1 conversion, small generator multiples, scalar `n - 1`, point addition/multiplication, zero/nonzero tweaks, x-only extraction, odd-Y tweak parity, and fourteen BIP341 secret tweaks including all seven official wallet vectors. Secret tweaks check exact bytes, corresponding public point and subsequent Schnorr signing/verification. |
| `test_scalar_boundaries_and_invalid_sec1` | Secret keys zero or at/above the order, wrong widths, scalar bounds, multiplication by zero, point cancellation, malformed/noncurve/out-of-field SEC1 keys, rejected hybrid encoding and invalid x-only keys. |
| `test_rfc6979_signatures_and_high_s` | Eight independently generated RFC6979/SHA256 signatures, exact low-S compact bytes, deterministic repeat signing, zero/order/maximum digest boundaries, compressed/uncompressed verification, accepted high-S signatures, normalization, exact DER, wrong-message/key rejection and high-S DER round trips. |
| `test_ecdsa_validation_and_strict_der` | Wrong digest/signature lengths, zero and out-of-range ECDSA scalars, minimal positive integers, required leading sign byte, negative integers, redundant leading zeroes, bad tags, truncation, indefinite/nonminimal lengths and trailing data. |
| `test_all_bip340_vectors` | All 19 official vectors, exact signatures where secret keys are supplied, key derivation, valid and invalid verification, odd reconstructed R, infinity, invalid keys, boundary scalars and arbitrary message lengths (0, 1, 17, 32 and 100 bytes). |
| `test_schnorr_input_validation` | Invalid auxiliary randomness, key/signature lengths and field/scalar bounds; zero r/s remain valid encodings whose invalid equations return false. |
| `test_evaluation_order_and_aliases` | Exactly-once left-to-right callee/argument evaluation for ECDSA sign/verify and three-argument Schnorr signing; aliases through records, arrays, generic identity, options and a typed Motoko callback. |
| `test_retained_results_after_allocations` | Retain compressed/uncompressed keys, signatures, DER and odd-parity tweak results across 32 rounds of unrelated calls and approximately 4 MiB of allocation; check deterministic outputs and unchanged source secret. |
| `test_outputs_and_inputs_survive_actor_frame_gc` | Ash-only GC stress retains dynamically allocated secret/digest inputs and plugin-produced keys, signatures, DER, x-only keys and tweaked secrets through persistent actor state, transient actor state and suspended async frames. Sixteen await boundaries, 64 MiB of live arrays interleaved with dead arrays, and a required increase of more than 16 MiB in reclaimed memory prove a collection occurred. Forwarded values are reused for signing, verification, conversion and tweaking. |

The actor-frame GC test is a correctness stress test. Its reported Ash metrics
cover only the final synchronous verification, not allocation, collection or
earlier messages, and must not be treated as a performance benchmark.

## Independent answer sources

Generator and domain parameters are from [Standards for Efficient Cryptography 2
(SEC 2), version 2.0, section 2.4.1](https://www.secg.org/sec2-v2.pdf).
Small generator multiples were independently checked with python-ecdsa.

Secret-tweak answers use all seven `keyPathSpending[0].inputSpending` entries in
the official [BIP341 wallet vectors](https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json):
`given.internalPrivkey`, `intermediary.tweak` and `intermediary.tweakedPrivkey`.
The file downloaded 2026-10-12 has SHA256
`403e19fb81dd1f31e745699216308f61fb403774b2aafa87b631b8f7c042d37f`.
Seven additional fixed scalar cases cover secrets 1, 6 and `n - 1`, including
zero tweaks, odd-Y normalization and a result with odd Y. Their expected scalar
bytes were checked independently using python-ecdsa public-key parity and
`((secret if compressed_key[0] == 2 else n - secret) + tweak) % n`.

Schnorr values are copied from the Bitcoin BIPs repository's
[BIP340 test-vectors.csv](https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv),
downloaded 2026-10-12. The downloaded bytes have SHA256
`34c9d1d9c3a88d524bc80778540dc43f8306ec249a7485293063c376db851c2d`.
Indices 5 and 14 map to `#err(#invalidPublicKey)`, and 12 and 13 map to
`#err(#invalidSignature)` because the public API distinguishes malformed inputs
from a well-formed but incorrect signature. The other invalid vectors return
`#ok(false)`. No acceptance result is weakened or skipped.

ECDSA expected values were generated independently with
[python-ecdsa 0.19.2](https://github.com/tlsfuzzer/python-ecdsa/tree/python-ecdsa-0.19.2),
using [RFC6979](https://www.rfc-editor.org/rfc/rfc6979) HMAC-SHA256 nonce generation.
The RFC itself does not contain secp256k1 signature vectors. Test secrets are
the integers 1, 1, 2, and `n - 1`; respective messages are the ASCII strings
`sample`, `test`, `sample`, and `boundary`. Four further cases use secret 1 and
the exact digests zero, `n - 1`, `n`, and `2^256 - 1`, exercising prehash reduction
and RFC6979 `bits2octets`. Reproduce the fixed compact/DER values with:

```python
import hashlib
from ecdsa import SECP256k1, SigningKey, util

n = SECP256k1.order
inputs = [(secret, hashlib.sha256(message).digest()) for secret, message in
          [(1, b"sample"), (1, b"test"), (2, b"sample"), (n - 1, b"boundary")]]
inputs += [(1, digest.to_bytes(32, "big")) for digest in [0, n - 1, n, 2**256 - 1]]
for secret, digest in inputs:
    key = SigningKey.from_secret_exponent(secret, curve=SECP256k1)
    compact = key.sign_digest_deterministic(
        digest, hashfunc=hashlib.sha256, sigencode=util.sigencode_string_canonize
    )
    r, s = util.sigdecode_string(compact, n)
    high_s = r.to_bytes(32, "big") + (n - s).to_bytes(32, "big")
    print(key.verifying_key.to_string("compressed").hex(), digest.hex())
    print(compact.hex(), high_s.hex(), util.sigencode_der(r, s, n).hex())
```

Expected bytes are committed in the test module; running tests needs no Python
dependency or network. A sign/verify round trip alone is never the acceptance
criterion for known-answer tests.
