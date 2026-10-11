# Motoko plugins

Native compiler plugins for fast, pure computation in Motoko. Each package
adds functions to `Prim`, specializes calls during compilation, and links its
Wasm runtime into the canister. Plugin code reads Motoko values through the
compiler's memory and GC helpers.

| Plugin | Function | Description |
| --- | --- | --- |
| [CandidX](plugins/candidx/) | `Prim.to_candid_canonical(...) : { #ok : Blob; #err : Text }` | Canonical Candid encoding from typed Motoko values |
| [JSON](plugins/json/) | `Prim.to_json(value)`, `Prim.from_json<T>(text)` | Typed JSON encoding/decoding with `#ok`/`#err` results |
| [SHA-256](plugins/sha256/) | `Prim.sha256(Blob) : Blob` | One-shot SHA-256 with direct Blob access |

The compiler support is proposed in
[Motoko PR #6443](https://github.com/caffeinelabs/motoko/pull/6443).
This repository is independent of the compiler checkout. It is not a submodule.

## Build and use

Use a compiler checkout with the plugin API; the tested revision is recorded in
[`toolchains/motoko.json`](toolchains/motoko.json). Enter that checkout's Nix
development shell. With this repository at `../plugins`:

```sh
cd /path/to/motoko
nix develop
make -C rts
../plugins/scripts/build.sh --motoko "$PWD"
bin/moc --plugin ../plugins/dist/candidx \
        --plugin ../plugins/dist/sha256 \
        --plugin ../plugins/dist/json app.mo -o app.wasm
```

```motoko
import Prim "mo:⛔";

switch (Prim.to_candid_canonical({ value = 42 })) {
  case (#ok bytes) { let digest = Prim.sha256(bytes) };
  case (#err message) { Prim.debugPrint(message) };
};
type User = { name : Text; age : Nat8 };
let user = Prim.from_json<User>("{\"name\":\"Ada\",\"age\":37}");
```

The build creates a matching dynamically linked native compiler and independent
packages in `dist/<name>/`, each containing `plugin.cmxs` and `runtime.wasm`.
To build selected plugins, append their names:

```sh
../plugins/scripts/build.sh --motoko "$PWD" sha256
```

Prebuilt packages load with `--plugin` without rebuilding the compiler. Native
components must match the compiler interfaces, OCaml toolchain, and host
platform; incompatible packages produce an unsupported-plugin error. Rebuild
packages when changing the compiler. ABI 2 adds typed managed results; ABI 1
packages are incompatible. CandidX callers must unwrap `#ok` or handle `#err`
before using the Blob. Static Linux/musl and JavaScript compiler
builds cannot load native `.cmxs` files.

## Repository layout

```text
plugins/
  candidx/
    plugin.json       package and build metadata
    compiler/         registration, code generator, interpreter reference
    runtime/          Rust crate compiled to Wasm
    tests/            plugin-specific Motoko tests and fuzz adapter
  json/
    ...
  sha256/
    ...
scripts/              shared build and test commands
tests/integration/    tests combining plugins and exercising GC
benchmarks/           PocketIC harness and recorded results
docs/                 architecture and authoring guide
toolchains/           compiler revision used by CI
dist/                 generated loadable packages (ignored)
_build/               generated intermediates (ignored)
```

Each plugin owns its implementation and tests. Shared tools discover plugin
manifests so adding another plugin does not require a new build script. See
[adding a plugin](docs/adding-a-plugin.md).

## Validation and performance

From the Motoko checkout's Nix shell:

```sh
../plugins/scripts/test.sh --motoko "$PWD"
```

The suite exercises source and IR interpretation, compiled Wasm, diagnostics,
package loading, native kernels, and GC behavior. The
[benchmark guide](benchmarks/README.md) covers PocketIC instruction counts and
the CandidX repository's conformance and fuzz tests.

Current ABI 2 results: [CandidX versus its native Motoko library](benchmarks/results/typed-results/README.md)
and [JSON encode/decode instruction costs](benchmarks/results/json/README.md).

Earlier comparisons against Motoko libraries include:

| Workload | Motoko library instructions | Plugin instructions |
| --- | ---: | ---: |
| SHA-256, 1 MiB | 323,721,060 | 78,124,848 |
| CandidX, 1,024 fixed records | 37,743,426 | 351,914 |
| CandidX, 1,024 sparse records | 88,379,476 | 5,674,118 |

These are historical ABI 1 PocketIC measurements, not Wasm component comparisons.
They predate the Result API and JSON plugin.
Input setup, reply encoding, and later GC are excluded. See the
[full results and methodology](docs/design.md#native-library-instruction-comparison).

## Design and licensing

The [design document](docs/design.md) describes compiler specialization, memory
borrowing, compatibility, and the relationship to Wasm components. Plugins are
trusted compiler extensions; the shared-memory interface is not a sandbox.

Existing licenses are preserved. CandidX carries MIT licenses in its compiler
and runtime directories. Other extracted material uses the Motoko license in
[LICENSE](LICENSE). See [NOTICE](NOTICE) for extraction provenance.
