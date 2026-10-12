# BLAKE3 public API coverage

Configuration: `../BLAKE3.ash.json` loads only the BLAKE3 plugin.

- `test_official_vectors_and_streaming`: upstream official digest, keyed-hash,
  context-derived key and 131-byte extended-output vectors; 63/64-byte output
  boundary, 64-byte blocks, 1024-byte chunks, non-power-of-two trees, streaming
  in every mode, unchanged inputs and empty updates.
- `test_errors_canonical_states_and_branching`: malformed key/state errors,
  canonical zero-padding checks, u64 input/seek overflow, output limits and error
  precedence, immutable state branches, UTF-8 and distinct derive-key contexts,
  exactly-once argument evaluation, ordinary callback wrapper.
- `test_all_chunk_boundaries_and_retained_outputs`: incremental splits 1, 63,
  64, 65, 1023, 1024, 1025, and 4096 bytes; retained state/results; XOF seek above
  2^32; one-shot/streaming parity.

Official values are copied from BLAKE3's tagged `1.8.2/test_vectors/test_vectors.json`.
The plugin's Rust fixtures retain all upstream vectors. The interpreter and
Wasm suites independently execute the public checks in `tests/run/crypto-blake3*`.
