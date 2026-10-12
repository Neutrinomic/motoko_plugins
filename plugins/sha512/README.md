# SHA-512 and SHA-384

Import `mo:fast/SHA512` with the `sha512` plugin loaded. `digest` returns a
64-byte SHA-512 digest; `digest384` returns a 48-byte SHA-384 digest using its
separate initial values.

```motoko
import SHA512 "mo:fast/SHA512";
let stream = SHA512.Digest();
stream.write("a");
stream.write("bc");
assert stream.sum() == SHA512.digest("abc");
stream.write("d"); // sum() does not consume the stream.
stream.reset();
```

`Digest384` has the same `write`, `sum`, and `reset` methods. Streaming retains
216 bytes independent of message length. Every update produces a fresh managed
state Blob and borrows its input only within one synchronous operation. No
runtime state, input pointers, host calls, or allocator are retained. Finalizing
returns a fresh managed digest and preserves the stream. Byte-aligned messages
must contain fewer than 2^125 bytes; `write` traps on exceeding that limit.

The canister runtime uses pinned RustCrypto `sha2` 0.10.9 without default
features, including its SHA-512 compression primitive. Source and IR
interpreters use an independent portable OCaml implementation of FIPS 180-4.
SHA-384 and SHA-512 share only the compression function. Empty one-shot inputs
use their fixed known answers. Complete message blocks are passed to the
upstream compressor in batches; shared one-shot padding and output code avoid
duplicating higher-level hash wrappers. Streaming validates unused buffer bytes
in machine words and writes its canonical state and digest directly into fresh
output Blobs, avoiding temporary serialized copies.

Internal Prim state functions (`sha512_init`, `sha512_init384`,
`sha512_update`, `sha512_sum`, `sha512_sum384`) are implementation details.
Update and sum return `null` for malformed states. The canonical state encoding
is 216 bytes: `S512`, one digest-size byte (48 or 64), three zero bytes, eight
big-endian 64-bit chaining words, an unsigned big-endian 128-bit byte count, and
a 128-byte tail whose unused suffix is zero. Before the first block, chaining
words must equal the selected initial values. States are not authenticated;
callers should keep them private as the public classes do.

Native tests cover NIST known answers, million-byte messages, SHA-384's separate
IV, padding boundaries, partition invariance, nondestructive output, invalid
states, 128-bit carry and overflow, pointer alignment, and output guards. Public
Motoko and Ash tests exercise the module and independent `hashlib` vectors.
