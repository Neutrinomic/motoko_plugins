# Pure-map final compiler check

The three final map actors were recompiled with clean compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f` and the canonical rebuilt package. Their measured function bodies are byte-identical to the archived `f1ccbba5e445df9db03bbc35be557187ade9b436` builds. **The complete executable sections are not byte-identical:** the compiler version string and its initialization lengths change. No new benchmark was run; the [111 public, 24 bulk and 32 point workload results](../../pure-map/README.md) remain measurements of the frozen f1 compiler.

The exact differences in each actor are:

- One passive data string changes from `2.0.0-9-gf1ccbba5e` (18 bytes) to `2.0.0-10-gc320bf90d` (19 bytes).
- Its static initializer changes only `i64.const 18` and `i32.const 18` to `19`, supplying the blob allocation and `memory.init` lengths. Every other code-section byte is identical; there are no instruction, control-flow, reference, or relocation changes beyond these two immediates.
- The `icp:private motoko:compiler` custom section changes to the same new version text. All other sections are byte-identical. The entire new data-section payload is exactly the old payload with the one length-prefixed version string replaced.

| Actor | Changed initializer | Passive segment | Raw complete WAT diff | Initialization references | Build provenance |
|---|---|---:|---|---|---|
| Public functions | `$alloc_484` | 234 | [diff](functions/raw-wat.diff) | [references](functions/initialization.txt) | [provenance](functions/provenance.json) |
| Bulk | `$alloc_146` | 83 | [diff](bulk/raw-wat.diff) | [references](bulk/initialization.txt) | [provenance](bulk/provenance.json) |
| Point | `$alloc_146` | 83 | [diff](point/raw-wat.diff) | [references](point/initialization.txt) | [provenance](point/provenance.json) |

The only reference to each changed initializer is a direct call from `$initialize_root_array`. The sole reference chain continues through `$rts_start`, `$link_start`, `$link_start.1`, and `$link_start.2`, which is the Wasm start function. These calls initialize static data before actor methods run. The archived actor methods measure deltas around operations with `Prim.performanceCounter(0)` and `Prim.rts_total_allocation()`; the changed initialization is outside those intervals. This check supports leaving the existing operation measurements attached to f1 without rerunning the full matrix. It does not claim identical installation costs or fresh c320 measurements.

[proof.json](proof.json) records all original and integrated Wasm hashes, section hashes, the two changed code-byte offsets, all four differing WAT lines, and every initializer reference. The actor sources, case inputs (apart from build provenance), native plugin sources, public `Map.mo`, Core 2.5.0 dependency sources, and dependency lock match the measured builds. The public wrapper SHA-256 remains `f653cbdbcfbfa456db5ddc78d6113ca8d926a39d6e435aa30991dc53fd9b888c`. The new compiler binary SHA-256 is `722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`; the rebuilt `plugin.cmxs` is `9969907022a2982732141711809ea7f12dbb70e5513b5effaf8390af9f229623`. Compiler source was clean; the plugin repository had concurrent report/CI changes, recorded in build provenance, while production inputs remained fixed.

The existing compile script was used separately for `functions`, `bulk`, and `point` from the plugin repository, after copying each archived `after/main.mo` and `after/cases.json` to its scratch directory:

```sh
python3 benchmarks/build-map-comparison.py \
  --motoko /srv/shared/code/motoko_experiments/motoko_sha \
  --deps /srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/deps \
  --out _build/opt-map-integrated/functions --require-clean-compiler
```

Both binaries were disassembled with WABT 1.0.41 `wasm2wat --enable-all` and compared without rewriting or normalizing any WAT lines. Complete disassemblies and binaries remain in `_build/opt-map-integrated`; the archive contains the complete raw diffs. A further functions-actor compilation using the original actor and wrapper filesystem paths produced the same integrated executable sections (and the same whole binary), ruling out source-path changes as the cause. The recorded difference is solely the linked compiler-version metadata and its initialization lengths.
