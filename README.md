# Motoko plugins

Native compiler plugins for fast, pure computation in Motoko. Each package
adds functions to `Prim`, specializes calls during compilation, and links its
Wasm runtime into the canister. Plugin code reads Motoko values through the
compiler's memory and GC helpers.

## Instruction costs

PocketIC measurements for the current ABI 1 plugins, using the same compiler
and typed inputs. Lower is better. For JSON/CBOR, the comparison below uses the
lowest instruction count among the three tested native libraries for each row.

| Operation | Native Motoko library | Native instructions | Plugin instructions | Native/plugin |
| --- | --- | ---: | ---: | ---: |
| JSON encode, 1,024 records | `json 1.4.0` | 53,258,267 | 7,780,660 | 6.84× |
| JSON decode, 1,024 records | `serde 3.5.0` | 763,222,636 | 23,799,314 | 32.07× |
| CBOR encode, 1,024 records | `cbor 4.1.0` | 49,934,053 | 8,409,156 | 5.94× |
| CBOR decode, 1,024 records | `cbor 4.1.0` | 152,527,112 | 10,577,700 | 14.42× |
| CandidX encode, 1,024 sparse records | CandidX `94c2868` | 88,379,476 | 6,154,646 | 14.36× |
| SHA-256, 1 MiB | `sha2 0.2.5` | 323,721,060 | 78,124,848 | 4.14× |

Three trials; medians shown. Counts include conversions between typed values
and each library's representation. Input setup, validation, reply encoding,
and message-end GC are excluded. These measure complete implementations,
not the isolated benefit of the plugin boundary or Wasm components.
[Full results](benchmarks/results/codec-comparison/README.md) include
`serde-core 0.2.1`, small records, large payloads, allocation counts, and
the serde stack overflows observed when decoding 64 KiB JSON strings.

## Plugins

| Plugin | Function | Description |
| --- | --- | --- |
| [CandidX](plugins/candidx/) | `Prim.to_candid_canonical(...) : { #ok : Blob; #err : Text }` | Canonical Candid encoding from typed Motoko values |
| [CBOR](plugins/cbor/) | `Prim.to_cbor(value)`, `Prim.from_cbor<T>(bytes)` | Deterministic CBOR encoding and typed decoding with `#ok`/`#err` results |
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
        --plugin ../plugins/dist/json \
        --plugin ../plugins/dist/cbor app.mo -o app.wasm
```

```motoko
import Prim "mo:⛔";

switch (Prim.to_candid_canonical({ value = 42 })) {
  case (#ok bytes) { let digest = Prim.sha256(bytes) };
  case (#err message) { Prim.debugPrint(message) };
};
type User = { name : Text; age : Nat8 };
let user = Prim.from_json<User>("{\"name\":\"Ada\",\"age\":37}");
let binary = Prim.to_cbor({ name = "Ada"; age = 37 : Nat8 });
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
packages when changing the compiler. The development SDK uses ABI 1; all plugin
functions use the same specialization mechanism and can return managed Motoko
values. Static Linux/musl and JavaScript compiler builds cannot load native
`.cmxs` files.

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
  cbor/
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

The [JSON optimization report](benchmarks/results/json-optimized/README.md)
records a 22.8% instruction reduction and 90.6% less allocation when decoding
1,024 records. Its [independent audit](plugins/json/tests/audit/README.md)
includes 9,263 syntax cases, 765 scalar/binary/Unicode cases, and regressions
for error paths, excessive scratch allocation, and GC.

Earlier [CandidX conformance and fuzz results](benchmarks/results/typed-results/README.md)
and [historical benchmarks](benchmarks/results/README.md) retain their original
artifact hashes and ABI labels.

## Design and licensing

The [design document](docs/design.md) describes compiler specialization, memory
borrowing, compatibility, and the relationship to Wasm components. Plugins are
trusted compiler extensions; the shared-memory interface is not a sandbox.
The [persistent-map research](docs/pure-map-research.md) compares structurally
shared trees and proposes SDK changes for discussion before implementation.

Existing licenses are preserved. CandidX carries MIT licenses in its compiler
and runtime directories. Other extracted material uses the Motoko license in
[LICENSE](LICENSE). See [NOTICE](NOTICE) for extraction provenance.
