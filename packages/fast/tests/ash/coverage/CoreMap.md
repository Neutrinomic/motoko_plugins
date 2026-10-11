# CoreMap coverage

`CoreMap.mo` exercises both public functions of `mo:fast/CoreMap` in four Ash
methods, loading only the mutable-map native plugin. The immutable source or
destination is `mo:core/pure/Map`, not the native pure-map plugin.

| Public function | Ash methods and assertions |
| --- | --- |
| `toPure` | `test_empty_both_directions`: empty conversion; `test_large_both_directions_and_orderings`: 700 entries, ascending/descending ordering, complete independently constructed core-map contents, nullable payloads, source clearing leaves result bindings intact; `test_equal_key_comparator_preserves_stored_keys`: comparator-equal record keys retain the actual stored replacement; `test_shared_keys_values_and_closures`: keys, values and closure state remain shared by reference. |
| `fromPure` | The same four methods cover empty conversion and subsequent reuse; independent 700-entry core inputs in both orders; complete contents and lookup checks; result mutation preserves source bindings; key identity and payload sharing; present-null versus absent values. |

Both directions are tested from independently built source maps, in addition
to a round trip. Converted mutable maps pass `Map.assertValid`. Mutable binding
trees are independently owned while their payload references remain shared.

Limits: these tests use lawful comparators and stable key ordering. They do
not claim exhaustive coverage of all key/value types, invalid comparators,
changing the ordering of stored keys, or mutation during a conversion callback.
