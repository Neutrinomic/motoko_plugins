# Prepared-key composition coverage

This suite links Ed25519, RSA, ML-DSA, Secp256k1, P256, BLS12-381,
mutable-map and pure-map in one canister. The integration fixture loads the
same eight plugins in reverse order. The Ash configuration enables
`--sanity-checks --force-gc`.

| Coverage | Check |
| --- | --- |
| Caller-owned application state | An account record holds each scheme's prepared public key, Ed25519/RSA/ML-DSA prepared secret keys, and secp256k1 Schnorr public/secret keys. P256 currently exposes prepared public keys only. No handle is serialized, compared for equality or put in stable state. |
| Generic native containers | Insert 96 account records into `mo:fast/Map` and `mo:fast/pure/Map`, then remove 64. This exercises mutable B-tree splitting/deletion and immutable path copying while an earlier pure snapshot remains reachable. Traversal checks IDs and metadata independently. |
| Aliases and closures | Retain records in array aliases and transient actor fields. One callback captures the complete credential record; per-account callbacks capture an Ed25519 secret handle. Verification and signing consume values retrieved by different routes. |
| Collector and message lifetime | Factory inputs are dynamically copied temporary buffers. After 13 asynchronous boundaries and more than 4 MiB of actual reclamation, every prepared public and secret handle remains usable. Exact independent signing answers and native verification detect damaged payloads. |
| Error isolation | Interleave malformed signatures, digest lengths and Schnorr auxiliary randomness across schemes before valid calls. Validly encoded signatures with changed messages/digests/context return `#ok(false)`. |
| Caller releases ownership | Clear both map roots, the preserved snapshot, aliases and the captured callback; then complete another allocation/collection phase. Assert that roots stay empty and that more than 4 MiB was reclaimed after release. |

Each collection phase allocates 72 MiB of disposable arrays over nine
continuations, followed by four settling continuations. This crosses the
current collector's 64-MiB allocation partition. There is one RSA and one
ML-DSA signing operation in the actor method, after collection; expensive
signing and BLS verification are never repeated by the pressure loop.

The integration fixture checks the same application/container operations
and known answers synchronously in the source interpreter, IR interpreter
and compiled Wasm. GC and cross-message claims come specifically from the
Ash actor execution, not the synchronous fixture.

## Independent expected answers

The dedicated [fixture](../../fixtures/PreparedComposition.mo) copies exact
answers already independently validated by the existing signature suites.
It imports no plugin code and generates no expected outputs at runtime.

- Ed25519: RFC 8032 section 7.1, test 2, including seed, public key, one-byte message and signature.
- P256: RFC 6979 appendix A.2.5, SHA-256 of `sample`, including the specified high-s signature.
- Secp256k1 ECDSA: the fixed independently checked answer in [SignatureComposition](SignatureComposition.md), secret scalar 1 and SHA-256 of `sample`. Schnorr: official BIP340 vector 0, scalar 3 and zero message/auxiliary input.
- RSA: the existing package-local [RSA fixture](../../fixtures/RSA.mo), generated independently with Node.js/OpenSSL, including its private CRT test key, modulus, message digest, salt and exact signature.
- ML-DSA: final FIPS 204 NIST ACVP deterministic sigGen group 1, case 4. The source and SHA-256 pin are documented in [SignatureComposition](SignatureComposition.md). The complete 1312-byte public key and 2420-byte signature are preserved.
- BLS: the `icKey0`/`icSig0` `alpha` fixture in [BLS12381](BLS12381.md), produced independently by py_ecc 8.0.0; the reproducible generator and JSON live in `plugins/bls12-381/tests/vectors`.

All secret values are published test keys. They must never protect real data.

## Running and interpretation

Build all eight plugins with the same compiler/SDK, then run:

```sh
scripts/test-ash.sh --ash-source /srv/shared/code/ash PreparedComposition
```

The current round requires private SDK commit `9f6ebeedc` and compiler binary
SHA-256 prefix `24d8d0b`, with matching plugin artifacts. The central
validation report records actual commands and results; adding sources is
not evidence that they have passed.

Ash metrics cover only the final empty-root assertions. These are functional
lifetime tests, not isolated performance benchmarks. The reclaimed counter
proves collection occurred while handles were reachable and after all tested
roots were dropped. It does **not** isolate the handles' reclaimed bytes,
prove absence of hidden references, establish exact live/retained heap, prove
secure secret erasure, or test upgrade persistence. Prepared values are
intentionally nonstable; only transient caller state holds them here.

## Execution in the prepared-key round

On 2026-10-13, the final private SDK compiler above passed the composition
fixture through typechecking, source interpretation, IR interpretation, lowered
IR interpretation, Wasm compilation/validation and Wasm execution. All eight
serializer/cross-plugin rejection fixtures produced the intended M0279/M0096
diagnostics and passed a fresh replay after expectation review. The Ash
composition method passed both reclamation thresholds and all signature,
container, alias and closure assertions. Exact commands, source/artifact/tool
hashes and preserved test-only failed attempts are recorded in the round's
[tracked validation archive](../../../../../tests/integration/prepared-validation/README.md), including timestamped logs.
