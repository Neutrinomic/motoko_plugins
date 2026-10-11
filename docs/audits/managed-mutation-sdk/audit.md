# Managed mutation SDK independent audit

Verdict: **approved**, following documentation correction and stronger permanent
GC coverage. No remaining correctness blocker found. ABI remains 1, with five
typed helpers and no new runtime representation, hidden heap, raw write API,
runtime type validator, or effect framework.

The audit reviewed the complete production diff against
`128a41c060d473e4307dbfcce88b4587312a29b6`, the preexisting array/object helpers,
ordinary assignment code generation, `potential_pointer`, the incremental RTS
write/allocation barriers, intrinsic constant analysis, fixture reference
semantics, invalid-generator packaging tests, and the updated contract.

## Findings and resolutions

- The old trust paragraph said all plugins must not mutate inputs or retain
  state. The owner scoped this restriction to borrowed-pointer runtime kernels
  and documented caller-owned managed state through the typed helpers. Root also
  removed obsolete blanket-purity headings/comments. Reviewed the final wording.
- The initial permanent large-heap test proved an active collection but did not
  deliberately fragment its retained graph. The owner added alternating dead
  and live 512 KiB allocations and asserted more than 192 MiB exists before the
  first message-end collection. Its existing expected output passed unchanged.
  No test-only GC introspection was added to production.

## Correctness review

`Arr.set` and `Object.set` check shape, mutability, and assignment subtyping while
generating code. Concrete aliases normalize; abstract container construction is
rejected rather than manufacturing a value of an opaque type. Runtime array
bounds remain necessary. Generic payloads conservatively retain pointer barriers.
Nested options retain the barrier; statically nonpointer payloads use the same
safe elision as ordinary assignments.

Setters evaluate supplied operands once in function-call order before resolving
the destination. A reentrant value callback may overwrite that same field; the
RTS barrier then reads the **current** old slot, preserving snapshot marking.
Arrays resolve forwarding before indexing. Record lookup resolves the object
and its MutBox, respects width subtyping, and updates the existing cell shared by
closures and aliases. Stored pointers are forwarded during Update. No weak-load
barrier is needed for these strong references.

Construction reuses existing initialized-slot array allocation. Record payloads
are evaluated into managed locals before allocating records or mutable cells;
recoverable early returns cannot abandon partially initialized objects. Every
mutable field gets a fresh cell, while its payload can share ordinary references.
The existing no-safepoint contract remains necessary across local callbacks.
`ComputePrim` stays nonconstant; `Triv` means no suspension, not purity. Ignored
unit results do not erase mutation. The fixture interpreter mutates existing
`Value.Mut` refs rather than replacing alias-bearing cells.

## Independent execution

`run/captured-field.mo` passed source, IR, lowered IR, and Wasm execution with
sanity checks. It tests a public variable also captured by object methods,
record width subtyping, holder replacement during the setter RHS, recursive
node aliasing, and nested construction/mutation callbacks.

`run/subtype.mo` passed the same four engines. Its separate generator explicitly
supplies `Nat` values to `Int` array elements, record stores, and mutable and
immutable record initializers; it also uses a concrete array type alias. This
checks permitted subtyping rather than only equal-type assignments.

`run-drun/fragmented-gc.mo` allocates over 192 MiB, drops alternating 512 KiB
blocks, retains over 96 MiB, then mutates shared records and arrays through
16 ingress calls with forced collection and sanity checks. It checks old/new
payloads, nested writes to the same slot, initialized early-return construction,
and all surviving large arrays after each mutation. Final assertions passed.

An audit-only, read-only generator observes the existing persisted GC phase at
the source-derived metadata offset. The observed first cycle enters mutation
calls in phases `Mark, Mark, Evacuate, Update, Update, Update, Pause`. A separate
audit-only address observation confirms at least one retained large array
actually moved. These fixtures introduce no compiler or RTS changes and expose
no production API. Merely observing a pending cycle or large heap was not treated
as proof of pointer forwarding.

`verify.py` checks successful outputs for every execution stage and rejects IC
trap/error output, missing phases, or missing final success. This is necessary
because `test-runner -a` can accept a failing test's output as an expectation.
The final run used no `-a` and all verification assertions passed.

The owner also ran the complete native/JS Dune build, Dune unit tests, 51 SDK
fixtures, and packaging validation. I inspected those logs. Packaging includes
11 invalid-generator cases (immutable/nonarray containers, wrong assignment
types, missing fields, malformed initializers, and abstract construction), all
rejected with normal diagnostics rather than uncaught internal errors. The
independent audit reran the complete packaging checks successfully as well. The
known JS `caml_unix_map_file_bytecode` warning is unchanged from the baseline;
there were no new OCaml or test warnings.

## Scope and limits

This audits trusted compiler extensions, not a sandbox: generator-supplied types
must describe their emitted values. No mutable map or map benchmark exists in
this SDK change. Allocation and throughput of the forthcoming map still require
measurement against core. Mutable data uses the unchanged Motoko heap/persistence
representation; this change introduces no stable layout migration.

Audit development corrected an invalid equality assertion on recursive mutable
nodes. An initial movement probe also watched only the active allocation
partition, which correctly did not evacuate; the final probe observes all live
arrays. Neither was an SDK defect, and neither failing pilot counts as passing
evidence. Final sources, outputs, hashes, and the independent result verifier
are retained beside this report.
