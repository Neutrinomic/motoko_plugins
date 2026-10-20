# Plugin design and recorded validation

This experimental native `moc` extension adds functions to `mo:⛔` from separate
plugin packages. Each package contains a compiler component (`plugin.cmxs`)
and, when needed, a position-independent Wasm64 runtime (`runtime.wasm`). The compiler
component supplies the function's type policy, specialization generator, and
reference implementation for the interpreters. The runtime supplies compute
kernels and temporary helpers.

Each package in this repository is independent:

| Package | Prim function | Implementation |
| --- | --- | --- |
| `candidx` | `to_candid_canonical(...) : { #ok : Blob; #err : Text }` | Generated typed traversal and a Wasm shape-table helper |
| `json` | `to_json(value)`, `from_json<T>(text)` | Typed heap visitors, streaming JSON parser/writer, managed Result values |
| `cbor` | `to_cbor(value)`, `from_cbor<T>(bytes)` | Deterministic encoding and typed decoding with managed Result values |
| `pure-map` | `pmap_*` through `Map.mo` | Persistent trees with shared branches and payloads |
| `mutable-map` | `mmap_*` through `Map.mo` | In-place B-tree operations on caller-owned managed arrays and records |
| `sha256` | `sha256(Blob) : Blob` | Direct Blob access and a one-shot Wasm SHA-256 kernel |

The CandidX package extracts the direct encoder from the CandidX compiler patch.
It does not use the standalone CandidX Wasm module. Its `cx` profile and limits
are preserved: value-derived types, omission of absent optional record fields,
canonical NaNs, at most 32 MiB output, 2,000,000 visited items, 1,024 output types,
and depth 256. Unsupported actual function/service values and invalid schemas
return `#err`. Ordinary `to_candid` and `from_candid` retain their existing behavior.

Performance and allocation tables below record the original ABI 1 artifacts.
They predate CandidX's Result wrapper and the JSON plugin; see each report's
artifact hashes. Additional ABI 2 measurements are recorded separately for
[CandidX](../benchmarks/results/typed-results/README.md) and
[JSON](../benchmarks/results/json/README.md).

## Build and use

From a compatible Motoko compiler checkout, in `nix develop` (with this
repository at `../plugins`):

```sh
make -C rts
../plugins/scripts/build.sh --motoko "$PWD"
moc --plugin ../plugins/dist/candidx \
    --plugin ../plugins/dist/sha256 \
    --plugin ../plugins/dist/json example.mo -o example.wasm
```

```motoko
import Prim "mo:⛔";

switch (Prim.to_candid_canonical({ height = 42; memo = ?"hello" })) {
  case (#ok bytes) { let digest = Prim.sha256(bytes) };
  case (#err message) { Prim.debugPrint(message) };
};
type User = { name : Text; age : Nat8 };
let user = Prim.from_json<User>("{\"name\":\"Ada\",\"age\":37}");
```

Pass the same `--plugin` options for `--check`, `-r`, or `-r -iR`. They add public
bindings when the compiler constructs its Prim module; no application-side
FFI declarations are needed. Only referenced runtimes are linked. Multiple
packages can be loaded in either order. Packages use the compiler and OCaml
toolchain they were built with; rebuild them after changing the compiler.

Every plugin binding is a compiler intrinsic. The compiler preserves the
operation's identity through inferred aliases and specializes every call using
the actual argument types. Its type cannot be erased to an ordinary function
annotation. An explicitly typed Motoko wrapper provides a function value for
callbacks:

```motoko
func encodeHeight(x : Nat) : { #ok : Blob; #err : Text } {
  Prim.to_candid_canonical(x)
};
func hash(bytes : Blob) : Blob { Prim.sha256(bytes) };
```

Argument lists and tuple values remain distinct, as with ordinary Candid:
`Prim.to_candid_canonical(1, true)` encodes two arguments;
`Prim.to_candid_canonical((1, true))` encodes one tuple argument.

## Loading prebuilt plugins during canister compilation

This is already supported. A compiler with the plugin SDK can load several
prebuilt packages on each invocation without rebuilding `moc`:

```sh
bin/moc --plugin /path/to/candidx \
        --plugin /path/to/sha256 \
        app.mo -o app.wasm
```

Each directory contains `plugin.cmxs` and its optional `runtime.wasm`. The CLI dynamically
loads `plugin.cmxs` using OCaml `Dynlink.loadfile_private` before typechecking.
The extension registers its Prim functions, type policy, interpreter reference,
and code generator. During canister compilation, generated code uses the
original Motoko types and the linker incorporates the referenced runtime Wasm.
The resulting canister is an ordinary Wasm module with direct calls. Loading
the compiler extension dynamically adds no runtime plugin dispatch and does
not change the GC borrowing contract.

The canister still needs compilation; the compiler executable does not need
rebuilding for each compatible plugin. The shared `scripts/build.sh` command
builds matching compiler and plugin artifacts together. Consumers with prebuilt packages skip that build step. Additional
packages can be built against matching compiler build artifacts; an installed,
standalone external SDK has not yet been packaged.

Native `.cmxs` files must match the compiler/OCaml interfaces and host platform.
Loading them also requires a dynamically linked host compiler with `dlopen`
support. The Linux/musl `release-static` compiler builds cannot load these
native packages; use a dynamically linked native build such as the compiler
produced by `scripts/build.sh`.
The explicit plugin ABI version is checked, but is not a promise of binary
compatibility across compiler releases. Updating the compiler can require new
plugin compiler components. New plugins supported by the existing SDK need no
compiler modification; extending the SDK itself can require one. Stock `moc`
without this extension and the current JavaScript compiler cannot load these
native packages.

Incompatible native interfaces or implementations, native loader failures, and
unsupported SDK ABIs produce an `unsupported compute plugin` diagnostic and
exit status 1. The diagnostic preserves the concrete cause and names the
running compiler and OCaml version so the developer can select a matching
package build. ABI mismatches include the required and supported ABI numbers.
Arbitrary plugin initialization failures and duplicate registrations remain
separate errors. Native loader failures can also mean a missing dependency or
wrong host platform; their original reason is retained.

Compatibility is checked using OCaml's native interface/implementation checks
and the explicit plugin ABI, rather than an exact Motoko release allowlist.
The ABI remains 1 during development of the compiler PR. Packages must be
rebuilt against the matching compiler checkout. A successful compatibility
check does not prove that the plugin implementation is correct.

Package names, internal function IDs, and plugin Prim names must be distinct;
duplicates fail during loading. Separate packages may reuse private runtime
Wasm export names. Plugins remain trusted compiler extensions and share the
canister's memory once linked. The current loader has no in-process unload or
replacement operation; a new compiler invocation loads the desired packages.
Replacing a deployed canister's plugin code requires compiling and deploying
an updated canister module.

The implementation is in [`moc.ml`](https://github.com/infu/motoko/blob/codex/compute-plugins/src/exes/moc.ml),
[`plugin_codegen.ml`](https://github.com/infu/motoko/blob/codex/compute-plugins/src/codegen/plugin_codegen.ml), and
[`compute_plugin.ml`](https://github.com/infu/motoko/blob/codex/compute-plugins/src/mo_values/compute_plugin.ml). Existing package
checks cover independent packages, unused runtimes, explicit `.cmxs` paths,
and invalid runtime diagnostics.

## Execution and allocation

There is one final Wasm module and one Motoko main memory. Plugin runtime
functions become ordinary direct Wasm calls during static linking. There is
no runtime plugin loader, secondary Wasm instance, serialized heap descriptor,
or host dispatch per value.

CandidX generates shape discovery, exact sizing, and payload writing from
the original Motoko types. Scalars, binary values, and records with fixed
wire shapes use compile-time headers and need no Rust shape context. Vectors
of primitives or fixed-shape records choose precomputed empty/nonempty headers.
Records can contain variable-length Text and binary fields; their wire types
remain fixed. Fixed-width record payloads also avoid a per-element sizing pass.
These paths retain the same value, depth, integer, and output limits as dynamic
shape discovery.

Value-dependent shapes use temporary Rust state, without copying the payload.
Arrays of variants whose cases all have primitive payloads collect their
selected labels and opcodes, sort and deduplicate once, and intern only the
completed union. Adjacent identical cases are skipped; empty and singleton
arrays bypass this collector. This greatly reduces scratch allocation for
distinct tags. Cycling through repeated tags can use more scratch than the
general reducer because the buffer grows with the number of elements before
deduplication. It remains charged against the existing scratch limit.

Other arrays whose elements can accumulate fields or variant cases use a
balanced reduction, avoiding a quadratic sequence of retained prefix unions.
Arrays of scalar/option/vector chains keep the cheaper sequential reduction.
Large source variants use a binary decision tree over the compiler's heap tags
and share shape, payload, and error helpers to bound generated code size. Wire
labels remain Candid IDs, which can differ from those heap tags. Dynamic record
joins and unary shapes share a bounded, lazily allocated 32-entry cache inside
each call's context. Record builders also reuse their previous shape when its
fields match. These caches save repeated work at a small temporary allocation
cost. Nothing is cached across calls.

All paths read original objects through the compiler's layout and forwarding
barriers, allocate one final Blob, and write directly into its payload. SHA-256
reads its input Blob in place, keeps its compression state in Wasm locals, and
writes its 32-byte digest into a new Blob. Empty input uses the known digest.
Separate 32-byte and 64-byte kernels expose fixed padding to constant folding.
They add about 20 KiB of runtime code; other lengths pay a small dispatch cost.

The raw-pointer borrowing interval is synchronous and contains no GC
safepoint, callback into Motoko, suspension, or retained pointer. The current
runtime collects at explicit safepoints, not on every allocation. Memory growth
does not change Wasm addresses. Previously forwarded input objects are read
through the compiler's existing forwarding barriers. Array traversals resolve
the array's forwarding pointer once and advance a cursor through its elements
inside this borrowing interval. Results use the normal allocation barrier
before becoming observable Motoko values.

`env.compute_plugin_alloc(size: i64, align: i64) -> i64` provides temporary
memory using unrooted Motoko Blob payloads, following the RTS
`EphemeralAllocator`. Alignment must be a power of two up to 65,536 bytes.
Deallocation is a no-op: unreachable scratch objects are reclaimed by a later
GC increment, after every plugin pointer is dead. This avoids a separate
persistent allocator or plugin heap. `env.compute_plugin_trap(ptr: i64,
len: i64)` terminates a failing computation. Neither function can trigger a GC
increment. Trapped computations must not depend on Rust destructors running.

Managed algorithms may call ordinary synchronous Motoko closures through
`Backend.Call.local`, using the full instantiated `Local`/`Returns` function
type and the compiler's existing closure calling convention. The compiler
preserves argument evaluation order and distinguishes one tuple-valued argument
or result from multiple sequence arguments or results. Current collection
points run after synchronous message frames return; a local callback cannot
run collection inside its caller. Keep only vanilla managed references across
callbacks, never borrowed addresses. Callbacks may allocate, reenter a plugin,
or schedule asynchronous work, but this interface cannot suspend the caller.
The interpreter protocol is continuation-based and invokes callbacks with the
ordinary actor context. `Compute_plugin.pure` lifts a callback-free reference
computation into this protocol.

Plugins that emit only managed Wasm code register `runtime = None` and no
runtime imports. They need no dummy runtime module. A plugin with imports and
no declared runtime is rejected. The pure-map implementation demonstrates
managed structural sharing, callbacks, scalar comparison helpers, and a
codegen-only package.

Managed plugins can also construct and update ordinary mutable Motoko arrays
and record fields through `Arr.tabulate_mut`, `Arr.set`, `Arr.move_within`, `Object.lit`,
`Object.load`, and `Object.set`. The SDK checks container shape, field mutability,
and assignment subtyping during compilation. Generated stores retain runtime
bounds checks and the compiler's existing forwarding and GC write barriers.
State belongs to the caller's managed objects and can persist like ordinary
Motoko data; there is no separate plugin heap. Setter operands are evaluated
once, left to right, before bounds checking and storing. See the
[independent mutation audit](audits/managed-mutation-sdk/README.md).

`Arr.move_within` copies an overlapping range within one mutable array. It
evaluates array, source index, destination index and length once in that order,
then validates both complete ranges before writing. Empty ranges may start at
the array end. It resolves forwarding once and borrows cursors only inside its
no-safepoint loop; every pointer destination still uses the normal write
barrier. Collection kernels use it for B-tree shifts without repeating a
bounds check and forwarding resolution for each element.

`Arr.with_prefix` validates a logical array prefix once and provides indexed
managed-value loads from a borrowed base. This is a trusted native-plugin
operation: callers must prove every index is below the saved prefix length,
keep the loader inside its body, and prevent GC safepoints in that body or its
callees. Allocation and Wasm memory growth preserve these logical addresses.
Mutable-map uses this only inside nonempty native `Nat`/`Int` node searches;
arbitrary comparators keep the usual managed array loads.

The no-safepoint invariant is part of this compiler ABI. A future collector
that moves objects during allocation would require changing this adapter or
introducing rooted handles before these plugins could use it.

## Garbage and accidental implementation errors

The codec and hash kernels have no persistent per-call state, but computation
can still allocate temporary garbage. Managed collections retain caller-owned
objects according to ordinary Motoko reachability. SHA-256 allocates only its final digest
Blob. CandidX's fixed-shape paths allocate their final Blob and a small Result variant. Dynamic
shape discovery additionally allocates Rust structures backed by ordinary
pointer-free Motoko Blobs. Dropping the Rust context does not immediately free
their backing bytes: `dealloc` is a no-op, and a later Motoko GC reclaims them.
Old buffers left by vector growth count toward CandidX's scratch budget.

Selected measured allocations from the native-library comparison below:

| Operation | Output payload bytes | Total plugin heap allocation | Allocation beyond the result Blob |
|---|---:|---:|---:|
| SHA-256, 1 MiB input | 32 | 56 | 0 |
| CandidX, static record | 78 | 104 | 0 |
| CandidX, 1,024 fixed records | 21,539 | 21,568 | 0 |
| CandidX, 1,024 sparse records | 17,350 | 22,592 | 5,216 |
| CandidX, 1,024 distinct variants | 9,998 | 60,256 | 50,232 |
| CandidX, 6,000 variants cycling 64 tags | 12,397 | 276,744 | 264,320 |

These totals are cumulative allocation during one measured call, not retained
live memory. The last column subtracts the returned Blob's 24-byte header and
payload rounded to an eight-byte word in this RTS. Input construction is
excluded. Retaining the output keeps its result Blob alive; the excess becomes
temporary garbage. The recorded instruction costs exclude the later GC work.

Repeated calls in one synchronous message can accumulate scratch and discarded
results before the next collection. Reclamation makes space reusable, but
does not imply that grown Wasm memory immediately shrinks. CandidX checks a
256 MiB scratch budget per call, alongside its output/type/item/depth limits.
This is not a per-message or global plugin quota. The generic allocator checks
overflow and alignment but does not enforce a plugin-specific allocation
budget. A future compiler-owned per-call scratch budget would limit accidental
over-allocation across all plugins.

Sharing the Motoko heap also makes ordinary implementation mistakes more
serious than a wrong return value. An incorrect offset or length can overwrite
another object while remaining within Wasm memory bounds. A partially written
result Blob can contain uninitialized bytes. Retaining a borrowed pointer,
introducing GC during borrowing, or bypassing forwarding/allocation barriers
can invalidate object references. The SDK provides compiler helpers and a
lifetime contract; it does not prove arbitrary generators and kernels obey it.
Compatibility checks do not detect these algorithmic or memory-access bugs.

These implementations use the compiler barriers, finish their scratch
contexts within the call, and initialize complete outputs. Exact sizing and
cursor checks cover CandidX output writing; SHA-256 writes a fixed 32-byte
digest. Existing fuzz, pointer-ABI, and forced-GC tests found no current leak,
corruption, or lifetime defect. The generic plugin system is nevertheless a
trusted foreign-code integration, not memory isolation between plugins and
Motoko objects. Additional output guards in debug builds would help catch
accidental overruns without imposing those checks on release kernels.

## Relationship to Wasm components

Component packaging can coexist with this integration. The Component Model
allows core modules inside one component to share memory and direct calls;
separately linked components have isolated memories. A compatible internal
core-module ABI could therefore retain the current access pattern. A separate
component's ordinary `list<u8>` interface generally adds allocation and copying
between memories. Canonical ABI fusion can remove intermediate adapter
representations, while preserving that memory separation. See the official
[linking design](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Linking.md)
and [Canonical ABI](https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md).

SHA-256 could use the same kernel behind an efficient component interface.
Small inputs are sensitive to fixed call overhead; large inputs retain any
per-byte copying cost. CandidX also needs its compiler specialization: a generic
component interface does not by itself describe arbitrary Motoko argument
types or permit traversing their heap representation. Generated concrete
bindings, an intermediate value representation, or preencoded bytes would be
needed. Keeping the compiler component can preserve specialization even if
runtime packaging later changes. Pure calls need no new component instance on
each invocation, but borrowing Motoko memory still requires the GC/lifetime
contract above.

No component-versus-plugin instruction benchmark has been performed. The
native-library measurements below cannot determine that penalty. Comparisons
should use an optimized component implementation and the same kernels; costs
from local prototypes are not universal component overhead. Historical source
references and research notes are in
[`component-research.txt`](../benchmarks/results/native-comparison/component-research.txt).

For these pure compute operations, the recommended direction is to retain the
current direct-memory integration. SHA-256 is a candidate for a future efficient
component interface. CandidX should keep its compiler specialization even if its
runtime is packaged differently. Comparing the same kernels through a deployable
component path is necessary before assigning a slowdown percentage.

## Implementing another plugin

The versioned compiler interface is
[`Plugin_codegen`](https://github.com/infu/motoko/blob/codex/compute-plugins/src/codegen/plugin_codegen.mli). A package registers:

1. A unique package name, ABI version, optional runtime filename, and runtime import
   signatures.
2. Public Prim bindings, each with a unique internal identity, an argument
   policy, explicit type parameter modes, result-type function, and an
   interpreter reference implementation.
3. A generator functor over `Plugin_codegen.Backend`. It receives getters for
   already evaluated vanilla arguments and returns code with an explicit result
   representation. `Managed` leaves one vanilla value; `Tuple n` leaves the
   fields of a statically known tuple. The compiler checks the exact tuple arity
   without promoting opaque type bounds, and packs it only when needed by the
   caller. Arguments use the ordinary sequence calling convention, avoiding an
   implicit heap tuple. Specialization includes input types, explicit type
   arguments, and the checked result type.

The package's required ABI must be fixed at build time, such as `abi = 1` for
the current SDK. Do not copy `Plugin_codegen.abi_version` from the running
host: a plugin built with opaque or interface-only dependencies can otherwise
adopt a newer host's ABI without having been rebuilt for its semantics.

`Fixed` input schemas depend on explicit type arguments; `Shared` accepts
variadic shared inputs. Parameters declare `Concrete` or `Opaque` mode.
Concrete schemas require known layouts. Opaque parameters preserve arbitrary
Motoko values and their generic relationships without inspecting their layout.
Intrinsics can return records, variants, arrays, options, text, scalars, and
generic managed values. JSON uses
`from_json<T>` to specialize the decoder for `T` and return typed `#ok`/`#err`.
The backend constructors manage forwarding, initialization, allocation, and
write barriers, including early failures during array construction. No callback
or safepoint may run during the borrowed-pointer interval. See the
[authoring guide](adding-a-plugin.md) for package registration and the SDK contract.

The SHA-256 package is the small example. CandidX demonstrates recursive type
specialization. Kernel modules are Wasm64 shared libraries with `dylink.0`
metadata, imported compiler memory/table/PIC globals, and only the approved
allocation and trap function imports. Read-only constants may have data
segments. The linker reserves their static data and table space alongside the
RTS, loads their data at initialization, resolves calls, then removes private
exports from each plugin after its imports have been resolved. Different
plugins may use the same private Wasm export names; their package names and
public Prim bindings must remain distinct.

Active data and element segments must fit their declared `dylink.0` memory
and table reserves. Their offsets must use the corresponding imported PIC
base, optionally adding nonnegative `i64` constants. The compiler rejects
inconsistent reserves and out-of-bounds linking indices before relocation.
`GOT.mem` symbols must resolve to defined immutable `i64` globals containing
constant offsets between zero and the memory reserve's size, inclusive.
Imported or already relocated addresses are not supported as relative offsets.

Plugins are trusted compiler extensions. Native components execute inside
`moc`, and linked Wasm shares memory with the application. The import validator
checks the runtime ABI; it is not a sandbox or a proof that an implementation
is pure. Borrowed-pointer runtime kernels must not mutate inputs, retain heap
pointers, keep mutable state between operations, or call a collector. Generated
managed code may mutate caller-owned objects through the typed SDK helpers
described above. Kernel algorithms remain in
the packages rather than the compiler's ordinary runtime.

Runtime authors must validate the Wasm binary before packaging it, for example
with `wasm-validate --enable-memory64 runtime.wasm`. `scripts/build.sh` does
this for the selected plugins. The compiler checks the plugin ABI and linking
metadata; it does not perform complete Wasm instruction-stack typechecking.

## Scope and validation

Dynamic compiler component loading is currently available in native `moc`.
The JavaScript compiler remains buildable but cannot load OCaml `.cmxs`
packages. Supporting it would require packaging the compiler components with
the JS build or a different compile-time component ABI.

Plugin tests live beside each implementation under `plugins/<name>/tests/`,
with composition and GC tests in `tests/integration/`. After building, run
from the Motoko checkout in its Nix development shell:

```sh
../plugins/scripts/test.sh --motoko "$PWD"
```

The validation counts below were recorded before the repository split. Raw
reports retain their original paths and artifact hashes; the split does not
relabel them as new benchmark runs. Compiler-only loader and linker tests
remain in the Motoko repository.

The implementation passes 18 source/IR/Wasm/diagnostic fixtures, the
IC GC stress fixture, package-loading checks, 30 runtime unit tests, repeated-link
relocation tests, and 12 existing Candid/Prim/tuple regressions. The GC fixture
retains nested inputs and outputs across two collection cycles and checks that
SHA-256 of a 65,537-byte Blob allocates less than 256 Motoko heap bytes. Loading
unused plugins produces byte-identical Wasm in the package test.
The post-optimization audit checks 857 additional encoding cases across the
source interpreter, IR interpreter, and compiled Wasm. It compares 20,000
randomized shape collections against the original sequential runtime, both
with balanced joins and with primitive variant collection enabled. SHA-256
matches Python `hashlib` on 5,597 native pointer-ABI cases, including unaligned
buffers and checks that inputs and output guard bytes remain unchanged.
Independent probes also cover primitive vectors, NaN normalization, and depth,
visit, and output limits.

Linker regression tests cover binary table32/table64 decoding, private export
isolation, direct and indirect calls across multiple libraries, and malformed
indices, relocation targets, segment reserves, and metadata lengths. A
clang-built function-pointer plugin and two packages with identical private
export names also compile and execute.

The full existing failure suite gives 411 passes and 11 human-diagnostic
indentation mismatches; a separately built pristine HEAD produces the same 11
mismatches. Native and JavaScript release targets build; JS typechecking and
interpreter smoke checks pass. The development JS build retains its existing
`caml_unix_map_file_bytecode` primitive warning. These checks establish
correctness and allocation behavior, not a throughput comparison against
every possible encoder or SHA implementation.

Reproducible PocketIC instruction and allocation benchmarks are documented in
[`benchmarks/`](../benchmarks/README.md).
They run the same actor against frozen baseline and optimized packages, check
outputs independently, and report every trial. Counts cover the synchronous
operation; input construction, reply encoding, and message-end GC are outside
the interval. The control workload exposes the fixed measurement overhead.

## Native-library instruction comparison

Recorded on 2026-10-11 with PocketIC 14.0.0. Native and plugin implementations
are compiled into the same actor using the same compiler and inputs. SHA-256
uses registry Mops `sha2@0.2.5`. Native CandidX uses the sibling repository at
`94c2868988d98e8f660a9aa569a0ebc36fcda8ea`, with the same `cx` canonical profile
as the plugin. Both native libraries use pinned `core@2.5.0`.

Native CandidX counts include `to_candid(value)` followed by
`CandidX.canonicalize(...)` and successful result unwrapping. The plugin calls
`Prim.to_candid_canonical(value)` directly. SHA-256 compares the complete
`Sha256.fromBlob(#sha256, input)` call with `Prim.sha256(input)`.

| Workload | Native instructions | Plugin instructions | Native / plugin |
|---|---:|---:|---:|
| SHA-256, 32 B | 27,968 | 4,966 | 5.63× |
| SHA-256, 1 KiB | 338,212 | 81,952 | 4.13× |
| SHA-256, 64 KiB | 20,253,300 | 4,888,128 | 4.14× |
| SHA-256, 1 MiB | 323,721,060 | 78,124,848 | 4.14× |
| CandidX, static record | 404,924 | 1,611 | 251.35× |
| CandidX, 64 KiB Blob | 210,032 | 66,322 | 3.17× |
| CandidX, 1,024 sparse records | 88,379,476 | 5,674,118 | 15.58× |
| CandidX, 1,024 fixed records | 37,743,426 | 351,914 | 107.25× |
| CandidX, 1,024 distinct variants | 1,428,890,507 | 2,190,869 | 652.20× |

The complete comparison covers 40 workload entries, including two control
entries, and 414 successful measured phases across 120 fresh canisters. All
three trials produced identical instruction counts, every phase reported zero
synchronous reclamation, and outputs matched their independent oracles.
Counts include instrumentation and output retention; the 256-instruction
control cost has not been subtracted. Input setup, reply encoding, and
message-end GC are outside the interval. These are instruction-count ratios
against native libraries; they do not measure wall-clock or component overhead.

The full [CSV](../benchmarks/results/native-comparison/summary.csv)
also records allocation, reclamation, ordinary Candid encoding, and native
canonicalization of preencoded bytes. That last phase excludes initial Candid
encoding and is not an equivalent end-to-end operation. Raw trials, artifact
hashes, pinned dependencies, and methodology are linked from the
[report](../benchmarks/results/native-comparison/report.txt);
reproduction commands are in the
[benchmark README](../benchmarks/README.md).

The sibling CandidX conformance suite and two 500-random-record fuzz seeds
(`0xcad1d` and `0x5eedc0de`) also passed against the plugin, covering 2,260 typed
record case instances plus the 93-case directed corpus. Directed cases repeat
across seeds, so the execution count is not a count of unique schemas.
Independent canonicality checks, schema-extension invariance, and original-value
recovery through Rust, TypeScript, and Motoko passed. No oracle, canonical-format,
or sibling implementation changes were needed. The standalone Wasm backend was
not executed. Exact commands and scoped coverage are saved in the
[correctness summary](../benchmarks/results/native-comparison/candidx-correctness/summary.json).
