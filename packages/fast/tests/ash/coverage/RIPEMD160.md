# RIPEMD160 test coverage

The module requires only `ripemd160`. Public API: `digest`, `init`, `update`,
`finalize`, and mutable `Digest` class (`write`, `sum`, `reset`).

| Ash test | Coverage |
| --- | --- |
| `test_independent_binary_vectors_and_streaming` | 26 fixed OpenSSL/hashlib RIPEMD-160 answers, lengths 0–65,537; binary bytes; 55/56/57 padding, 63/64/65 block, later transitions; irregular chunks; exact canonical state equality; repeat finalization, empty writes, retained initial state, unchanged input. |
| `test_forking_and_class_api` | Immutable prefix branches, repeated finalization, class write/sum/reset, exactly-once left-to-right argument evaluation. |
| `test_malformed_states` | Wrong sizes, magic, reserved bytes, length overflow, initial chaining words, nonzero unused buffer; maximum structurally valid byte count; rejected growth. |
| `test_million_a_and_retained_results` | Authors' official million-`a` answer, repeated streaming writes, retained results across substantial allocation. |

Binary expectations were generated independently using
`hashlib.new('ripemd160', bytes((i * 131 + 17) % 256 for i in range(n))).digest()`.
Expected results are fixed in the tests; the plugin never generates its oracle.
The million-`a` value comes from the original RIPEMD-160 authors' vector table.

The native suite additionally covers every official short vector, eight chunk
sizes, unaligned pointer ABI calls, guard bytes, rejected-output initialization,
each invalid initial-state byte and near-limit update arithmetic. The package
run fixture checks every split for lengths spanning both padding branches.
Compile-failure fixtures check wrong input/state types and ordinary function
annotations on intrinsics.

These tests validate finite vectors and boundaries; they do not authenticate
serialized states, simulate canister upgrades, or prove collection behavior.
The benchmark suite records isolated costs separately from Ash assertions and
input setup.
