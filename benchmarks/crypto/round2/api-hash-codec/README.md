# Complete hash and codec public API workloads

`api-inventory.json` maps all **60 public callables** in SHA256, SHA512, RIPEMD160, BLAKE3, HMAC, Base58, Base58Check, Bech32 and Segwit to exact-oracle measurements. This includes every stream constructor, write, sum and reset, prepared HMAC key creation, digest and stream factory, and methods on streams returned by that factory. Constant and type exports are not operations.

`suite-cases.json` contains the referenced existing and new actor fixtures. In manifest implementation labels, `native` means the plugin implementation, inherited from the original harness; the report's **Native** column means pure Motoko. Use `plugin_case` and `native_case` from the inventory rather than deriving that distinction from labels.

Every isolated method fixture prepares inputs and existing state outside its counter interval. The named operation and assignment are timed. A separate query checks independently expected output bytes, and where relevant checks preserved state, repeated sums, continued writes, or independent streams. State constructors are checked by finalizing in that untimed query. Resets begin with an existing populated stream and are checked against the empty-message digest. Inputs use Python hashlib/hmac, the retained official BLAKE3 vectors, integer Base58 conversion and double SHA256, or the existing independent BIP173/BIP350 oracle.

The pure Motoko HMAC counterpart composes public APIs from pinned `sha2` 0.1.14. It precompresses RFC2104 key pads, takes immutable snapshots with `share`, and clones them through `unshare`. This preserves reusable prepared keys, independent streams, reset and non-destructive sum. The pinned `bitcoin/Hmac` implementation consumes its receiver during `sum`, so it remains a valid direct one-shot counterpart but does not implement those reusable methods. The inline composition is archived in every actor that uses it.

SHA512 and SHA384 also clone the pure Motoko digest within the timed interval for a semantically equivalent non-destructive sum. Bitcoin RIPEMD exposes no immutable-state API or snapshot clone, so its raw state methods and non-destructive sum have no native counterpart. BLAKE3 uses the public immutable `Hasher` methods for correct single-chunk workloads. Native cells remain empty for derivation (the pinned package ignores its context) and the 100-byte seeked XOF (it truncates at the first output-block boundary). Bech32 bit conversion has no public counterpart in the pinned Bitcoin package. Full decoded Segwit output preserves HRP, version and program; the native encoder additionally round-trips its output through decode.

Regenerate and validate:

```sh
python3 benchmarks/crypto/round2/api-hash-codec/sha-ripemd/generate.py
python3 benchmarks/crypto/round2/api-hash-codec/generate.py
python3 benchmarks/crypto/round2/api-hash-codec/assemble.py
python3 benchmarks/crypto/round2/api-hash-codec/sha-ripemd/check.py
python3 benchmarks/crypto/round2/api-hash-codec/check.py
```

The parent round-two harness freezes sources and artifacts and executes three fresh-canister trials per case after final candidate promotion. Local compile checks here establish buildability and do not claim measured performance or successful execution.
