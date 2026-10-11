# SDK and plugin optimization round

Each component had a separate implementation agent and an independent auditor.
Accepted changes reduce repeated work or simplify existing code. ABI 1, public
APIs, typed results, managed ownership, and map structural sharing are preserved.

| Component | Accepted change | Measured result versus the previous implementation |
| --- | --- | --- |
| [SDK](sdk/README.md) | Reuse the array-construction cursor; remove interpreter checks already performed during compilation | 4,096 scalar elements: 13.13% fewer IC instructions; nested values: 3.77% fewer; allocation unchanged |
| [CandidX](candidx/README.md) | Specialize fixed record subtrees and batch their visit accounting | Optional arrays of 1,024 fixed records: 82.02% fewer instructions; Text records: 68.05% fewer; allocation unchanged |
| [JSON](json/README.md) | Build diagnostic paths only on errors; share the number lexer | Focused 1,024-record encode/decode: 34.73% / 23.24% fewer instructions |
| [CBOR](cbor/README.md) | Build diagnostic paths only on errors; calculate literal field lengths during compilation | 1,024-record encode/decode: 35.84% / 30.66% fewer instructions |
| [Pure map](pure-map/README.md) | Fixed-width private depth counters, direct folds, simpler lazy cursors and merge tails | Folds: about 32% fewer instructions; predicate find: 21–27% fewer; full iteration: about 8% fewer |
| [SHA-256](sha256/README.md) | Simplify output handling; enforce fixed digest length at compile time | Identical runtime and actor Wasm, instruction counts, and allocation; slower alternatives rejected |

These are workload-specific before/after improvements, not comparisons with
native libraries. The repository [README](../../../README.md) contains native
library comparisons and the complete map table at 1,000 / 10,000 / 100,000
entries. The SDK interpreter benchmark separately measures CPU time: about
25–28% less for one million generic calls; it is not an IC instruction result.

## Measurement and audit scope

Plugin before/after measurements freeze compiler revision `f1ccbba5`; the SDK
comparison advances it to `c320bf90d`. Every paired comparison uses identical
actors and inputs, three PocketIC trials, output validation, and instruction
and cumulative allocation counters. Historical results are preserved unchanged.
Allocation includes temporary garbage and returned values; it does not measure
peak memory or live memory after GC.

All five packages were then rebuilt together against `c320bf90d`. Fresh
[JSON](integrated/json/README.md), [CBOR](integrated/cbor/README.md), and
[CandidX/SHA-256](integrated/candidx-sha256/README.md) comparisons use those
packages and the same archived actors/inputs. JSON's 1,024-record encode/decode
now cost 5,081,644 / 18,251,729 instructions in the native comparison actor;
CBOR costs 5,395,241 / 7,324,274. These are the headline README values.
Native comparison counts and allocation are unchanged by the SDK update.
The [map integration check](integrated/pure-map/README.md) recompiles all three
actors. Their only executable difference is the embedded compiler-version
string and its startup length constants; measured function bodies are identical.
The full map matrix remains labelled with its measured `f1ccbba5` compiler.

[Combined validation](integrated/validation/validation.json) passes the full
Nix build, 45 SDK fixtures, 62 Rust tests, 52 plugin Motoko fixtures, both
packaging checks, and saved-archive verification. Build inputs and logs are
preserved with the validation record.

The component reports retain raw trials, exact actors, manifests, source and
artifact hashes, reproduction commands, rejected experiments, and independent
audit reports. CandidX also passes the upstream conformance suite and two
500-record fuzz seeds. JSON retains independent syntax/value oracle results;
CBOR retains independent encoded-byte checks. Map testing exercises depth
limits, mutable/closure payloads, and retained cursors across GC.

The audits fixed a JSON large-key error allocation regression before acceptance,
and caught misleading benchmark metadata. Error buffers now reserve their
known key length instead of growing repeatedly. CandidX interpreter and Wasm
visit-limit diagnostics also now agree.

## Tradeoffs retained in the reports

- JSON's small record cases allocate eight extra bytes. Large-key error scratch
  measurements are labelled separately from PocketIC heap allocation.
- Empty SDK arrays add one instruction. Dynamic array bounds, callback checks,
  initialization, and write barriers remain. Record width subtyping requires
  runtime field lookup; an expected type alone cannot prove a physical offset.
- Map shuffled `fromIter`, cursor/snapshot creation alone, and small
  intersection cases still lose to Core in instructions. Point operations are
  unchanged by this round. No alternate algorithm or whole-map copying was
  added to hide weak results.
- The known native serde 64 KiB JSON string decoding stack overflows remain in
  the raw reports. They are not counted as successful plugin speedup rows.
- An ordinary Motoko constructor-identity failure involving a local `T1` alias
  also reproduces on a pre-plugin compiler. Its minimal reproduction is saved
  in the SDK evidence; a broader compiler identity fix is outside this round.

Run `python3 benchmarks/verify-optimization-archives.py` to check the saved
evidence and regenerate summaries in temporary directories without running
benchmarks or modifying the archives. CI runs the same check.
