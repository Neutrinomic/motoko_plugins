# Prepared Ed25519 public module coverage

- All five RFC8032 pure-Ed25519 vectors and ten independent OpenSSL vectors.
- Prepared signing exact byte parity and verification, including empty messages.
- Wrong-message false and malformed-signature typed error; recovery reuses handles.
- Factory length, noncanonical/small-order key errors, all-zero/all-ones seeds.
- Function aliases, higher-order calls, shared handle aliases in arrays/records.
- Caller input bytes unchanged and interleaved independent prepared keys.
- Secret/public table handles retained in arrays, records and mo:core/Map over
  forced GC and message boundaries;
  reclaimed bytes must rise by at least 4 MiB, then both handles still operate.
- Separate compile-failure fixtures reject Blob forging, cross-key substitution,
  and extracting prepared secret bytes.

The independent audit corpus additionally checks Wycheproof and mixed-order
acceptance rules, initialized portable payloads, native FFI guards and 64 KiB data.
