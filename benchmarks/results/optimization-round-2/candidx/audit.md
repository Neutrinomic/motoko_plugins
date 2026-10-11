# Independent CandidX audit, second optimization round

**Approved.** The final candidate has no unresolved correctness finding. The
review covers the generator, runtime removals, registration, error tables,
unchanged interpreter semantics, final measurements and retained regressions.
The audited generator SHA-256 is
`8d3d89db79e68f8c7a551a33101845333b2604efaf1e1bf4a2db5790d5287e54`;
complete source and package hashes are in [candidate-build.json](candidate-build.json).

The specialization applies only when every declared variant payload has a
fixed, supported primitive opcode; `Empty` is excluded. An input element sets
one bit corresponding to its declared case. Distinct selected cases are then
emitted once, in ascending unsigned Candid field-ID order. Existing tag
dispatch still uses Motoko heap hashes, so numeric Candid labels are not
mistaken for heap tags. Empty and singleton arrays preserve their prior paths.
Payload order, payload encoding and canonical wire-type numbering are unchanged.

Bits are `i64` values, including positions 31, 32 and 63. Tests compare the
complete word with zero before branching, and masks use positions modulo 64.
The shape function is always emitted as a real shared function, whose Wasm
locals start at zero on each call. Repeated and nested arrays cannot inherit
previous bits.

Each nonempty word invokes one generated helper containing at most 64 field
checks. Its memoization key is the unambiguous ordered sequence of unsigned
field IDs and signed primitive opcodes. These are exactly the facts that
determine its code; original source width and word number are unnecessary
because every word starts at relative bit zero. Equal labels with different
payload opcodes have distinct keys. A helper returns any field error before
continuing, and its caller checks that status before finalizing the builder.
Arguments are passed explicitly; no caller-local getter leaks into a helper.

The removed collector modes and payload checks have no remaining caller.
Its per-element count was redundant with the unchanged array-length check and
the exact two visits charged per variant element. The generic field builder
retains label, reference, order, field-count, lifecycle and scratch checks.
Depth, total visits, output type count, integer/text length and output-byte
limits remain enforced. A 999,999-element array inside a record consumes
exactly 2,000,000 visits and succeeds; the next length returns the expected
typed error, followed by a successful call. No callback, suspension, GC
safepoint, persistent allocation or raw Motoko layout access was introduced.
Input loads retain the compiler's forwarding barriers.

Independent checks against the final package:

- All 23 remaining Rust tests and all 15 Motoko fixtures passed. Six removed
  Rust tests exercised only the deleted collector; general builder, limit,
  lifecycle and canonicalization tests remain.
- [The additional oracle fixture](audit-fixtures/candidx-bitmap-exhaustive.mo)
  passed in source, IR, lowered-IR and Wasm execution. It checks all 256 subsets
  across positions 0/31/32/63/64/95/127/128 with mixed Nat/Bool/Nat8/Text payloads
  against independently constructed canonical bytes. Three further assertions
  check helper reuse across different word positions and separation of equal
  labels with different payload opcodes.
- Final upstream conformance passed, including 93 directed typed cases and 61
  frozen goldens. Both final 500-record fuzz seeds (`0xcad1d`, `0x5eedc0de`)
  passed 1,130 typed cases each, original-value roundtrips and independent
  canonical-byte checks. Their recorded source files did not change during
  the runs. These expensive suites were inspected rather than duplicated.
- All 21 source hashes for each package match the actual baseline commit or
  final files; both package artifact hashes per version and all ten measured
  actor Wasm hashes and lengths match. The compiler remained the frozen
  `c320bf90d` build. [The summary validator](verify-summary.py) passes.

There are 93 paired phases with three deterministic trials each: 279 samples
per version, 558 total. Sources, case manifests, runner hashes, output lengths
and output hashes match between versions; synchronous reclaimed bytes are zero.
Across the 40 plugin/control rows, 15 improve, 22 are unchanged and three are
slower. Repeated 6,000-element/64-tag input falls from 10,756,821 to 6,651,184
instructions and from 276,776 to 16,504 allocated bytes. The separate native
comparison actor measures 6,651,200 instructions; its 16-instruction overhead
is preserved in the report, not substituted with the focused actor's result.
Allocation means cumulative allocation during the measured call, not peak or
retained memory.

The tradeoffs are explicit and accepted by the coordinating agent. For a
4,096-case declared type, two equal tags, two distant tags and 65 spread tags
cost **4.13%, 6.82% and 13.59% more instructions**, respectively, while each
allocates eight fewer bytes. The wide actor grows from 2,375,752 to 2,531,571
bytes (**6.56%**); other measured actors grow 2.28–2.86%. Intermediate inline
emission failed IC function-complexity validation at this previously supported
width. Bounded word helpers fix that regression, and the final 4,096-case actor
installs and passes all measurements. An 8,192-case baseline already fails IC
validation and is archived as a failed installation, not a successful sample.
No alternate collector or compatibility path remains; production code is 97
lines shorter, excluding deleted collector-only tests.
