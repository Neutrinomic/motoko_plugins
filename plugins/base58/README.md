# Base58

`mo:fast/Base58` provides Bitcoin-alphabet Base58 encoding and strict decoding.
`mo:fast/Base58Check` composes it with the existing SHA-256 plugin, adding and
checking the first four bytes of double-SHA256. Version bytes are part of the
caller-supplied payload; these modules do not interpret Bitcoin networks.

```motoko
import Base58 "mo:fast/Base58";
import Base58Check "mo:fast/Base58Check";
assert Base58.encode("\00\00a") == "112g";
assert Base58.decode("112g") == #ok("\00\00a" : Blob);
assert Base58Check.decode(Base58Check.encode("payload")) == #ok("payload" : Blob);
```

The plain module loads only `base58`; Base58Check also requires `sha256` and
`mo:core`. Empty input and arbitrary leading zero bytes are preserved. Decoding
rejects whitespace and all nonalphabet bytes; unlike the benchmark package,
it does not trim leading/trailing spaces. Invalid character offsets count UTF-8
bytes. Decode failures are typed `#err` values.

Encoding accepts at most 4096 bytes; decoding accepts at most 5653 UTF-8 bytes
and produces at most 4096 bytes. Base58Check's payload cap is 4092 bytes before
the four checksum bytes. Oversized encoding traps before hashing or allocating
scratch. Decoding checks text size, validates the complete alphabet, then checks
the decoded-size limit, in that order. These limits bound quadratic conversion
work and scratch; they are well above Bitcoin addresses and extended keys.

The Wasm64 Rust kernel has no external dependencies, allocator, callbacks, or
retained state. A fresh SDK-allocated Blob supplies initialized scratch; managed
Text/Blob constructors copy the exact result. All pointers are borrowed only
inside the synchronous operation, with no GC safepoint. Conversion processes
four input bytes into base-58^5 limbs, or five Base58 digits into base-2^32
limbs, per batch with proven u64 intermediate bounds. Bounded stack arrays hold
only initialized limb prefixes; small inputs use scalar u64 conversion without
reserving these arrays. The OCaml interpreter is an independent arbitrary-precision conversion.

Positive wire vectors come from [Bitcoin Core v29.0](https://github.com/bitcoin/bitcoin/blob/v29.0/src/test/data/base58_encode_decode.json).
The Motoko comparator is `bitcoin@0.2.1`'s `Base58`/`Base58Check`; conversion to
its `[Nat8]` interface belongs outside primitive timing loops where possible.
