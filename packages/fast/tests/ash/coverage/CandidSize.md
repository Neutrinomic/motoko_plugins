# Candid size estimate coverage

Public API: `CandidX.estimateSize(...) : Nat`, with only the CandidX plugin loaded.

| Ash test | Independent checks |
| --- | --- |
| `test_scalars_and_references` | Actual native Candid Blob size for zero/variadic arguments, all fixed integer widths, Unicode Char, Float, principal and service; lexical and external function sentinel parity; absent function options; single evaluation; erased mutable values. |
| `test_dynamic_values_and_unused_schema` | Full unused variant schema, recursive list, unselected function variant, and 100 seeded heterogeneous record/vector values compared with actual Blob sizes. |
| `test_large_integers_without_allocation` | Both signs across compact and magnitude-tier boundaries up to 65,536 bits; zero allocation measured around the estimator alone; actual native Blob oracle outside that interval. |
| `test_fixed_arrays_and_text_ropes` | 10,000 fixed-width records including optional/variant payload bounds, 64 KiB Blob, multibyte UTF-8 rope, empty vector, nested options; zero estimator allocation and actual Blob oracle. |
| `test_bounded_work_depth_and_recovery` | Shared recursive DAG with exponential expansion, deep small list, million-element dynamic array, conservative sentinel, successful next call. |

The native `tests/run/candid-size.mo` fixture separately checks all three
interpreters/compiled Wasm, aliases and argument evaluation, erased mutable
cycles, work/depth limits and recovery. The compile-fail fixture rejects mutable
input that has not been erased to the shared `Any` type.
The separate `tests/run/candid-size-overflow.mo` fixture builds a tiny shared
tuple DAG with enormous expanded size and checks fixed-width saturation,
array multiplication and variadic addition limits, recovery, and zero
estimator allocation.

Ash instruction/heap metrics include setup and the independent oracles. They
are correctness-test costs, not the estimator benchmarks; see
[the focused comparison](../../../../../benchmarks/candid-size/README.md).
