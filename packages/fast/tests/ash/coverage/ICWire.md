# ICWire public module coverage

Suite: [`ICWire.mo`](../ICWire.mo), configured by
[`ICWire.ash.json`](../ICWire.ash.json). It imports `mo:fast/ICWire` and loads
only the `icwire` plugin, with `--force-gc` and `--sanity-checks`.

Run from the plugins repository root with an Ash checkout supporting `mocArgs`:

```sh
scripts/test-ash.sh --ash-source /path/to/ash ICWire
```

The suite contains 25 independently invocable methods for the raw positional
wire contract. There is no message magic, field identity, record envelope or
field length. Record values follow unsigned Candid-label-hash order in the
agreed schema; every optional field writes its presence byte. Variant ordinals
and collection lengths use minimal unsigned LEB128 bounded to 32 bits.

Expected literals follow the contract and are not captured encoder output.
A separate arithmetic ULEB128 oracle supplies unsigned integer and length
expectations. Round trips supplement known answers and are identified below.

| Behavior | Named test (`test_` prefix omitted) |
|---|---|
| Public `Result`/`Error`, concrete typed wrappers as callbacks and record members, exactly-once argument evaluation | `public_result_types_and_typed_wrappers` |
| Conservative sizing without allocations for recursive records, fixed arrays, text ropes and large signed/unsigned integers; successful `unwrap` and successful/rejected `toOption` adaptation; size-only handling of nonfinite floats | `size_bounds_and_helpers_without_allocation` |
| Unit/null have no bytes; booleans, nested options, optional null, tuple concatenation and invalid presence bytes | `null_unit_bool_options_and_tuples` |
| All eight fixed-width integer types, little-endian bytes, unsigned maxima, signed minima and sign extension | `fixed_width_integer_known_answers` |
| ULEB128 boundaries through 512 bits, independent positive/negative SLEB128 endpoints at 9/10, 18/19 and 27/28 bytes, mixed-bit medium integers, 128 deterministic unsigned wire comparisons | `arbitrary_integer_known_answers_and_oracle` |
| Redundant zero/sign extension, legal signed extension and truncated arbitrary/fixed-width integer inputs, including 10/18/19/27/28-byte malformed integers | `nonminimal_and_truncated_integer_rejection` |
| Exact binary32/binary64 answers, signed zero, subnormals, finite maxima; nonfinite encode errors in arrays, records, options, tuples and recursive/mutually recursive payloads with exact offsets; bulk arrays reject existing first/middle/last invalid values before a missing tail and report partial final words | `float_widths_signed_zero_and_finite_values` |
| Compact UTF-8 byte lengths, NUL/multibyte text, raw binary, Unicode scalar boundaries and surrogate rejection | `text_blob_unicode_and_char_wire_values` |
| Eleven malformed UTF-8 forms including overlongs, surrogate encodings, truncated scalars and out-of-range code points; management/anonymous/29-byte principals and 30-byte rejection | `invalid_utf8_and_principal_bounds` |
| Empty and unit arrays, Nat8/Bool arrays, nested arrays/options, Bool arrays followed by another record field, first/middle/last invalid Bool precedence over a missing tail, trailing bytes and an empty recursive uninhabited element type | `arrays_empty_values_and_nested_collections` |
| Independent bytes for arrays of all eight fixed-width integer types, signed/unsigned extrema, empty 64-bit arrays and exact offsets for partial final elements | `fixed_width_arrays_and_partial_final_words` |
| Unframed records in schema hash order, independent declaration order, numeric/escaped labels, zero-width fields, maximum unsigned hash, field-type ordering changes bytes | `positional_records_schema_order_and_zero_width_fields` |
| Explicit null/present/nested optional fields in records; missing fields truncate; added absent fields change bytes and require the same schema | `record_optional_fields_have_explicit_presence` |
| Sorted schema ordinals, changed ordinals after adding earlier cases, numeric cases, ordinals 128/129, unknown ordinals and nonminimal/overflowing/truncated tags | `variant_ordinals_follow_exact_sorted_schema` |
| Recursive records, arrays and variants; mutually recursive schemas; independent recursive ordinal bytes | `recursive_and_mutually_recursive_values` |
| Bulk integer arrays inside records followed by scalar/array fields, empty nested arrays, exact truncated-element offsets and malformed subsequent fields | `positional_record_truncation_and_nested_bulk_arrays` |
| No envelope, every truncated prefix of a known positional value, trailing bytes, compact length boundaries 127/128 and 16383/16384, nonminimal/overflowing/truncated lengths | `compact_length_prefixes_truncation_and_trailing_bytes` |
| Every byte from 0 through 255 against complete Bool, optional-null and one-byte Nat acceptance expectations | `all_byte_bool_and_option_acceptance_oracle` |
| Hostile array counts rejected before allocation, including zero-byte elements and nested item budgets; oversized scalar declarations | `declared_collection_limits_before_allocation` |
| Exactly 128 typed nesting levels succeeds; the next level fails on encode and independent decode; recovery | `depth_limit_at_boundary_and_recovery` |
| Exact 4096-byte unsigned maximum and signed extrema; next-bit encode/decode rejection and recovery | `integer_byte_limit_at_boundary_and_recovery` |
| Exactly 1,000,000 typed visits including array/record roots succeeds, with no field-frame charges; one extra zero-byte element or following field fails, including estimator sentinel; oversized Float arrays reject before element validation; first nonfinite value versus later node-limit error precedence | `zero_byte_array_item_budget_at_boundary` |
| Exactly 16 MiB complete encoded message succeeds; next output byte and oversized input fail, including estimator boundary/sentinel; nonfinite array versus preceding/following byte-limit error precedence; recovery | `complete_message_byte_budget_at_boundary` |
| 100 deterministic rich-record round trips with large integers, text, blobs, principal, arrays, nested options and variants; malformed-call recovery | `seeded_composite_roundtrips_and_failure_recovery` |
| Retained decoded records, blobs, text, options, variants, exact wire bytes, structured errors, patterned Bool arrays, signed-zero/subnormal Float and Float32 arrays, and repeated signed/unsigned integer arrays spanning 9/10, 18/19 and 27/28-byte boundaries survive messages, later calls and two confirmed GC cycles | `decoded_values_and_errors_survive_messages_and_confirmed_gc` |

The GC test uses actor roots and asynchronous message boundaries. It requires
`rts_reclaimed` to increase by more than 4 MiB in each collection phase before
checking retained values. Merely compiling with `--force-gc` is not treated as
evidence that collection occurred.

Large limit checks use update methods. Ash instruction/heap measurements include
test construction, independent expectations and assertions, and are not codec
performance benchmarks. The asynchronous GC test measures its final check only.
No test depends on invocation order or state retained by a previous test.

This is finite behavioral coverage. Compile-time rejection of unsupported types
and label collisions, native runtime checks and source/Wasm agreement belong to
the separate `plugins/icwire/tests` suite. The wire requires an exact agreed
schema and does not promise additive-field compatibility or runtime schema
verification. These tests do not claim Rust IC Wire/Postcard interoperability
or application transport/migration correctness.
