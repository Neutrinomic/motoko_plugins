# Crypto audit round five

All eight audit lanes and central validation passed. Three demonstrated issues
were fixed, with failing-before/passing-after regressions and independent
production-code review:

- **BIP340 nonce reduction:** signing rejected nonce hashes at or above the
  curve order instead of reducing them modulo the order before rejecting zero.
- **BIP340 zero signature scalar:** the signature representation rejected
  canonical `s = 0`, which the signing equation can validly produce.
- **Portable ECDSA error parity:** the shared P256/Secp256k1 interpreter signer
  retried a valid nonce whose signature had zero `r` or `s`, while both native
  signers returned `invalidSignature`. The reference now follows the existing
  documented native policy. This is contract parity, not an additional RFC6979
  compliance claim.

The behavior changes are confined to the shared portable ECDSA signer and
vendored BIP340 signing/signature representation. The SDK, original RTS,
ABI 1, public APIs and prepared-key layouts are unchanged. Other lanes found no
production defect. A separate test configuration fix corrects
`PreparedComposition`'s Core dependency path so the normal Ash runner works
without the previous temporary dependency link.

## Added coverage

| Lane | New coverage and detailed evidence |
| --- | --- |
| [Ed25519](ed25519/README.md) | Hash-prefix padding, mixed-order torsion, ctx/ph separation, sign-bit mismatches and guarded unaligned FFI. |
| [Secp256k1](secp256k1/README.md) | Independently forced rare BIP340 paths, hash padding, error precedence and FFI boundaries. |
| [P256](p256/README.md) | DER lengths/padding, SEC1 encodings, normalization boundaries, guarded outputs and forced portable/native ECDSA error parity. |
| [RSA](rsa/README.md) | Independent malformed PSS, aliased immutable inputs, unaligned bytes, error precedence and 99 importer cases. |
| [ML-DSA](ml-dsa/README.md) | Mathematically equivalent noncanonical hints, binary context framing, encoding extremes and all FFI offsets. |
| [BLS12-381](bls/README.md) | Ciphersuite/PoP domains, message framing, DST normalization and prepared-key type boundaries. |
| [Hashes/HMAC](hashes/REPORT.md) | Independent varied inputs, BLAKE3 context/tree boundaries, stream forks and prepared state across confirmed GC. |
| [Bitcoin](bitcoin/report.json) / [codecs](bitcoin/codecs/REPORT.md) | BIP32 derivation relations, sighash commitments, parser boundaries, bit-conversion and checksum mutations. |

## Central validation

[Commands and results](validation.json) supplement the narrower lane runs:

| Gate | Result |
| --- | --- |
| Cargo workspace | 184 tests passed. |
| Registered independent native adapters | All five passed, including forced rare paths, independent oracles, sanitizer checks and importer cases. |
| Build configuration | 4 tests passed. |
| Fixed-plugin/public composition | 5 source/IR/lowered-IR/Wasm fixtures and 8 nominal rejection fixtures passed; packaging and expectation checks passed. |
| Ash/PocketIC | 76 methods across 11 selected suites passed, including new cases and confirmed collection with retained prepared keys. |
| Focused Secp256k1 performance | 11 matched workloads, 33 new successful observations; unchanged strict comparison validator passed. |

The [artifact inventory](artifacts.json) checks every source and artifact pin
for all 23 packages. Existing build manifests conservatively pin every workspace
runtime source, so the new tests/fixes required rebuilding 16 runtime-backed
packages; seven compiler-only packages reused their exact artifacts. **15 of 16
runtime Wasms remain byte-identical**; only Secp256k1 changes. Rebuilt OCaml
plugins include checkout paths and therefore have new binary hashes. No compiler
or RTS rebuild occurred.

## Cost of the correctness fixes

[Recorded measurements](performance.json) reuse the unchanged round-four
11-workload actor set and its baseline observations, with the same compiler,
RTS, dependency identities and independent expected outputs. Three fresh
canisters per workload produced identical instruction/allocation triples.

| Operation | Before instructions | Current instructions | Delta |
| --- | ---: | ---: | ---: |
| BIP340 direct sign | 2,681,364 | 2,681,582 | +218 |
| BIP340 prepared sign | 1,375,272 | 1,375,508 | +236 |
| Prepare BIP340 secret | 1,308,308 | 1,308,292 | -16 |

The other eight measured operations and all allocations are unchanged. Runtime
Wasm grows **875 bytes** (180,910 to 181,785); each measured canister grows
872 bytes. Current root README costs are updated; historical round-four reports
remain unchanged. An initial successful 33-observation run captured additional
unused actor files, which the strict comparator rejected. The final cohort uses
the original frozen actor directory and passes that comparator; no crypto output
failed in either run.

## Running the regressions

Use the selected compiler's Nix environment and matching `dist/` artifacts:

```sh
scripts/test.sh --motoko /path/to/sdk
scripts/test-ash.sh --ash-source /path/to/ash
```

The existing native runner executes Cargo workspace tests, then each
`tests/crypto-audit/round5/*/run-native.sh` adapter. These adapters retain required
independent-oracle dependencies, backend flags and rare-case harnesses. Public
fixtures use normal plugin/package `tests/run` directories; new Ash configurations
live with the existing public suites. RSA's CLI oracle requires OpenSSL on
`PATH`, or `OPENSSL=/path/to/openssl`. Lane reports provide narrower commands.

Raw logs and generated binaries remain under ignored `_build/` and `_out/`.
Forced rare cases use controlled seams in temporary copies of production source;
they are not natural hash-preimage witnesses. Correctness-test heap/instruction
figures are not isolated performance results, and reclamation checks do not
establish exact retained heap or secure erasure. These finite regressions and
internal reviews are not an external cryptographic audit or a whole-program
timing proof.
