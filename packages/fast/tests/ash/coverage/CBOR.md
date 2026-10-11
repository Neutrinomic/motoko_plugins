# CBOR module coverage

Suite: [`CBOR.mo`](../CBOR.mo), loaded with only the CBOR
native plugin using [`CBOR.ash.json`](../CBOR.ash.json). All operations
go through `mo:fast/CBOR`; the suite does not call CBOR primitives directly.

Run from the plugins repository with an Ash version that supports `mocArgs`:

```sh
scripts/test-ash.sh CBOR
```

Use `--ash-source /path/to/ash` if the installed Ash lacks `mocArgs` support;
see the [suite setup](../README.md). Ash compiles the actor and executes its
34 independent tests on PocketIC. No test depends on invocation order or
persistent test state.

| Behavior | Named test (`test_` prefix omitted) |
|---|---|
| Public `encode`, `decode`, `Result`, `Error`; aliases through local bindings and records | `public_alias_and_result_types` |
| RFC integer heads at 23/24, 255/256, 65535/65536, 32-bit and 64-bit boundaries; both signs | `integer_wire_boundaries` |
| Independent major-type-0/1 wire oracle for 512 deterministic 64-bit values and their negative counterparts | `integer_deterministic_oracle_corpus` |
| All eight fixed-width integer types, extrema and out-of-range inputs | `fixed_width_integer_extrema`, `integer_range_errors` |
| Tags 2/3, 64-bit transition, leading zero magnitudes, empty magnitudes, wrong tag payload type | `bignum_tags_and_canonicalization` |
| `Bool`, `Null`, unit, empty record/array/text/blob, empty `None` containers | `bool_null_unit_and_empty_values` |
| ASCII, NUL, multibyte Unicode, scalar boundaries, empty/multiple-character `Char` errors | `text_unicode_and_characters`, `utf8_rejection_corpus` |
| Blob versus `[Nat8]` representations and type mismatch | `blob_and_nat8_array_are_distinct` |
| Management/anonymous principals, exact 29-byte limit and 30-byte rejection | `principal_byte_mapping_and_limits` |
| Known half/single/double float wire bytes, shortest exact format, signed zero | `float_shortest_rfc_encodings` |
| NaN canonicalization, infinities, Float32 rounding to even, underflow, extrema and finite overflow | `float_nan_infinity_and_float32_rounding` |
| Every one of the 65,536 binary16 bit patterns, both `Float` and `Float32`; canonical NaN normalization | `float_all_binary16_encodings` |
| Rejection of implicit integer/float, boolean/integer, text/blob and null coercions; `None` cannot decode a value | `no_implicit_scalar_coercions` |
| Arrays, tuples, lengths at 23/24 and 255/256, tuple-length errors and element paths | `arrays_tuples_and_length_heads` |
| Text/blob lengths at 23/24, 255/256 and 65535/65536 with independent header oracle | `text_and_blob_length_heads` |
| Source record names, numeric-looking names, deterministic encoded key ordering and 23/24-byte key boundary | `record_names_and_deterministic_order` |
| Missing required/optional fields, ignored fields, duplicate known/unknown/nested fields, duplicate nonpreferred key heads and non-text keys | `records_missing_unknown_and_duplicate_fields` |
| Bare and payload variants, unknown tags, empty/multiple-key maps and payload errors | `variants_payloads_and_shape_errors` |
| Null/present/nested options, `?Null`, record named `some`, invalid option map and nested error path | `optional_null_and_nested_options` |
| Recursive list/tree and mutually recursive types | `recursive_and_mutually_recursive_values` |
| 128 deterministic rich records, large integers, Unicode, options, arrays, variants and canonical re-encoding | `deterministic_record_roundtrip_corpus` |
| Nonpreferred definite integer, string, array, map and bignum-tag heads | `nonpreferred_definite_encodings` |
| Reserved/truncated heads, every truncated prefix of a valid composite message and trailing bytes | `malformed_heads_truncation_and_trailing_bytes` |
| Indefinite arrays/strings/maps, unsupported simple values and tags, including ignored unknown fields | `unsupported_indefinite_tags_and_simple_values` |
| All 256 one-byte inputs against the complete typed `Nat` acceptance oracle; recovery after errors | `single_byte_adversarial_corpus` |
| Error kind, nonempty message, byte offset, nested and multidigit array paths, escaped slash/tilde/NUL/Unicode keys | `structured_error_paths_and_offsets` and exact diagnostic assertions throughout |
| Oversized declared array/map/string lengths rejected before allocation, legal-but-truncated lengths | `declared_length_limits_before_allocation` |
| Valid recursion, nesting quota on encode/decode and recovery | `depth_limit_and_recovery` |
| Exactly 4096-byte integer magnitude succeeds; 4097-byte encode/decode fails; error path and recovery | `bignum_magnitude_limit_and_recovery` |
| Exactly 1,000,000 visited values succeeds; next value fails; nested field error and recovery | `item_budget_at_and_past_limit` |
| Exactly 16 MiB encoded output succeeds (including header); next byte and oversized input fail; recovery | `byte_budget_at_and_past_limit` |
| Retained decoded strings/blobs/options/variants/bignums survive later successful and failed scratch use | `borrowed_data_and_integer_scratch_are_retained` |

The two large byte/item quota tests use update calls. Their measured instruction
counts include input construction, independent oracles and assertions; these
are correctness tests, not codec performance benchmarks. The largest test used
about 1.94 billion instructions and 96 MiB heap delta in the initial run.

This is finite coverage, not proof of correctness or an exhaustive schema/wire
fuzzer. The complete binary16 sweep checks decode/re-encode consistency;
independent known-answer vectors separately anchor the float representation.
The integer corpus has an independent wire oracle; the rich-record corpus is
a roundtrip/idempotence property. Unsupported source types require compile-fail
tests outside an Ash actor. Forced GC, cross-message result retention and
interpreter/Wasm agreement are covered by the repository's separate native
plugin integration suites, not claimed by this actor.
