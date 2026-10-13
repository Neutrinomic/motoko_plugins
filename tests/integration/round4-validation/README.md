# Round-four central integration validation

**All final gates passed on 2026-10-13.** One central build produced all
23 plugins; their six crypto runtimes and plugin-owned build source pins match
the selected audited lane artifacts. The compiler and both RTS artifacts were
unchanged. No compiler build, lane suite replay, fixture edit or expectation
acceptance was needed.

| Check | Result | Evidence |
| --- | --- | --- |
| Central plugin build | All 23 built successfully | [build log](logs/build-all23.log.gz), [inventory](adoption-inventory.json) |
| Selected runtime/source parity | All six crypto plugins identical | [integration.json](integration.json) |
| Packaging and simultaneous loading | Passed, including directory/component parity and expected compatibility/runtime errors | [log](logs/packaging-20261013T064733.log) |
| Prepared and direct signature composition | Both passed source, IR, lowered IR and compiled Wasm execution | [log](logs/run-20261013T064827.log) |
| Existing serializer and cross-plugin rejections | All eight expectations replayed unchanged | [log](logs/replay-fail-20261013T064926.log) |
| Combined prepared-key Ash lifetime test | Passed both actual-GC reclamation thresholds and all handle/container/closure assertions | [log](logs/ash-20261013T064946.log) |

The Ash test required more than 4 MiB of reclamation before consuming retained
prepared keys, then cleared all tested roots and required another 4 MiB of
reclamation. Its displayed 3K instructions/zero allocation measure only the
final empty-root assertions. These results do not claim exact retained/live
heap, secure secret erasure or absence of hidden references; see the unchanged
[composition coverage](../../../packages/fast/tests/ash/coverage/PreparedComposition.md).

## Identities and preserved evidence

- SDK commit: `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`.
- Compiler SHA-256: `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
- Complete `mo:fast` module-tree SHA-256: `af0d3dd7e8396b93346acfea752d2275720402f3381026198d739050aa096eeb`.

The module hash uses **all files recursively**, mapping their repository-root
relative paths to SHA-256 values, then hashing UTF-8 JSON with sorted keys and
compact `(',', ':')` separators. There were exactly 30 files, all `.mo`.
[adoption-inventory.json](adoption-inventory.json) preserves this exact map and
every plugin's original build-manifest and artifact hashes.

[provenance.json](provenance.json) is byte-identical to all four per-gate
manifests, stored once. It records compiler/RTS/PocketIC/Ash/tool hashes, all23
artifact identities, module and actual test-source pins. Every artifact and
declared source closure was checked before every gate. The unchanged tests
were also checked against the earlier prepared-round fixture pins.

[build-manifests.json.xz](build-manifests.json.xz) contains the 23 complete
central build manifests, including source and compiler-source pin maps.
Re-encoding each entry with Python `json.dumps(entry, indent=2) + '\n'`
reconstructs its original `build.json` bytes and inventory hash; that was
verified for all23 entries. [selected-runtime-pins.json](selected-runtime-pins.json)
is the original selected-lane runtime inventory. `integration.json` records
six exact runtime matches plus the matched per-plugin owned-source counts and
hash maps' fingerprints. No native binaries or generated canister binaries
are included; their hashes are preserved instead.

The full build log is gzip-compressed without timestamps. Four smaller gate
logs remain readable. [SHA256.json](SHA256.json) checks all archived files.
There were no failed gate attempts in this central round. Original ignored
`_build/round4-validation` evidence and prior prepared-round evidence remain
unchanged.

## Commands and historical paths

The [build wrapper](harness/build.sh), [gate wrapper](harness/run.sh) and
[preflight](harness/preflight.py) retain the actual local paths. From the SDK
checkout, the gate command was run sequentially with `PHASE` set to
`packaging`, `run`, `replay-fail` and `ash`:

```sh
nix develop --command bash \
  /srv/shared/code/motoko_experiments/plugins/_build/signature-round4/integration/_build/round4-validation/run.sh PHASE
```

Map historical paths as follows when reviewing outside that workspace:

| Historical prefix | Meaning |
| --- | --- |
| `/srv/shared/code/motoko_experiments/plugins/_build/signature-round4/integration/` | Central plugin checkout used for these gates. |
| `/srv/shared/code/motoko_experiments/prepared-crypto/sdk/` | Private SDK checkout at the pinned commit above. |
| `/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/` | Existing hash-pinned private Ash harness selecting that compiler. |

Source/output paths inside the manifests are repository-root relative.
The historical locked `.mops` links supplied Core2.5.0 to the unchanged test
configuration; those task-local links were removed after validation. No
installed compiler or other global tool was changed by these gates.
