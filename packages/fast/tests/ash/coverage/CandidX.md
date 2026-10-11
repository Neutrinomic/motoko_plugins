# CandidX test coverage

Public API: `CandidX.encode(...) : CandidX.Result`, including the public
`Result` and `Error` aliases. The Ash configuration loads only CandidX.

| Ash test | Behavior checked |
| --- | --- |
| `test_zero_variadic_tuple_and_unit` | Exact Candid bytes for zero arguments, unit/null, reserved, booleans, variadic arguments versus one tuple, and argument order. |
| `test_integer_kinds_and_boundaries` | Every fixed signed/unsigned width and extremum, LEB transitions, scalar-kind distinctions, cold big integer, and 180 expanding integer values checked against independent native `to_candid`. |
| `test_float_bits_and_nan_normalization` | Exact Float32/Float64 values, signed zeros, NaN normalization, infinities and subnormal preservation; raw Candid supplies noncanonical NaN payload bits. |
| `test_text_char_principal_and_binary` | Unicode/BOM/NUL, no Unicode normalization, Char/Nat32 identity, management/anonymous principals, empty/nonempty Blob and `[Nat8]` equivalence. |
| `test_option_presence_is_data` | Absent option type erasure, nested presence distinctions, exact option-array joins. |
| `test_record_evolution_and_numeric_labels` | Omission of absent optional fields, retained explicit null/reserved/present fields, nested evolution, numeric labels and maximum unsigned field ID. |
| `test_array_joins_and_type_interning` | Empty-vector kind rules, array order, mixed optional record fields, nested arrays, deduplication of Blob/byte-array and Char/Nat32 shapes, decoding independently with native `from_candid`. |
| `test_variant_narrowing_and_join_order` | Unused cases erased, selected-case preservation, maximum field ID, rewritten variant indices, nested vector joins and native typed decoding. |
| `test_recursive_values_ignore_unused_shapes` | Equivalent recursive declarations, finite recursive lists/trees, uninhabited declarations inside empty vectors. |
| `test_aliases_callbacks_and_evaluation_order` | Alias propagation through generics/records/arrays/options, concrete callback wrapper, exactly-once evaluation in source order. |
| `test_reference_errors_and_recovery` | Function/service references return typed errors; absent/unused references are accepted; numeric-label collision error; successful call after errors. |
| `test_nesting_and_integer_limit_errors` | Nesting/integer size limits, typed error recovery, retained earlier output. |
| `test_seeded_records_and_retained_results` | 150 deterministic heterogeneous optional-record/variant arrays, native decoding, determinism and retained results. |
| `test_fixed_shape_depth_boundary` | Exact fixed-record array bytes, deepest fixed-row fields accepted at depth 256, next recursive wrapper rejected, recovery. |
| `test_collection_and_output_limit_errors` | Collection count above 2,000,000; repeated shared text exceeding 32 MiB output; valid call after both errors. |
| `test_dynamic_traversal_limit_boundary` | Just-under and just-over two-million traversal budget with an optional vector of fixed-shape records, plus recovery. |

Exact wire oracles follow the independent CandidX `cx` profile. Several match
the established cross-language CandidX conformance vectors. Native decoding
and native scalar encoding supplement those oracles; round-trip checks alone
would not prove canonical bytes.

Limits: the seeded cases are reproducible examples, not exhaustive fuzzing.
The separate CandidX repository corpus/fuzz adapter and existing native tests
remain complementary. This module suite does not deliberately exhaust the
1,024-type table or 256 MiB scratch limit, simulate interruption/upgrade, or
prove GC reclamation. It checks retained results across allocations and error
recovery. Compile-time unsupported-schema checks live in the package's
compile-failure suite. Metrics include fixture construction and assertions,
so they are not isolated encoder benchmark results.
