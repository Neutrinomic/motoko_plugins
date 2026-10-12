# RIPEMD-160

`mo:fast/RIPEMD160` supplies RIPEMD-160 hashing, including bounded-state streaming.
Load only the `ripemd160` plugin to use this module.

```motoko
import Hash "mo:fast/RIPEMD160";

let oneShot = Hash.digest("abc"); // 20-byte Blob
let stream = Hash.Digest();
assert stream.write("ab");
assert stream.write("c");
assert stream.sum() == oneShot;
```

The immutable API is `init() : Blob`, `update(state, data) : ?Blob`, and
`finalize(state) : ?Blob`. Update returns a fresh 104-byte state. Finalize
preserves its input, so callers can finalize repeatedly, extend an existing
prefix or branch it. Null indicates malformed state or, for update, a message
longer than `2^61 - 1` bytes. The `Digest` class retains a state internally;
`write` returns false and preserves its state if that byte limit is exceeded.
`sum` preserves the state and `reset` starts a new hash.

State bytes are canonical and portable across the interpreter and Wasm kernel.
They are opaque application data, not authenticated evidence that an input
prefix was hashed. Layout: ASCII `R160`, four zero reserved bytes, LE64 total
bytes, five LE32 chaining words, four zero reserved bytes, and a 64-byte pending
buffer whose unused bytes are zero. The pending count is total modulo 64.
States before the first full block must contain the standard initial words.

The runtime uses pinned RustCrypto `ripemd` 0.2.0 with default features disabled.
It has no allocator, mutable globals or retained pointers. Borrowed Blob inputs
are read only; output is initialized completely, including rejected calls.
Serialization explicitly maps the pinned crate's serialized fields to the
plugin encoding, without depending on Rust object layout. Scratch space is
constant in input length. The compiler allocates only the digest/state Blob
and an optional result wrapper. The interpreter has a separate portable OCaml
compression implementation.

Build with `scripts/build.sh --motoko /path/to/motoko ripemd160`. Native kernel
tests cover the [authors' official vectors](https://homes.esat.kuleuven.be/~bosselae/ripemd160.html),
independent OpenSSL binary answers, padding/block boundaries, partitioning,
state validation, length overflow, input preservation and unaligned pointer
guards. Public API fixtures are in `packages/fast/tests/run/crypto-ripemd160.mo`
and `packages/fast/tests/ash/RIPEMD160.mo`.

For Bitcoin HASH160, compose `RIPEMD160.digest(SHA256.digest(data))`; the
composition requires both plugins. The comparison baseline is
[`bitcoin@0.2.1/Ripemd160`](https://mops.one/bitcoin), whose public API accepts
and returns byte arrays. Benchmarks must account for that representation
difference explicitly.

The measured implementation has an immediate empty-message result and a
32-byte specialization for Bitcoin's SHA-256 digest input. Three PocketIC
trials reduced empty-message instructions from 4,222 to 436 and 32-byte hashing
from 4,327 to 3,845 (11.1%). General inputs add 19 dispatch instructions; result
allocation remains 48 bytes and the benchmark canister grows by 431 bytes.
The 64-, 1,024- and 16,384-byte public Blob workloads use approximately one tenth
the instructions of Bitcoin's array implementation with its input/output
conversions included. The [recorded benchmark results](../../benchmarks/crypto/results/ripemd-native-candidate/results.json)
retain exact outputs, source/artifact hashes and measurement methodology.
