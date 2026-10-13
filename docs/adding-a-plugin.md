# Adding a plugin

Put each plugin in `plugins/<name>/`. Use a lowercase name with underscores or hyphens;
the directory and manifest name must agree. Registered package names must be unique.

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
using `ocamldep`; no per-plugin Dune project is needed. An external runtime is a Rust
`cdylib` crate. A plugin that emits managed code only omits `runtime_crate`,
registers `runtime = None` and `imports = []`, and ships only its native
component; no dummy Wasm module is needed. The root Cargo workspace discovers `plugins/*/runtime`, sharing
one lockfile and release profile across plugins. Update `Cargo.lock` when
adding a crate or dependency.

An optional `runtime_cfg` list selects documented Rust dependency backends,
for example `["curve25519_dalek_bits=\"32\"", "curve25519_dalek_backend=\"serial\""]`.
Each item becomes a `--cfg` argument only for that plugin's separate Cargo
invocation. The manifest pins the choice; `build.json` records the effective
runtime Rust flags. This field accepts cfg names and quoted values, not arbitrary
compiler options.

From the Motoko checkout in its Nix development shell:

```sh
../plugins/scripts/build.sh --motoko "$PWD" example
```

The build uses that compiler's Wasm64 target, validates the runtime, checks
native loading, and writes `dist/example/`. `build.json` records toolchain
versions, source revisions, compiler binary and source hashes, plugin build-input
hashes, and artifact hashes. Inputs are captured before compilation and checked
again before publishing the package. Generated binaries and
intermediates are ignored by Git.

## Compiler component

Register a `Codegen.Plugin_codegen.plugin` during native module initialization.
Choose unique package names, internal function IDs, and public Prim names.
Private Wasm export names may be reused by separate packages.
Set `types = []` for a plugin without prepared value types.

Pin the required compiler ABI in the source, currently `abi = 1`. It remains
at 1 during development of the compiler PR. Do not read
the running host's `abi_version` as the package requirement: that could accept
a newer host without rebuilding for its semantics.

During this development phase, update the SDK and plugins together. Do not
keep legacy entry points or add backward compatibility shims.

Each binding supplies an argument policy (`Shared` or `Fixed schema`),
a list of explicit type parameter modes (`Concrete` or `Opaque`), a result-type
function, and a continuation-based interpreter reference. A fixed schema maps
explicit type arguments to expected input types, enabling contextual typing of
literals and typed callbacks. Concrete parameters require known layouts;
opaque parameters can preserve generic values, including closures and mutable
payloads, without inspecting them. All occurrences retain the same Motoko type.
The result-type function validates the supported schema and returns its Motoko
result type. Use `Compute_plugin.pure` for callback-free references, or the
provided evaluator's typed `call` operation for ordinary Motoko callbacks. Expected runtime
failures belong in a Motoko `#err` value; the evaluator's outer OCaml `Error`
means an interpreter failure.

A generator over `Plugin_codegen.Backend` receives a specialization record
with `type_arguments`, `argument_types`, and `result_type`, plus a getter for
each already evaluated vanilla argument. Arguments are evaluated left-to-right
exactly once using ordinary sequence arities; no implicit heap argument tuple
is allocated. Return `{code; representation = Managed}` for a vanilla result,
or `Tuple n` for the vanilla fields of a statically known tuple result. The
compiler validates the exact tuple arity (zero or at least two) without
promoting opaque type bounds. Immediate destructuring needs no result allocation;
a context retaining the tuple uses the compiler's ordinary tuple constructor.
Opaque values remain managed, even when their bound happens to be a tuple. Use managed
constructors for records, variants, arrays, options, text, and boxed scalars.
The array builder initializes all slots before running element code, so a
decoder can return an error midway safely. Record and variant builders evaluate
payloads before allocation. No generated code may introduce a GC safepoint. `Backend.Call.local` calls
fully instantiated synchronous local closures through the normal compiler
calling convention. Only vanilla managed references may remain live across
callbacks; borrowed raw pointers may not. The current compiler collects after
synchronous message frames return, so callbacks can allocate and reenter a
plugin without collecting their caller. Do not implement closure offsets or
indirect-call signatures inside a plugin.

Shared generated helpers must work for every type that reuses their code.
In particular, a helper first compiled for immediate scalar elements must not
omit write barriers when later reused for reference-bearing elements. Either
specialize the helper's sharing key by representation, or use universal `Any`
storage types for shared slot writes while keeping injection/projection typed
at call sites. Mutable Set uses the latter approach. Its
[mixed-type GC regression](../packages/fast/tests/ash/coverage/SetGC.md)
exercises scalar-first helper generation followed by reference-bearing sets.

See [JSON](../plugins/json/) for explicit output specialization and typed
errors, and the matching compiler's `src/codegen/plugin_codegen.mli` for the
exact interface. All plugin bindings are compiler intrinsics. Inferred aliases
preserve their specialization; explicit Motoko wrappers provide ordinary
function values when an application needs callbacks.

### Prepared values

A plugin can validate and precompute a key once, then return an opaque value
that the application keeps in its records or maps. Create a descriptor with
`Compute_plugin.Prepared.create ~owner:"example" ~name:"ExamplePreparedKey"`
and list it in the registration's `types` field. The owner must exactly match
the registered plugin name. Prim type names are global, so prefix them with
the plugin name; the public module can export a shorter alias:

```motoko
public type PreparedKey = Prim.ExamplePreparedKey;
```

Use `Compute_plugin.Prepared.typ` in binding schemas. Reference evaluators use
`Prepared.wrap` and `Prepared.unwrap`; generators use `Backend.Prepared.wrap`
on a completed immutable Blob and `Backend.Prepared.unwrap` with the declared
argument type before borrowing its bytes. Wrapping and unwrapping add no Wasm
instructions. Ownership and exact nominal type compatibility are checked when
the compiler generates the call. Ordinary Blob helpers still resolve forwarding
on every borrow.

The private payload contains fully initialized, pointer-free bytes, aligned to
eight bytes. Serialize fields explicitly: a native struct can contain padding,
native pointers or a backend-specific layout. Validate the input in the factory
and never mutate a published payload, retain its native address between calls,
or expose a public Blob-to-prepared cast. Reference and Wasm implementations may
use different private byte layouts while preserving the same typed behavior.

Prepared types are nominal, nonshared and nonstable. Keep them in transient
application state and recreate them after upgrades from the original key.
Erasing a value to `Any` does not provide a way to recover its prepared type.
The backing bytes use ordinary managed memory: copies can remain until GC, and
neither dropping a handle nor upgrading guarantees secure erasure of secrets.

Name factories `preparePublicKey` or `prepareSecretKey`, with an explicit
algorithm profile where needed. Append `Prepared` to existing operations, such
as `verifyPrehashPrepared`. Return typed errors for recoverable input failures;
an operation that cannot fail with a valid handle need not invent an error case.
Benchmark preparation separately from reuse, including payload size and actual
allocation. Test handles retained in application records and maps across
message boundaries and confirmed garbage collection.

## Public Motoko module

Add the user-facing module to `packages/fast/src/`, so callers import it as
`mo:fast/Example`. Import `Prim` inside that module and expose inferred aliases
for typed intrinsics:

```motoko
import Prim "mo:⛔";
module {
  public let operation = Prim.example_operation;
}
```

Do not annotate the alias as an ordinary function or hide concrete type
parameters behind a generic wrapper. Inferred aliases preserve specialization
and add no wrapper calls. Export named result/error types when applicable.
Keep modules independent so importing one does not require unrelated plugins.
Keep all public Motoko sources inside the Mops package; imports must not reach
outside its directory. Update its README and add a test under
`packages/fast/tests/run` loading only the corresponding plugin. The shared
test script discovers these package tests automatically.
Add public API cases to the [Ash suite](../packages/fast/tests/ash/) as well,
using independent expectations or reference models alongside round trips.

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
