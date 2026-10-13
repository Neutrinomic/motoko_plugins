# Prepared composition validation

All final gates passed on 2026-10-13 with SDK commit
`9f6ebeedc547e389a0529b4c91442e46b88fcbe0` and compiler SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.

| Final gate | Result | Evidence |
| --- | --- | --- |
| Composition through source, IR, lowered IR and Wasm | 1 passed; silent diagnostics/output | [log](logs/run-20261013T052750.log) |
| Eight serializer/nominal-type rejection fixtures | Intended M0279/M0096 diagnostics reviewed | [accept log](logs/accept-fail-20261013T052809.log) |
| Fresh rejection replay | 8 passed | [replay log](logs/replay-fail-20261013T052824.log) |
| Ash composition and real GC | 1 passed | [log](logs/ash-20261013T052853.log) |

The Ash actor retained prepared public and secret keys in application records,
generic mutable/pure maps, snapshot versions, array aliases and closures.
It required more than 4 MiB of reclamation before checking all keys, then cleared
all tested roots and required another 4 MiB of reclamation. This proves the
asserted lifecycle behavior; it does not isolate prepared-object reclaimed
bytes, prove exact retained heap, or establish secure secret erasure. The
reported 3K instructions/zero allocation cover only final empty-root assertions,
not the complete asynchronous test. See the [coverage notes](../../../packages/fast/tests/ash/coverage/PreparedComposition.md).

## Preserved failed checkpoints

These were test/harness issues; no production bug was found:

1. [Initial source](logs/run-20261013T052656.log): reserved field name `label`; renamed to `accountName`.
2. [Intermediate source](logs/run-20261013T052719.log): all execution stages completed, but dot-notation warnings violated the silent expectation; calls were changed to dot notation.
3. [Initial Ash config](logs/ash-20261013T052838.log): Core dependency pointed at package-level `.mops`; corrected to the existing test-local `.mops` link.
4. One `nix develop` invocation from the plugin directory was rejected by the compiler's shell hook before tests began. It was retried from the SDK directory. This event is noted in the summary; it produced no gate log.

## Files and path mapping

[validation.json](validation.json) and all seven logs/provenance manifests are
byte-for-byte copies of the original local evidence. [SHA256.json](SHA256.json)
checks those archived files; no compiler, plugin or generated canister binaries
are copied. Logs are at most 3.2 KiB, so compression would hinder review without
a meaningful size benefit. Provenance records tool/artifact/test-source hashes;
it contains no key material or source payloads. The matching copied
[Ash source manifest](ash-source-provenance.json) records the private compiler
resolver and its unchanged source files.

The summary's `log` and `provenance` paths resolve inside this directory.
Its `outputs_sha256` and each manifest's `test_sources_sha256` paths resolve
from the plugins repository root. The eight rejection fixtures and their
reviewed expectations remain under `tests/integration/fail/`; generated Wasm
is represented by hash only. Absolute historical command/tool paths are
retained rather than rewritten; map them as follows when reviewing locally:

| Historical path prefix | Meaning |
| --- | --- |
| `/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/integration/` | Plugins checkout used for these gates; repository-relative paths follow this prefix. |
| `/srv/shared/code/motoko_experiments/prepared-crypto/sdk/` | Private compiler checkout at the SDK commit above. |
| `/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/ash-local/` | Hash-pinned private Ash source copy, selecting that SDK compiler. |
| `_build/prepared-validation/composition/` in the historical integration checkout | Original logs and runner scratch; the log/provenance/summary files are archived here with the same relative names. |

Every gate verified eleven matching plugin artifact/source closures before
execution. The original runner entered the SDK's Nix shell, selected its
`bin/moc` through `PATH`, and ran sequentially:

```sh
test-runner -b -j 1 "$PLUGINS/tests/integration/run/prepared-composition.mo"
test-runner -b -a -j 1 "$PLUGINS/tests/integration/fail"
# Review intended diagnostics before replaying.
test-runner -b -j 1 "$PLUGINS/tests/integration/fail"
bun "$PRIVATE_ASH/src/index.ts" test \
  "$PLUGINS/packages/fast/tests/ash/PreparedComposition.ash.json" --verbose
```

`MOTOKO_ROOT` selected the private SDK and `MOTOKO_CORE` selected
`benchmarks/crypto/dependencies/.mops/core@2.5.0/src` within that plugin checkout.
These commands describe the recorded execution; archiving this evidence did
not rerun tests or change the original `_build` files.

## Full integration build and regressions

[integration.json](integration.json) records the 23 matching plugin builds, exact
parity with the six audited crypto runtimes, public-module hashes, four build
configuration tests, all-package compatibility checks, and 20 unchanged
codec/SHA fixtures across all four engines. Its `logs` map pins the additional
`integration-*.log` files; the earlier `SHA256.json` remains the unchanged
composition archive inventory. The manifest also pins the 199-case final
benchmark cohort and restored source archive evidence. Compiler-wide CI is a
separate gate.
