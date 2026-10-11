# Automatic comparator dispatch coverage

`Comparators.mo` loads all four native container plugins together. Its 16 Ash
query methods exercise ordinary public Map and Set operations. A separate
interoperability case mixes those calls with explicit scalar helpers on the
same trees. These tests check correctness and allocation; instruction
benchmarks separately establish whether scalar recognition ran.

| Methods (without `test_`) | Assertions |
| --- | --- |
| `nat64_direct_alias_field_and_generic_forwarding` | Core `Nat64.compare` passed directly, aliased, stored in an object field, and forwarded through an extra generic function. Every case reaches all four families with opaque generic keys; an independently specified order includes zero, the signed midpoint, and the unsigned maximum. |
| `implicit_nat64_comparators` | Core-style comparator omission works for construction, lookup, membership, and removal, including the full unsigned boundary order. |
| `equivalent_body_with_unrelated_name` | A scalar comparator with Core's canonical body and an unrelated function name preserves ordering. Swapped variant-result labels preserve reversed order, and an assertion-bearing body retains its guard's effects. Source paths, function names, and control-flow shape alone are not a correctness oracle. |
| `runtime_comparator_selection_and_captured_state` | A mutable comparator field switches between standard, reversed, stateful, and standard functions. One capturing closure changes direction between independently built containers; its side effects remain observable. Two closures sharing one factory body retain their distinct captured directions. |
| `empty_operations_do_not_invoke_effectful_comparator` | Empty reads, removals, replacement, and first insertion call the comparator zero times across all four families. |
| `scalar_looking_impostor_keeps_exact_callback_effects` | A function named `compare` with the canonical scalar tail but a counter side effect is called exactly once on singleton hit/miss probes and equivalent-key updates. Pure inputs remain unchanged. |
| `argument_evaluation_order_and_once_only` | Container expression, comparator expression, key expression, and comparator callback produce exactly `MFKC`, in that order, for every family. A standard comparator-producing expression still runs once. Empty insertions evaluate every argument, including a Map value, while invoking no comparator body. |
| `custom_equivalence_is_not_natural_scalar_order` | A decade comparator collapses distinct scalar keys into one equivalence class. Maps replace the value; mutable Set replaces its representative; pure Set keeps its first representative. Equivalent-key lookup and removal work. |
| `int_comparator_on_nat_subtype_and_large_values` | `Int.compare` supplied as a comparator of Nat keys handles immediate and boxed values through 2^128, and agrees with `Nat.compare`. |
| `distinct_scalar_representations_share_no_wrong_strategy` | Shared generic wrappers receive Bool, Nat8, Int8, Int64, Text, Blob, and Nat64 comparators. Signedness, byte order, string prefixes, embedded NUL, and heap-backed keys retain their expected ordering. |
| `float_custom_total_order_falls_back_correctly` | Core's custom Float ordering preserves negative/positive NaNs, infinities, finite values, and its equality of signed zeros. |
| `fallback_comparator_reenters_automatic_dispatch` | A reversed fallback callback performs ordinary standard-comparator lookups in all four other containers before returning. Nested dispatch cannot change the caller's ordering strategy. |
| `automatic_strategy_preserves_multivalue_results_and_transform_effects` | Pure Map `alter` invokes its transform exactly once on hit, miss, and deletion, with the correct optional old value. Rank and split-lookup preserve two- and three-result native return paths, including absent pivots, in both pure families. |
| `static_helpers_and_automatic_dispatch_can_share_trees` | All four families interleave explicit Nat64 helpers and ordinary standard-comparator insertion, reads, and deletion on the same trees. |
| `nested_optional_keys_keep_custom_callback_values` | An effectful comparator distinguishes `null`, `?null`, `??0`, and a nested unsigned maximum through all four container families. |
| `comparator_dispatch_does_not_allocate_on_membership` | After setup, 1,792 ordinary membership probes with a standard Nat64 comparator allocate zero bytes. An opaque generic key type preserves already-managed search keys; the measured loop creates no iterators, arrays, or boxed search keys. |

The generic helper verifies lookup values, ordered keys, deletion, mutable
aliases, and retention of old pure roots for each comparator form. Callback
counts are asserted only on empty or singleton trees, where the expected number
does not depend on the tree-balancing algorithm.

The allocation test isolates dispatch from argument representation. A concrete
`let key : Nat64 = keys[index]` can unbox a large key, then allocate a fresh box
when passing it to a generic operation. A diagnostic PocketIC control measured
32,768 bytes for 1,536 such calls with either automatic dispatch or explicit
scalar helpers; direct array-element arguments and opaque generic keys both
measured zero. The regression retains its strict zero-byte assertion and uses
the generic path, isolating dispatch from compiler-generated argument boxes.

Run from the plugins repository:

```sh
scripts/test-ash.sh Comparators
# With an Ash checkout supporting mocArgs:
scripts/test-ash.sh --ash-source /path/to/ash Comparators
```

These finite cases do not establish full comparator recognition coverage or
prove that arbitrary custom comparators are lawful. Every tree uses one
consistent ordering for its lifetime; runtime direction changes use fresh trees.
