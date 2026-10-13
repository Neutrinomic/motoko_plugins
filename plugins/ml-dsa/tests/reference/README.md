# Portable interpreter checks

Run from any directory with Python 3.9+ and OCaml available:

```sh
python3 plugins/ml-dsa/tests/reference/check.py
```

Use `--ocamlopt /path/to/ocamlopt` to select the compiler. The script creates
and removes its own temporary build directory and needs no third-party Python
or OCaml packages. It reuses the pinned official external vectors in
[`../vectors/acvp-ml-dsa-44.json`](../vectors/acvp-ml-dsa-44.json); source URLs
and the upstream commit are recorded there.

The checks exercise:

- 25 public keys derived from seeds, 30 exact deterministic or randomized
  signatures with contexts, and 15 positive/negative verifications from the
  official external-interface corpus. Each generated signature is also verified.
- SHAKE128/SHAKE256 against Python `hashlib`, including both sponge rates,
  empty input/output, multi-block data, and fragmented output reads.
- The actual `Reference.evaluate` adapter, all five typed errors and their
  precedence, all four successful operations, wrong messages and wrong contexts.
- A one-bit mutation in each of the 2,420 signature bytes. Every verification
  must return `#ok(false)`, including malformed hint encodings.
- All 256 permitted context lengths with an empty message.
- Prepared-key adapters against every signing and verification vector, the
  signature mutations, factory errors and consumer error precedence. Interleaved
  reuse of two key pairs verifies that no message state survives between calls.

The adapter is compiled against minimal `Mo_values.Value` constructors and
the SDK's prepared Blob representation/registration contract. This script
validates reference behavior without requiring a Motoko compiler installation;
the stubs do not implement nominal type checking. Full plugin tests separately
exercise actual SDK loading, type rejection, and interpreter values.

Prepared reference payloads privately retain the original canonical public key
or secret seed. Operations recompute through the independent arithmetic above;
they do not consume the Wasm kernel's optimized cache representation. These
opaque values have no public serialization format. PocketIC performance and
memory measurements apply to the Wasm implementation, not this reference.

Optional older official internal-interface vectors, distributed with the
pinned `fips204` 0.4.6 source, exercise the expanded secret encoding and the raw
internal message domain as well:

```sh
python3 plugins/ml-dsa/tests/reference/check.py \
  --internal-vectors /path/to/fips204-0.4.6/tests/nist_vectors
```

That adds 25 exact public/expanded-secret key pairs, 20 exact signatures, and
15 positive/negative verifications. These private helpers are only test
surfaces: the public Motoko API exclusively accepts 32-byte seeds.

On 2026-10-13, OCaml 5.4.1 passed **3,369 checks** from the default command;
OCaml 4.14.2 passed **3,454 checks** with the optional internal corpus.
The subsequent prepared-key adapter suite passes **6,193 checks** with
OCaml 5.4.1 using the default command.
Compilation enables all warnings as errors except missing interfaces
and intentional catch-all value matches. The production plugin also built
successfully against the selected compiler's OCaml 5.4.1 toolchain.

The reference independently implements the arithmetic using ordinary modular
reduction and generated roots of unity. The Wasm kernel uses the pinned
`fips204` Montgomery-arithmetic implementation. The OCaml reference prioritizes
clear interpreter semantics; it does not promise constant-time signing.
