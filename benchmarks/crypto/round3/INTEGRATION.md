# Signature round-three integration

The final direct-API checkpoint starts at plugins `7a0211b` and uses compiler
`92b1bdecbc7bc67fd51ad226f8d147d15494fc09`, the original release/debug RTS,
and ABI 1. Compiler, SDK, RTS and installed binaries are unchanged. The
separately authorized prepared-key SDK work is a later phase.

Final source/shared configuration is committed at
`f43a81e88e3396b58f707761d01f635836747d2b`, with the test-only composition
correction `dce24ad`. All 23 plugins build in the pinned compiler's Nix shell.
The six signature runtime Wasm files are byte-identical to their independently
audited lane artifacts. The final 98-case cohort passed all 294 exact-output
checks in three fresh canisters per case.

The retained changes are secp256k1 native-width arithmetic and public-scalar
NAF, allocation-free predicate output handling, P256 fixed-base signing,
fused BLS aggregate calls with ordinary public wrappers, Ed25519's documented
upstream serial32 backend, fixed-profile RSA-3072 PSS with a specialized public
exponent, and ML-DSA-44. New algorithms are standalone costs, not optimization
speedups against a different signature scheme. [Results](RESULTS.md) include
negative cases, allocation, Wasm size, memory limitations and exact evidence.

Shared `runtime_cfg` accepts only Rust cfg names/quoted values and applies them
to one runtime package per Cargo invocation. It does not add arbitrary compiler
flags or change the plugin ABI. Four tests check validation and isolation; the
Ed25519 production Wasm and native independent audit exercise the selected
upstream backend. RSA uses its plugin-local C toolchain resolver and builds
without `RSA_CLANG`/`RSA_AR` overrides in the pinned Nix shell.

## Integration gates

- 54 native tests across six separate runtime crate invocations.
- 14 public fixtures through Motoko, IR, lowered IR, Wasm validation and execution,
  including downstream Bitcoin composition.
- Seven type-rejection fixtures and the full expectation inventory.
- 62 Ash methods across seven modules, including all 15 P256 methods and four
  seven-plugin composition methods.
- All-plugin packaging: standalone native components, unused-plugin identity,
  compatibility/ABI diagnostics, runtime resolution and malformed-runtime checks.
- Composition retains dynamically created inputs and results across 13 message
  boundaries and asserts more than 4 MiB of actual reclamation. Independent lane
  audits retain additional malformed-input, boundary, pointer and GC checks.

The first composition fixture used a nonexistent Blob instance method and then
had two unused declarations. Only fixtures changed; their initial failed logs
remain alongside the passing replay. Adapting the older RSA benchmark manifest
also needed its family label before any final actor was compiled.
[Validation records](validation/report.json) retain commands, logs and hashes.

## Reproduction boundaries

Run plugin builds from the existing compiler checkout's Nix shell; its shell
hook requires that checkout as the initial working directory:

```sh
cd /absolute/path/to/motoko
nix develop . --command bash -c 'cd /absolute/path/to/plugins && python3 scripts/build.py --motoko /absolute/path/to/motoko --skip-motoko-build'
```

OCaml 5.4.1 and Rust 1.99.0-nightly (2026-07-24) match the recorded build.
RSA records the selected clang/llvm-ar 21.1.8 tools in its lane evidence.
Ash uses the source checkout with `mocArgs` support, rather than an older
installed executable with a different configuration schema.

At most three heavy team jobs ran concurrently. PocketIC measurements were
exclusive within the team; this does not claim an otherwise idle host. Earlier
crypto round-one/round-two evidence remains unchanged. The common protocol
retains occupied-heap/capacity samples, not true peak scratch or retained-live
memory. Four GC increments do not guarantee a complete collection.

The [source store](source-store.json) covers 17 immutable build stages, including
the unmeasured BLS alias-only build, which supplies no performance result. Its
12.2 MB compressed archive restores exact sources and binary vector fixtures;
compiler, RTS, plugin and canister executables remain locally frozen and are
hash-pinned, rather than committed. The recorded compiler executable also
requires its Nix loader/shared-library environment; source restoration is not
an executable portability guarantee. Fresh restoration of the final stage and
the early RSA baseline is checked by the retained integrity reports.
