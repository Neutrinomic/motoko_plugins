# HMAC test coverage

Public API: `HMAC.sha256`, `HMAC.sha512`, `HMAC.SHA256`, `HMAC.SHA512`,
`HMAC.prepareSha256` and `HMAC.prepareSha512`. Streams implement `Digest`
(`write`, nonconsuming `sum`, and `reset`); reusable keys implement
`PreparedKey` (`digest` and independent `stream` creation).

The package run fixture loads only `hmac-sha2`, which checks module independence.
Its four test functions are also exposed as Ash update methods so instruction
limits for queries do not constrain the binary and boundary cases.

| Ash test | Behavior checked |
| --- | --- |
| `test_rfc4231_all_seven_cases` | SHA256 and SHA512 results from every RFC 4231 case through direct calls, prepared keys, and split incremental input. Covers short and long keys, binary inputs, empty updates and complete output lengths. Case 5 compares the specified 128-bit prefix. |
| `test_empty_binary_padding_and_key_boundaries` | 27 independent answers per hash, including empty keys/messages, the 55/56 and 111/112 padding transitions, key sizes on both sides of 64 and 128 bytes, 131/1024-byte keys and messages up to 4097 bytes. Repeated 63-byte writes cross both hash block sizes. Checks repeated sums and unchanged inputs. |
| `test_stream_lifecycle_and_prepared_key_isolation` | Independent fixed answers for empty, partial and complete messages; nonconsuming sum followed by additional writes; retained results; reset and repeated reset; empty writes; independent streams from a shared prepared key; prepared digest and stream operations interleaved. |
| `test_aliases_callbacks_and_argument_evaluation` | Inferred aliases, records, generic identity, arrays, ordinary callback wrappers and exactly-once left-to-right callee/key/message evaluation for both direct operations. Key expressions for prepared keys and classes run once, including after reset. |

RFC answers come from [RFC 4231 sections 4.2–4.8](https://www.rfc-editor.org/rfc/rfc4231.html)
and were cross-checked with Python `hmac`. Binary inputs use
`bytes((i * 131 + 17) % 256 for i in range(length))`; fixed expected outputs
were generated with `hmac.new(key, message, "sha256").digest()` and
`hmac.new(key, message, "sha512").digest()`. Tests do not calculate expected
MACs through the plugin.

Compile-failure fixtures separately check a non-Blob key and coercion of a
compiler intrinsic to an ordinary function type. The public interface hides
raw state values; malformed raw-state rejection belongs to the plugin tests.

These are functional checks, not isolated timing measurements. They do not
prove constant-time behavior, memory erasure, GC reclamation or arbitrary-input
correctness. Streaming storage bounds follow from the implementation's fixed
hash states and are reviewed separately.
