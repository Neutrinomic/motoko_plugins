# MLDSA test coverage

The 17 Ash update methods import `mo:fast/MLDSA` and load only `ml-dsa`.
They use final FIPS 204 ML-DSA-44, pure external message/context framing, a
32-byte secret seed, 1312-byte public keys and 2420-byte signatures. The checked-in
configuration enables `--sanity-checks --force-gc`.

| Ash test | Behavior checked |
| --- | --- |
| `test_official_key_generation` | Three exact NIST seed-to-public-key answers; all-zero and all-one seeds are valid. |
| `test_official_deterministic_*` | Three exact official signatures, covering a one-byte message, empty context, and 8192-byte message with a 255-byte context. Deterministic signing equals randomized signing with zero randomness. |
| `test_official_randomized_*` | Three exact official signatures using supplied 32-byte randomness, covering a one-byte message, empty context and a 255-byte context. |
| `test_official_verification_1` … `_5` | All 15 official pure external verification cases: valid signatures and independently modified message, commitment, z and hint cases. |
| `test_input_lengths_and_error_precedence` | Empty, short, long and expanded secret inputs; public-key/signature lengths; 256-byte context rejection; randomness lengths; secret-before-context-before-randomness and public-before-signature-before-context precedence; recovery after errors. |
| `test_context_message_and_randomness_binding` | Wrong message, context and public key reject; nonzero randomness changes the signature without changing its validity; empty message/context signatures are deterministic and valid. |
| `test_noncanonical_hints_and_out_of_bound_z` | Hint count overflow, decreasing counts, duplicate positions, nonzero unused padding, z norm boundary, all-zero/all-one signatures return typed `#ok(false)`. |
| `test_aliases_argument_order_and_retained_outputs` | Function aliases, generic identity, array storage, exactly-once left-to-right argument evaluation, retained results through later successful/error calls. |
| `test_outputs_survive_await_and_confirmed_collection` | Independently retained public-key and signature buffers plus aliases survive 13 awaits, subsequent plugin calls and more than 4 MiB of observed reclamation after 72 MiB disposable allocation. |

All expected bytes come from the pinned official NIST ACVP corpus under
[`plugins/ml-dsa/tests/vectors`](../../../../../plugins/ml-dsa/tests/vectors/README.md),
with an extraction script, source hashes and exact selected IDs. The full native
Rust suite checks all 25 keygen, 30 signing and 15 verification answers, plus API
boundaries, context/message/key binding, structured malformed encodings, 66
signature mutations and native output-buffer guards. The independent OCaml
reference is tested separately against the same official answers.

`tests/run/crypto-mldsa.mo` checks key derivation, deterministic and randomized
known answers, valid/invalid verification, typed failures and aliases through
the interpreter/Wasm test runner. It is intentionally smaller than Ash because
reference interpretation is slower.

Ash metrics include assertions and fixture work; use the isolated signature
benchmarks for performance comparisons. The GC test's returned metrics cover
only final validation, excluding its asynchronous allocation/collection phases.
This suite does not prove constant-time behavior, every GC schedule, secret
storage protection, canister upgrade behavior or NIST validation of the plugin.

## Validation

On 2026-10-13, all **7 native Rust tests passed** in release mode with Rust
1.99, including every one of the 70 official known answers. The independent
OCaml reference also matched all 70 official answers. The public Motoko run
fixture passes `moc --check` against the built plugin.

Interpreter/Wasm and Ash execution remain pending; typechecking is not counted
as execution.
