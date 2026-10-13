# RSA test coverage

The nine Ash methods import `mo:fast/RSA` and load only the `rsa` plugin.
The checked-in configuration enables `--force-gc` and `--sanity-checks`.
The ordinary package test additionally exercises all seven operations through
both interpreter and generated Wasm execution.

| Ash test | Behavior checked |
| --- | --- |
| `test_public_key_and_validators` | Exact public modulus from independently generated CRT components through both `derivePublicKey` and `publicKey`; private/public validation; empty, short, long and zero encodings; public top-bit and parity requirements. |
| `test_exact_openssl_prehash_signature` | Exact 384-byte OpenSSL signature using its recovered 32-byte salt; prehash and message verification. |
| `test_exact_openssl_message_signature` | Exact OpenSSL signature from the original message, including its embedded NUL; independently committed SHA-256 digest verifies. |
| `test_mismatches_and_signature_encodings` | Changed message/digest/signature and zero signature return `#ok(false)`; truncated/oversized signatures and signature equal to the public modulus return `#err(#invalidSignature)`; valid verification after failures. |
| `test_lengths_and_error_precedence` | Empty/31/33-byte digest and salt rejection; private/public key before digest before salt/signature; message APIs validate their relevant arguments in order. |
| `test_corrupted_crt_components` | Independent corruption of p, q, dP, dQ and qInv is rejected by private validation, derivation and signing; both factor top-bit requirements; valid recovery afterward. |
| `test_empty_message_and_explicit_salt` | Empty-message hashing agrees with the independent standard SHA-256 empty digest; changing the caller-provided salt produces a different valid signature. |
| `test_aliases_and_argument_evaluation` | Inferred alias, ordinary Motoko callback wrapper, exactly-once left-to-right callee/key/digest/salt evaluation, and retained result integrity after successful and failed calls. |
| `test_retained_outputs_across_await_and_forced_gc` | Dynamic private-key/digest/salt copies and returned public-key/signature Blobs survive through a persistent actor field, continuation locals and array aliases; 13 asynchronous boundaries, later outputs, error paths, observed heap growth and over 4 MiB of confirmed reclamation; signing with retained dynamic inputs again matches the exact signature after collection. |

The fixture module is generated directly from
[`plugins/rsa/vectors/openssl3072.json`](../../../../../plugins/rsa/vectors/openssl3072.json).
It contains a **public test key**, never a production secret. Node.js/OpenSSL
independently generated the RSA-3072 key and SHA-256 PSS signature using
public exponent 65537 and a 32-byte salt. The public RSA operation and MGF1
recovered that signature's salt, allowing exact deterministic comparison.
Expected signatures were not produced by this plugin. The profile follows
[RFC 8017 sections 8.1 and 9.1](https://www.rfc-editor.org/rfc/rfc8017.html#section-8.1).

The GC method first places dynamic private-key, digest and salt copies behind
1 MiB of dead heap data, so input roots are movable rather than static fixture
Blobs. It then allocates 72 MiB of disposable arrays over nine continuations,
followed by four settling continuations. Crossing a 64-MiB allocation
partition makes the original output partition eligible for evacuation with
the current collector. `rts_reclaimed()` must increase by more than 4 MiB;
allocation alone is not accepted as collection evidence. `rts_heap_size()` is
sampled during allocation to confirm pressure. After confirmed collection,
signing again with the copied inputs retained in the actor field must reproduce
the exact OpenSSL signature. This checks input and managed-result retention
during real collection, not every possible GC schedule or upgrades.
The method's returned Ash metrics include only final validation, excluding
allocation pressure and asynchronous phases. No correctness test metrics
should be presented as isolated RSA performance measurements.

Bulk Wycheproof and deliberately malformed EMSA-PSS cases belong to the
runtime's separate vector suite. These public Motoko cases focus on the
compiler boundary, typed results, module aliases and managed output lifetime.
Private-key validation proves the documented encoding and CRT congruences;
it does not prove the imported factors prime.

Run after building the matching package:

```sh
scripts/test-ash.sh --ash-source /srv/shared/code/ash RSA
```

Validated on 2026-10-13: all nine Ash methods passed with the checked-in
configuration, including the observed-GC assertion. The targeted package
`crypto-rsa.mo` test also passed through `test-runner` against the matching
plugin-enabled compiler. Independent crypto audit evidence is retained in
[`tests/crypto-audit/round3/rsa`](../../../../../tests/crypto-audit/round3/rsa/README.md).

The prepared-key candidate was independently retested on 2026-10-13: all nine
direct Ash methods and the ordinary package test passed with its selected
window-five runtime. [Prepared coverage](RSAPrepared.md) records the exact
SDK and artifact hashes, alongside the eight prepared methods and six
nominal-type rejection cases.
