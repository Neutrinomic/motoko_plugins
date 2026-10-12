# Crypto plugin benchmarks

See [final measured results and limitations](RESULTS.md) and the [verified artifact ledger](final-verification.json).

These benchmarks compare `mo:fast` plugins and composed Bitcoin workflows against pinned Mops implementations. Each implementation is compiled into its own canister. Every case runs at least three times, with a fresh canister per implementation and trial. The runner checks exact output against independent expected bytes after measurement.

The dependency graph is pinned by [`dependencies/mops.toml`](dependencies/mops.toml) and [`dependencies/mops.lock`](dependencies/mops.lock): BLAKE3 0.1.2, ECDSA 8.0.1, Bitcoin 0.2.1, BLS12-381 0.2.0, SHA2 0.1.14, and their transitive dependencies. BLAKE3 omits its `base` dependency in published metadata, so the harness explicitly supplies base 0.16.0. No dependency is added to `packages/fast`.

## Reproduction

Run from the repository root with the matching installed compiler/RTS bundle and PocketIC 10.0.0. The runner's `--sdk-package` must identify an installed package containing `@icp-sdk/core/candid` and `@icp-sdk/core/principal`.

```sh
python3 benchmarks/crypto/generate.py
python3 benchmarks/crypto/generate-curves.py
python3 benchmarks/crypto/generate-bitcoin.py
python3 benchmarks/crypto/generate-bitcoin-tx.py
python3 benchmarks/crypto/merge-manifests.py
python3 benchmarks/crypto/build.py --manifest benchmarks/crypto/all-cases.json --stage my-run
node benchmarks/crypto/run.mjs --build benchmarks/crypto/results/my-run/build.json --out benchmarks/crypto/results/my-run/results.json --trials 3
```

`build.py` accepts `--bundle`, `--moc`, `--filter`, `--implementation`, `--plugin-roots` (a JSON map from plugin name to an isolated build root), and `--fast-root` for the source directory of an exactly matching public package. Stage directories and result files cannot be reused. `--implementation native` selects native variants including prepared transaction hashers.

Mops CLI 1.12.0 writes a valid lock but returns an integrity error for duplicate aliases: `sha2` and `sha2@0` share a package. The builder verifies the complete per-file SHA-256 lock directly, including every transitive `.mo` source and all alias/version mappings, before compilation. A successful downloaded dependency graph must match the retained lock; resolving different dependencies is an error. For network-independent reproduction, `source-store.tar.gz` and each stage's `source-map.json` retain every exact source byte with SHA-256 verification. Restore a stage with `python3 benchmarks/crypto/restore-sources.py --stage NAME --out /tmp/crypto-frozen-NAME`. Dependencies appear under `benchmarks/crypto/dependencies/.mops/` in that restored tree. The deduplicated store avoids committing dozens of identical dependency archives; local per-stage `sources.tar.gz` files remain available but are ignored.

## Measurement boundaries

- Inputs, parsing explicitly marked prepared, key preparation, and four forced GC increments execute before measurement. Each manifest states exceptions such as cold preparation deliberately included in a multi-input transaction workload.
- One synchronous operation or explicitly declared batch is measured with `Prim.performanceCounter(0)`, `Prim.rts_total_allocation()`, and `Prim.rts_reclaimed()`. No empty-loop subtraction is applied. Counts include plugin calls, result assignment and any synchronous GC. End-of-message GC is excluded.
- `allocated_bytes` is cumulative allocation during the interval, including objects later reclaimed. It is not retained heap growth. `reclaimed_bytes` records synchronous reclamation.
- Output normalization, serialization for the host oracle, and exact comparison happen after counters stop. Public Blob-to-array conversions required to call Mops algorithms remain inside the interval for Blob public API comparisons. RIPEMD160 also has explicitly labeled prepared-array kernel cases.
- Wasm sizes are complete separately compiled canisters, not just runtime kernels. `build.json` records source hashes, compiler/RTS hashes, plugin artifacts, Cargo locks, command lines and dependency aliases. Compiler identity must match each loaded plugin. Sources and fixtures are frozen before compilation and archived; executable artifacts are retained locally but excluded by repository ignore rules.
- Every trap, compilation failure, output mismatch and incomplete trial set is retained as a failure. A failed oracle never contributes a speedup. There is no substitution of instruction limits or missing measurements with a guessed number.

## Equivalence limits and independent oracles

Expected hashing/MAC outputs use Python `hashlib`/`hmac`; BLAKE3 uses the official vector file retained in `fixtures/`. Encoding generators independently implement radix conversion and BIP173/BIP350 checksum formulas. Curve fixtures use independent Python affine arithmetic and RFC6979/BIP340 vectors. BLS standard generators, independent affine multiplication, official Ethereum vectors and published IC certificate signatures establish expected output. Bitcoin uses published BIP32/BIP86 vectors and independent transaction serialization/sighash code in its generator.

BLAKE3 0.1.2 ignores derivation contexts and lacks complete chunk-tree handling. The 16 KiB unkeyed vector fails its official digest and is retained as a baseline failure; no speedup is claimed for that case. Full context derivation and absent Schnorr/BLS signature APIs have native absolute costs only. Early keyed benchmark artifacts used an accidental 33-byte key; they are superseded by the corrected 32-byte official-key case, which both implementations pass.

ECDSA Mops signing takes a caller-supplied nonce; native RFC6979 signing derives one. Native signing costs therefore have no direct Mops speedup. BLS native operations validate compressed encodings and subgroup membership; Mops group kernels start from trusted in-memory points and exclude parsing. These costs are labeled separately: native addition can be slower because validation dominates. Their ratios must not be described as pure arithmetic speedups.

Bitcoin P2PKH/P2WPKH native APIs validate curve membership while the Mops convenience functions trust key bytes. For the full BIP86 workflow, the baseline composes its public tagged hash and tweak primitive because its `tweakFromKeyAndHash` requires a 32-byte root and cannot represent the empty tree; a scalar-order check matches BIP341. Prepared transaction measurements include cold cache creation and hashing, amortized across all inputs in a batch. Mops has no BIP143 comparator, so prepared versus one-shot BIP143 is an internal native API comparison.
