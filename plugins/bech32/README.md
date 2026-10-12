# Bech32 and Bech32m

`mo:fast/Bech32` exposes BIP173/BIP350 encode/decode and general bit-group
conversion. `mo:fast/Segwit` composes these primitives with witness-version,
program-length, padding and checksum-variant validation.

```motoko
import Bech32 "mo:fast/Bech32";
import Segwit "mo:fast/Segwit";

assert Bech32.encode("a", "", #bech32m) == #ok("a1lqfn3a");
assert Segwit.encode("bc", 16, "\75\1e") == #ok("bc1sw50qgdz25j");
```

Generic codec data is a Blob of 5-bit values, **not** raw arbitrary bytes.
`convertBits(bytes, 8, 5, true)` produces such groups; the inverse uses
`convertBits(groups, 5, 8, false)` and rejects excessive or nonzero padding.
Bit widths are 1 through 8. Input and output each have a 16 MiB limit.

HRPs are 1 through 83 printable ASCII characters. The complete encoded string
is at most 90 characters. Uniform uppercase input is accepted and normalized;
mixed case is rejected. Encoding always produces lowercase. Generic decoding
returns `{ hrp; data; encoding }`, excluding the checksum from data. Malformed
input returns typed errors, never a deliberate input-validation trap.

Segwit versions are 0 through 16, with program lengths 2 through 40 bytes.
Version 0 requires 20 or 32 bytes and Bech32; later versions require Bech32m.
Segwit decoding returns `{ hrp; version; program }`. Its HRP is intentionally
generic: applications must compare it against their intended network (`bc`,
`tb`, `bcrt`, or another explicitly selected prefix).

The Rust runtime is allocation-free, stateless and dependency-free. Encode and
decode receive 90 bytes of scratch space from SDK-managed allocation and
initialize every byte. Bit conversion validates first, then writes to an
exactly sized managed Blob. No pointer or mutable state survives a call.
The compiler extension contains an independent portable OCaml implementation
for interpreter execution. SDK constructors own all Motoko heap layouts.

Tests use the published [BIP173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki)
and [BIP350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki)
valid/invalid tables, independent conversion expectations, boundary lengths,
case/ASCII validation, output guards and checksum-version mismatch cases.

Build with `scripts/build.sh --motoko ../motoko_sha bech32` from the compiler's
Nix environment. Run native kernel tests with
`cargo test -p motoko-compute-bech32`; public fixtures are in
`packages/fast/tests/run/crypto-bech32.mo` and Ash suite `Bech32`.
