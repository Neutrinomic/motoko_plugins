Independent CBOR audit completed on 2026-10-11. No blocking correctness finding remains in the retained change against `093957a`.

The audit covered the generator, schema validation, reference interpreter, Rust runtime, typed result construction, existing tests, and benchmark actors. The final implementation keeps ABI 1 and the existing representation and limits. It replaces the mutable path string plus length stack with borrowed key/index segments, renders the first error once, initializes the oversized-input error directly, and emits literal byte lengths at compile time.

- Borrowed keys originate only from validated input slices or compiler-emitted labels. They never reference growing output or scalar buffers. The frozen SDK introduces no GC safepoint during these calls; error strings and successful results are copied into managed values before the context is dropped. Array slots are initialized before a decoder can return early, and object fields are evaluated before object allocation.
- JSON Pointer escaping, UTF-8 validation, first-error offsets, missing/duplicate/unknown-field handling, integer and bignum ranges, shortest floats, binary/principal values, options, variants, trailing-input rejection, and byte/item/depth quotas remain intact. No input-dependent validation or output-bound check was removed. Text-key sorting and preferred encodings agree with [RFC 8949 sections 4.2.1–4.2.2](https://www.rfc-editor.org/rfc/rfc8949.html#section-4.2.1).
- `String.length` measures OCaml string bytes, matching the bytes consumed by SDK `Text.lit`/`Blob.lit`. The frozen source grammar permits ASCII identifiers only; Unicode/NUL static labels cannot be expressed. Runtime Unicode/NUL keys are covered by diagnostic fixtures, including `/a/11`, escaped nested keys, and `/a/some`.
- The one-line `reserve(key.len())` is an error-only capacity hint using raw UTF-8 byte length. Escaping can grow beyond that lower bound normally. It adds no representation, validation, or lifetime assumption.

Independent verification passed all 10 Rust tests and all 7 focused Motoko fixtures using the final package. These exercise source/IR/lowered interpreters, Wasm, compile-time rejection, and the forced-GC actor with retained results and an abandoned partial decode. Runtime tests include all 65,536 binary16 patterns, integer bridges, malformed-byte fuzzing, duplicate maps beyond eight keys, and quota/pointer-access failures. The four new diagnostic assertions are silent tests and need no expectation files.

The frozen compiler remained clean at `f1ccbba5e445df9db03bbc35be557187ade9b436`; its executable SHA-256 remained `375484d8cb78891111b1a7c1700ac2bc31e71226b23a11583a5d22d973da1aa8`. Baseline CBOR source hashes match `093957a`, including the preserved package whose build metadata has an older repository revision label. Final source and artifact hashes match the final package.

All 23 plugin workload pairs have matching actor/manifest/runner hashes, exactly three stable trials, matching output hashes, and zero measured reclamation. Instructions and allocated bytes both improve in every pair. The seven edge encoder output hashes were independently recomputed from `cbor2` canonical bytes; decoder inputs come from `cbor2`, with complete retained values checked outside timing. Malformed inputs are rejected independently by `cbor2`, and their queries check the complete typed error.

| Error workload | Baseline instructions | Final instructions | Baseline allocated bytes | Final allocated bytes |
|---|---:|---:|---:|---:|
| 256 KiB key | 21,576,255 | 21,305,590 | 1,574,560 | 525,624 |
| Escaped Unicode key | 2,227,472 | 2,209,586 | 116,288 | 75,096 |
| Nested index | 22,146 | 13,772 | 1,744 | 1,720 |

The final reserve costs about 1.2% more instructions than the intermediate lazy-only implementation on the largest error, while saving another 786,768 allocated bytes; it remains faster than baseline. Successful workloads are unaffected by the reserve. The 1,024-record workloads reduce instructions by 35.84% for encoding and 30.66% for decoding. Raw evidence is in [baseline/final core reports](final.json), [edge reports](final-edges.json), and [error reports](final-errors.json), with their paired baseline files alongside.

The audit found and the owner corrected misleading SHA/Candid fallback wording in the new edge report metadata, then reran those reports. No shared runner or historical result was edited. The separately tracked frozen-compiler actor-local `T1` alias failure reproduces without a plugin and is outside this CBOR change.
