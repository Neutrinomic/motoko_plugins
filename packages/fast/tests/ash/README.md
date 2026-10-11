# Public module tests with Ash

These 14 configurations execute **202 checks** (196 distinct Motoko methods)
on PocketIC through Ash. They exercise the public `mo:fast` modules, independent wire
oracles, comparisons with Core containers, error recovery, persistence, and GC.

Run from the plugins repository root:

```sh
# All suites using an installed Ash CLI.
scripts/test-ash.sh

# Use an Ash source checkout through Bun.
scripts/test-ash.sh --ash-source /path/to/ash

# Run selected suites by their names below.
scripts/test-ash.sh --ash-source /path/to/ash JSON Set PureSet
```

The helper installs the `fast` package's Mops dependencies and runs each selected
configuration with verbose output. Mops must be installed; using an Ash checkout
also requires Bun and that checkout's dependencies.

Build the native plugins in `dist/` against the compiler build that **Ash uses**.
Ash selects `moc`, `didc`, and `pocket-ic` from its own toolchain; inspect it with
`ash bin` (or `bun /path/to/ash/src/index.ts bin`). A different `moc` on your shell
PATH does not change Ash's compiler selection. Native plugin packages and the
host compiler must match; rebuild the plugins when changing that compiler.
The helper does not build plugins or replace Ash's toolchain.

Ash must support the canister `mocArgs` configuration field: these suites use it
to pass `--plugin` and, for GC tests, `--force-gc` and `--sanity-checks`. The helper
checks Ash's schema before running. If an installed release lacks this field,
use `--ash-source` with a checkout that supports it.

CI currently runs the native suite and validates archived benchmark evidence;
it **does not run these Ash suites**. The tested Ash checkout has local
`mocArgs` support that is absent from its published revision. A published
revision with that support is needed before pinning Ash in CI.

## Suites and inventories

Each suite name links to its Motoko source. The configuration loads the required
native plugins; individual module suites also verify that importing a module
does not require unrelated plugins.

| Suite | Tests | Main coverage | Configuration / detailed inventory |
| --- | ---: | --- | --- |
| [CBOR](CBOR.mo) | 34 | Exact wire vectors, typed decoding, all binary16 patterns, malformed inputs, quotas, retained results | [Config](CBOR.ash.json) · [Inventory](coverage/CBOR.md) |
| [CandidX](CandidX.mo) | 16 | Canonical bytes, variadic arguments, type joins, recursion, references, quotas | [Config](CandidX.ash.json) · [Inventory](coverage/CandidX.md) |
| [Comparators](Comparators.mo) | 16 | Automatic scalar ordering, aliases and implicit calls, callback effects, multi-value results, allocation | [Config](Comparators.ash.json) · [Inventory](coverage/Comparators.md) |
| [Composition](Composition.mo) | 3 | All eight plugins together, codec pipelines, recovery after failures, retained managed values across messages | [Config](Composition.ash.json) · [Inventory](#composition-inventory) |
| [CoreAPI](CoreAPI.mo) | 12 | Six identical consumer methods run against Core and Fast; implicit comparators/formatters, Core signatures and types | [Config](CoreAPI.ash.json) · [Inventory](coverage/CoreAPI.md) |
| [MapConversions](MapConversions.mo) | 4 | Both Map conversions, independent bindings, shared payloads, comparator-equivalent keys | [Config](MapConversions.ash.json) · [Inventory](coverage/MapConversions.md) |
| [JSON](JSON.mo) | 33 | Independent JSON output, typed decoding, Unicode, numeric limits, duplicates, structured errors | [Config](JSON.ash.json) · [Inventory](coverage/JSON.md) |
| [Map](Map.mo) | 17 | 58 existing functions, mutable aliases, differential operations, B-tree boundaries, scalar keys | [Config](Map.ash.json) · [Inventory](coverage/Map.md) |
| [PureMap](PureMap.mo) | 22 | 100 existing functions, retained versions, ranges, algebra, builders, callback contracts | [Config](PureMap.ash.json) · [Inventory](coverage/PureMap.md) |
| [PureSet](PureSet.mo) | 16 | All 70 functions, persistent AVL operations, rank/split/join, algebra, scalar keys | [Config](PureSet.ash.json) · [Inventory](coverage/PureSet.md) |
| [SHA256](SHA256.mo) | 5 | Independent known answers, padding/block boundaries, million-byte input, aliases | [Config](SHA256.ash.json) · [Inventory](coverage/SHA256.md) |
| [Set](Set.mo) | 15 | All 66 functions, Core semantics, B-tree removal, nested optional elements, scalar keys | [Config](Set.ash.json) · [Inventory](coverage/Set.md) |
| [SetGC](SetGC.mo) | 2 | Shared native helpers, mixed element types, incremental GC and write barriers | [Config](SetGC.ash.json) · [Inventory](coverage/SetGC.md) |
| [Smoke](Smoke.mo) | 7 | Package imports, codec results, hash pipeline, both map modules and Core conversion | [Config](Smoke.ash.json) · [Inventory](#smoke-inventory) |
| **Total** | **202** | | |

`Map` now exposes 61 functions and `pure/Map` 101; `MapConversions` and
`CoreAPI` cover their conversions and `toMap` additions. `CoreAPI` changes only
the imported container package, so implicit argument resolution and ordinary
Core call sites must compile and execute unchanged with either implementation.

### Composition inventory

Methods: `test_roundtrip_pipeline_and_map_queries`,
`test_failures_do_not_poison_later_plugin_calls`, and
`test_gc_retains_results_and_shared_payloads`.

### Smoke inventory

Methods: `test_json_typed_result`, `test_cbor_typed_result`,
`test_canonical_hash_pipeline`, `test_sha256_known_answer`,
`test_mutable_map_aliases`, `test_pure_map_versions`, and
`test_core_map_conversion`.

## What the results establish

Known-answer vectors and independently constructed expectations complement
round trips and differential checks. Container suites test public operations
and invariants with deterministic sequences and boundary sizes. The Set GC
regression also calls native primitives directly to exercise helper sharing
between concrete element types.

Comparator tests preserve aliases, custom ordering, callback effects and
argument evaluation across all four container plugins. Membership through
opaque managed keys allocates zero bytes; typed Nat64 locals can independently
require boxing at generic calls, as detailed in the comparator inventory.

This is finite behavioral coverage, not proof for every input, native branch,
or runtime state. Compile-fail cases, expected traps, interpreter agreement,
and upgrade checks remain in the separate compiler/plugin test suites. The
inventories identify additional limits and which assertions cover each API.
The accompanying native suite passes 103 Motoko fixtures and 57 Rust kernel
tests, plus package compatibility checks, against the pinned compiler.

Ash's instruction and heap figures measure correctness-test closures, usually
including setup, independent oracles, and assertions. The asynchronous GC tests
measure only their final verification. These figures are **not plugin
performance comparisons**. Allocation assertions in selected container tests
check specific no-allocation or bounded-copy contracts; they do not describe
the memory cost of every workload.
