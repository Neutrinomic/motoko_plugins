# Adding a plugin

Put each plugin in `plugins/<name>/`. Use a lowercase name with underscores;
the directory, manifest, and registered package name should agree.

```text
plugins/example/
  README.md
  plugin.json
  compiler/
    register.ml
    reference.ml
    reference.mli
  runtime/
    Cargo.toml
    src/lib.rs
  tests/
    run/
    fail/
```

Start from [SHA-256](../plugins/sha256/) for a fixed Blob input, or
[CandidX](../plugins/candidx/) for specialization over Motoko types.

## Manifest and build

```json
{
  "name": "example",
  "ocaml_packages": ["wasm"],
  "runtime_crate": "motoko-compute-example"
}
```

`ocaml_packages` lists findlib packages needed to compile the extension.
Compiler libraries are resolved from the selected Motoko build. The builder
packs each plugin's OCaml modules into a distinct namespace and does not link
copies of the compiler libraries into the package. Additional OCaml libraries
must already be available in the host; naming a package does not bundle it.

Place all compiler `.ml` and `.mli` files in `compiler/`. The build orders them
using `ocamldep`; no per-plugin Dune project is needed. The runtime is a Rust
`cdylib` crate. The root Cargo workspace discovers `plugins/*/runtime`, sharing
one lockfile and release profile across plugins. Update `Cargo.lock` when
adding a crate or dependency.

From the Motoko checkout in its Nix development shell:

```sh
../plugins/scripts/build.sh --motoko "$PWD" example
```

The build uses that compiler's Wasm64 target, validates the runtime, checks
native loading, and writes `dist/example/`. `build.json` records toolchain
versions, source revisions, and artifact hashes. Generated binaries and
intermediates are ignored by Git.

## Compiler component

Register a `Codegen.Plugin_codegen.plugin` during native module initialization.
Choose unique package names, internal function IDs, and public Prim names.
Private Wasm export names may be reused by separate packages.

Pin the required compiler ABI in the source, currently `abi = 1`. Do not read
the running host's `abi_version` as the package requirement: that could accept
a newer host without rebuilding for its semantics.

Each binding supplies an argument policy, an interpreter reference, and a
generator over `Plugin_codegen.Backend`. The current API supports a Blob input
or variadic shared Motoko values, with a Blob result. The generator consumes
the packed argument and leaves the result on the Wasm stack. Use the supplied
layout, forwarding, and allocation helpers; consult the matching compiler's
`src/codegen/plugin_codegen.mli` for the exact interface.

## Runtime and tests

The runtime uses imported Motoko memory and the approved allocation/trap
functions. Operations are synchronous: do not retain input pointers, mutate
inputs, invoke the collector, or keep mutable state between calls. Initialize
every output byte and bound scratch allocation. See the
[memory and GC contract](design.md#execution-and-allocation).

Keep native kernel tests with the Rust crate. Put Motoko expectations in
`tests/run`, `tests/fail`, `tests/trap`, or `tests/run-drun`. Shared scenarios
belong under root `tests/integration`. Existing test comments demonstrate the
relative `--plugin` paths. Add at least one ingress `//CALL` for a `run-drun`
test so its actor method is actually exercised.

Run the shared suite from the compiler's Nix shell:

```sh
../plugins/scripts/test.sh --motoko "$PWD"
```

For intentional diagnostic or trace changes, regenerate expectations with
`--accept`, review the differences, then rerun without it. Do not hand-edit
expected outputs. New performance workloads belong in `benchmarks/`; keep
recorded results tied to their original inputs, artifact hashes, and toolchain.
