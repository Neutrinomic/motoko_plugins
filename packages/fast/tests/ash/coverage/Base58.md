# Base58 and Base58Check test coverage

Public APIs: `Base58.encode(Blob) : Text`, `Base58.decode(Text)`,
`Base58Check.encode(Blob) : Text`, and `Base58Check.decode(Text)`.
The Ash configuration loads only the Base58 and SHA256 plugins. The separate
Base58 public run fixture loads only Base58, checking its independent import.

| Ash test | Behavior checked |
| --- | --- |
| `test_bitcoin_core_vectors` | All 21 Bitcoin Core v29.0 positive vectors in both directions, covering empty input, zero prefixes, all-zero values, the entire alphabet, all 256 byte values, and a digit-carry boundary. |
| `test_strict_alphabet_and_byte_offsets` | Rejection of excluded characters `0OIl`, whitespace, embedded NUL, and non-ASCII text; first invalid UTF-8 byte offset. |
| `test_quotas_and_error_precedence` | Exactly 4096 decoded bytes, rejection above the binary quota, 5653/5654 input-byte boundaries, quota-before-alphabet and alphabet-before-output-quota precedence, UTF-8 byte counting, maximum nonzero Base58 round trip, and maximum 4092-byte Base58Check payload. |
| `test_base58check_fixed_answers_and_errors` | Eight independent fixed answers, including protected empty payload, leading zeroes, address version bytes, the genesis address, compressed/uncompressed secret-1 WIF, and arbitrary binary bytes; too-short, altered checksum, and alphabet errors. |
| `test_aliases_callbacks_and_evaluation_order` | Inferred builtin aliases through records, generic identity, arrays, and options; typed callback wrappers; ordinary Base58Check callbacks; exactly-once left-to-right Base58 callee and argument evaluation. |
| `test_repeated_calls_and_retained_results` | Round trips and retained outputs across repeated allocations and calls at multiple sizes for both APIs. |

Base58 known answers come from
[Bitcoin Core v29.0 `base58_encode_decode.json`](https://github.com/bitcoin/bitcoin/blob/v29.0/src/test/data/base58_encode_decode.json),
distributed under the Bitcoin Core MIT license. The production implementation
rejects whitespace instead of applying Bitcoin Core's optional trimming.

The eight fixed Base58Check answers were generated independently using Python
`hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]`, appending the
checksum, converting the combined big-endian bytes to a Python integer, and
successively dividing by 58 with the Bitcoin alphabet. Initial zero bytes each
produce one `1`. Tests store those answers as literals rather than regenerating
them through the plugins. Checks retain the complete payload including version
bytes. An empty payload is valid only when its four-byte checksum is present.

Compiler run fixtures repeat the known answers and error checks under the
interpreter and compiled backends. Compile-failure fixtures check wrong argument
types and attempts to coerce specialized builtin aliases into ordinary function
values. Trap fixtures cover 4097-byte Base58 and 4093-byte Base58Check encode
inputs. Runtime trap-message checks are part of the golden fixture runner.

Large quota and retention Ash tests use update calls. Their metrics include
setup and assertions and are correctness metrics, not isolated codec benchmarks.
Finite vectors cannot exhaust arbitrary strings or establish a proof of memory
reclamation; the suite does not simulate upgrades or instruction interruption.
