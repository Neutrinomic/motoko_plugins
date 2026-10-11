# JSON module coverage

[`JSON.mo`](../JSON.mo) contains 33 independent Ash/PocketIC tests of `mo:fast/JSON`.
[`JSON.ash.json`](../JSON.ash.json) loads only the JSON compiler plugin, so importing this
module does not depend on unrelated plugins. The tests use the public
`encode`, `decode`, `Result<T>`, and `Error` package surface.

From the repository root, after building the plugins and installing the
`fast` package's Mops dependencies:

```sh
scripts/test-ash.sh JSON
```

The Ash version must support the canister `mocArgs` configuration. Use
`--ash-source /path/to/ash` when needed; see the [suite setup](../README.md).
All 33 methods passed on PocketIC with the development compiler and plugins.

| Behavior | Test method (`test_` prefix omitted) |
| --- | --- |
| Null, booleans, unit, empty arrays/records, payload-free variants | `basic_values_and_empty_containers` |
| Nat8/16/32/64 bounds, Nat, numeric and string integer input | `unsigned_integer_boundaries` |
| Int8/16/32/64 signed boundaries, negative zero | `signed_integer_boundaries` |
| Exact positive/negative integers beyond 256 bits and adjacent values beyond float precision | `arbitrary_integer_precision` |
| Every fixed integer width's overflow/underflow and prohibited numeric string conversions | `integer_overflow_and_underflow` |
| Fractions, exponents, leading zeros, signs, whitespace and nonnumeric types | `integer_grammar_does_not_coerce` |
| Float round trips, smallest subnormal, normal boundary, greatest finite value, negative zero, overflow | `float_finite_and_negative_zero` |
| Infinity, negative infinity, NaN and invalid unquoted specials | `float_nonfinite_values` |
| Float32 limits, exact midpoint/tie rounding, no double rounding, nonfinite values | `float32_rounding_and_nonfinite` |
| Independent exact escaped-text output, all short escapes, UTF-16 pairs and no normalization | `text_escapes_and_unicode` |
| UTF-8 scalar boundaries, maximum scalar, single-character restrictions | `unicode_scalar_boundaries` |
| Lone/mismatched surrogates, illegal escapes, raw controls and truncated strings | `invalid_unicode_and_string_syntax` |
| RFC 4648 base64 examples and an all-256-byte round trip | `base64_known_vectors` |
| Nonzero pad bits, missing/excess padding, misplaced padding, URL alphabet, whitespace | `base64_rejects_noncanonical_and_malformed` |
| Management/anonymous principals and all legal principal byte lengths | `principal_known_values_and_lengths` |
| Bad checksums, case, hyphens, whitespace and wrong JSON types | `principal_rejects_noncanonical` |
| Lexical field order, literal `_42_` names, escaped names, ignored nested data and public type members | `record_names_order_and_unknown_fields` |
| Missing required vs. optional fields, typed error path/offset | `record_missing_required_and_optional` |
| Duplicate known/unknown/escaped keys, including ignored nested objects | `duplicate_keys_include_ignored_subtrees` |
| Variant payloads, unit cases, unknown/multiple tags and nested payload paths | `variant_shape_and_payloads` |
| Arrays, heterogeneous tuples, exact tuple arity and bad element paths | `arrays_and_tuple_shapes` |
| Direct and tagged options, all four states of `???Null` | `options_preserve_all_null_distinctions` |
| Incorrect tagged-option field/count/payload with paths and offsets | `tagged_option_errors` |
| Recursive record, list, variant and recursive nested error paths | `recursive_records_lists_and_variants` |
| Representative application record, arrays of records, optional defaults | `nested_application_record` |
| Root, array, object, slash/tilde/empty/Unicode JSON Pointer paths and UTF-8 byte offsets | `error_paths_and_utf8_byte_offsets` |
| 24 malformed documents, trailing content and array pre-scan error precedence | `malformed_json_corpus` |
| Local/record aliases, heterogeneous specialization, argument evaluation once, concrete callback wrapper | `aliases_and_argument_evaluation_once` |
| 128 deterministic generated records checked against independent exact JSON, shuffled fields/whitespace and unknown subtrees | `deterministic_generated_record_oracle` |
| 128 partial allocation failures interleaved with successes, preserving earlier decoded values | `repeated_partial_failures_preserve_live_values` |
| Recursive encode/decode depth limits and subsequent successful calls | `depth_limits_and_recovery` |
| Exactly 4096 digits accepted, 4097 rejected, encode limit path and offset | `integer_digit_limits_and_error_paths` |
| Oversized input text, collection item quota and recovery | `text_byte_and_collection_item_limits` |

The generated-record oracle assembles the expected JSON independently; it does
not derive expected bytes using the encoder under test. Fixed vectors also
check encoding and decoding separately, so symmetric codec mistakes cannot
pass solely because a round trip succeeds. Error assertions check semantic
kinds and useful paths/offsets; messages must be nonempty without freezing
incidental wording.

These tests exercise deployed Wasm behavior. They do not claim exhaustive
fuzzing or a proof of correctness. Source/IR interpreter agreement, forced GC
and heap evacuation, malformed raw UTF-8 bytes that cannot be represented as
Motoko `Text`, and compile-time rejection of unsupported types are covered by
the separate compiler/plugin tests. The byte and item tests check rejection
above quotas; they do not allocate every possible value exactly at each quota
or test platform out-of-memory behavior.
