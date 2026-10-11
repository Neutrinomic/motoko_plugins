# Motoko plugins

Native compiler plugins for fast, pure computation in Motoko. Each package
adds functions to `Prim`, specializes calls during compilation, and links its
optional Wasm runtime into the canister. Plugin code reads Motoko values through the
compiler's memory and GC helpers.

## Instruction and allocation costs

Recorded PocketIC measurements for the ABI 1 plugins, using the same compiler
and typed inputs within each comparison. Lower is better. For JSON/CBOR, the
comparison below uses the lowest instruction count among the three tested
native libraries for each row.

| Operation | Native Motoko library | Native instructions | Plugin instructions | Native/plugin | Native allocated bytes | Plugin allocated bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| JSON encode, 1,024 records | `json 1.4.0` | 53,258,267 | 7,780,660 | 6.84× | 7,145,616 | 194,208 |
| JSON decode, 1,024 records | `serde 3.5.0` | 763,222,636 | 23,799,314 | 32.07× | 136,203,896 | 172,848 |
| CBOR encode, 1,024 records | `cbor 4.1.0` | 49,934,053 | 8,409,156 | 5.94× | 2,452,232 | 174,224 |
| CBOR decode, 1,024 records | `cbor 4.1.0` | 152,527,112 | 10,577,700 | 14.42× | 11,545,504 | 173,192 |
| CandidX encode, 1,024 sparse records | CandidX `94c2868` | 88,379,476 | 6,154,646 | 14.36× | 3,578,064 | 22,624 |
| SHA-256, 1 MiB | `sha2 0.2.5` | 323,721,060 | 78,124,848 | 4.14× | 1,008 | 56 |

Three trials; medians shown. Counts include conversions between typed values
and each library's representation. Input setup, validation, reply encoding,
and message-end GC are excluded. These measure complete implementations,
not the isolated benefit of the plugin boundary or Wasm components.
Allocated bytes include results and temporary garbage during the measured call;
they measure allocation pressure, not peak memory or retained live bytes after
GC. The same library supplies native instruction and allocation counts, chosen
by instruction cost.
[Full results](benchmarks/results/codec-comparison/README.md) include
`serde-core 0.2.1`, small records, large payloads, allocation counts, and
the serde stack overflows observed when decoding 64 KiB JSON strings.
[Allocation tables](benchmarks/results/codec-comparison/allocations.md) compare
every tested native library with the plugins.

Persistent maps compared with `core 2.5.0` pure Map, using 65,536 entries and
boxed `Nat64` keys. Each row is the median batch cost divided by 64 operations;
three trials produced identical counts. Both plugin paths support generic
values. The callback path uses a normal Motoko comparator; scalar ordering
compares keys directly in generated Wasm.

| Map operation | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Plugin allocated B/op |
| --- | ---: | ---: | ---: | ---: | ---: |
| `get` (present) | 3,234.27 | 2,560.17 | 1,413.59 | 0.00 | 0.00 |
| `add` (insert) | 13,311.12 | 10,089.95 | 8,889.05 | 2,379.88 | 1,323.00 |
| `add` (overwrite) | 12,337.73 | 5,831.77 | 4,685.19 | 2,165.00 | 1,109.25 |
| `remove` (present) | 17,378.17 | 9,049.58 | 7,903.00 | 3,443.38 | 1,104.75 |
| `remove` (absent) | 16,604.55 | 3,056.73 | 1,855.83 | 3,269.38 | 0.00 |
| `replace` (absent) | 3,566.27 | 3,039.73 | 1,838.83 | 0.00 | 0.00 |

An overwrite allocates **1,109.25 bytes/op** in either plugin path versus
**2,165 bytes/op** in core. Missing removal and replacement allocate **zero**
plugin bytes. Callback and scalar paths have identical allocation in these rows.
Both libraries share unchanged branches; the plugin copies only
the changed paths and retains payload references. Separate GC tests verify that
updating a map with a 1 MiB payload costs the same allocation as a 5-byte payload.

The [complete map report](benchmarks/results/pure-map/README.md) includes all
48 workloads, allocations, retained versions, bulk operations, and reproduction
commands. Some operations favor core: intersecting a 256-entry map with a small
map costs **57,509 instructions** for the core adapter versus **87,555** for the
plugin, allocating **6,016 versus 12,184 bytes**. Bulk comparisons explicitly
identify adapters where core lacks a public operation. These results measure
the complete algorithms and representations.

## Plugins

| Plugin | Function | Description |
| --- | --- | --- |
| [CandidX](plugins/candidx/) | `Prim.to_candid_canonical(...) : { #ok : Blob; #err : Text }` | Canonical Candid encoding from typed Motoko values |
| [CBOR](plugins/cbor/) | `Prim.to_cbor(value)`, `Prim.from_cbor<T>(bytes)` | Deterministic CBOR encoding and typed decoding with `#ok`/`#err` results |
| [JSON](plugins/json/) | `Prim.to_json(value)`, `Prim.from_json<T>(text)` | Typed JSON encoding/decoding with `#ok`/`#err` results |
| [Pure map](plugins/pure-map/) | `Map.get`, `Map.add`, `Map.remove`, `Prim.pmap_*` | Persistent ordered maps with generic keys/values, Motoko callbacks, and native scalar comparisons |
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
        --plugin ../plugins/dist/cbor \
        --plugin ../plugins/dist/pure-map \
        --package pure-map ../plugins/plugins/pure-map/motoko \
        app.mo -o app.wasm
```

```motoko
import Prim "mo:⛔";
import Map "mo:pure-map/Map";

switch (Prim.to_candid_canonical({ value = 42 })) {
  case (#ok bytes) { let digest = Prim.sha256(bytes) };
  case (#err message) { Prim.debugPrint(message) };
};
type User = { name : Text; age : Nat8 };
let user = Prim.from_json<User>("{\"name\":\"Ada\",\"age\":37}");
let binary = Prim.to_cbor({ name = "Ada"; age = 37 : Nat8 });
let original = Map.empty<Nat64, Text>();
let updated = Map.addNat64(original, 42, "answer");
assert Map.getNat64(updated, 42) == ?"answer";
```

The build creates a matching dynamically linked native compiler and independent
packages in `dist/<name>/`, each containing `plugin.cmxs`. Kernel-based packages
also contain `runtime.wasm`; pure map emits managed Wasm directly.
To build selected plugins, append their names:

```sh
../plugins/scripts/build.sh --motoko "$PWD" sha256
```

Prebuilt packages load with `--plugin` without rebuilding the compiler. Native
compiler modules must match the compiler interfaces, OCaml toolchain, and host
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
  pure-map/
    compiler/         generated managed Wasm and interpreter reference
    motoko/           public Map library
    tests/            differential, sharing, and GC checks
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
shared trees and records the SDK options considered. The implementation uses
integrated synchronous callbacks and optional native scalar ordering. Point
updates copy changed paths and share untouched branches and payloads.

Existing licenses are preserved. CandidX carries MIT licenses in its compiler
and runtime directories. Other extracted material uses the Motoko license in
[LICENSE](LICENSE). See [NOTICE](NOTICE) for extraction provenance.
