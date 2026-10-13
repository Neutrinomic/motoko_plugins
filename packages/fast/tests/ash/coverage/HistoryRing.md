# HistoryRing coverage

Eight public-module Ash tests execute compiled Wasm on PocketIC:

| Test | Contract |
| --- | --- |
| Empty/zero capacity | No retention at zero capacity, continuous sequence after clear, empty operations |
| Flat-array oracle | 11 capacities and 1,000 deterministic mixed mutations each |
| Rotated tail | Pop and bulk-drop keep the live prefix in a chunk shared with the removed head |
| Pages/iterators | Inclusive clamped cursors, huge limits, direct sequence order, detached output array, exact chunk end before absent storage |
| Generic payloads | Nested null distinctions, mutable aliases, closure references |
| Arbitrary Nat/lazy capacity | Subtraction across compact, 64-bit and larger sequence boundaries; capacity above 2^64 allocates lazily |
| Removed references | Occupied slots equal retained values after partial/whole-chunk drops; bounded spare storage; clear releases directory |
| Incremental GC | Mutation and 63/64/65-element drops while a collection is pending, message boundaries, nullable pages, live closure/shared-blob references, retained iterator |

The independent native model fixtures additionally run through interpreter,
lowered interpreters and Wasm, including 405 directed bulk-drop cases and
sequence subtraction while the retained range crosses integer representation
boundaries. Page tests also end exactly at lazy or detached chunk boundaries,
then refill and wrap the same ring. The separate `history-ring-persistence` fixture
checks stable aliases and sequences across upgrades. Ash's test metrics describe
correctness workloads, not the standalone performance benchmark.
