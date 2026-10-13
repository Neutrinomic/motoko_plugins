# Independent Ed25519 audit

**Passed:** seven native tests and three public fixtures in all four execution
engines, with the selected upstream serial32 backend. No findings; exact
source/artifact hashes and scope are recorded in `report.json` and
`evidence.json`. The original serial64 audit is preserved in `history/default64`.

The corpus exercises the public `mo:fast/Ed25519` API in the source interpreter,
IR interpreter, lowered interpreter and compiled Wasm. The native audit calls
the exact exported Rust entry points and compares admitted inputs with
`ed25519-dalek` 2.2.0 `verify_strict`.

- All **151 Wycheproof** Ed25519 vectors, pinned by commit and content hash.
- **139 additional verification cases**: all eight torsion points as A and R,
  canonical-field and scalar boundaries, off-curve points, negative-zero
  encodings, malformed lengths and key-before-signature error precedence.
- Sixteen independently constructed mixed-order cases: eight valid
  uncofactored signatures and eight signatures satisfying only the cofactored
  equation. These check both against weak acceptance and accidental rejection
  of the documented mixed-order key domain.
- Independent OpenSSL signing answers for a **64 KiB** message and overlapping
  read-only key/message/seed inputs; successful calls after malformed inputs.
- Native empty-message null-pointer handling, input immutability and untouched
  output buffers on malformed seed errors.

`generate.py` uses independent affine Edwards arithmetic for structural
classification and mixed-order construction. Wycheproof validity expectations
come from the published corpus; they are not inferred from plugin output.
`vectors/provenance.json` pins the upstream corpus and its license.

Build `dist/ed25519`, then run inside the matching compiler's Nix environment:

```sh
CARGO_ENCODED_RUSTFLAGS=$'--cfg\x1fcurve25519_dalek_bits="32"\x1f--cfg\x1fcurve25519_dalek_backend="serial"' \
python3 tests/crypto-audit/round3/ed25519/run.py --motoko /path/to/motoko
```

The runner checks source/artifact consistency before and after execution and
records per-engine outputs and content hashes in `evidence.json`. It requires
native flags to match the plugin's configured backend, and records both native
and Wasm flags. `native.log` includes the exact curve25519-dalek rustc invocation.

The source review covers the runtime, compiler binding and portable reference.
Dalek's ordinary `raw_verify` and `verify_strict` use the same internal scalar
decoder, `RCompute` and compressed-R comparison. The plugin performs the strict
small-order checks first and additionally rejects noncanonical A/R encodings,
so avoiding a second R decompression preserves that verification equation.

The compiler allocates managed output before extracting borrowed input
pointers; the runtime performs no host callbacks, allocations or input writes.
Secret-key and expanded-key destruction use the enabled upstream zeroize
feature. This does not promise erasure of the caller's immutable seed or every
temporary SHA state; no such promise is made by the public module.

References: [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html),
[Wycheproof](https://github.com/C2SP/wycheproof),
[pinned Dalek verification source](https://docs.rs/ed25519-dalek/2.2.0/src/ed25519_dalek/verifying.rs.html).
