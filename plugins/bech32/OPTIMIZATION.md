# Decode optimization

The first implementation searched the 32-character alphabet for every decoded
symbol. The current runtime validates printable ASCII and then uses one
immutable 128-byte reverse table indexed by the input byte. Both letter cases
map directly to the same 5-bit value; invalid entries remain 255. Mixed-case
validation still runs separately before decoding.

Three PocketIC trials per workload, each in a fresh canister, produced identical
instruction counts. Encode results and managed allocation are unchanged.
The paired workload source, exact outputs, compiler, runtime artifacts and
checksums are preserved by the crypto benchmark harness.

| Workload | Initial instructions | Current instructions | Reduction |
| --- | ---: | ---: | ---: |
| Bech32 decode, 33 groups | 9,543 | 9,231 | 3.27% |
| Bech32m decode, 33 groups | 9,546 | 9,234 | 3.27% |
| Bech32 decode, 53 groups | 13,083 | 12,611 | 3.61% |
| Bech32m decode, 53 groups | 13,086 | 12,614 | 3.61% |

The plugin runtime artifact decreased from 4,220 to 4,007 bytes. Against pinned
`bitcoin@0.2.1`, the current 33-group Bech32 encode takes 5,846 instructions
versus 50,233; decode takes 9,231 versus 56,095. These are per-call workload
measurements, not throughput projections for every address or canister.

Local evidence: `benchmarks/crypto/results/bech32-native-initial/results.json`
and `benchmarks/crypto/results/bech32-native-candidate/results.json` (including
three oracle-checked trials each). The standalone runtime sources corresponding
to those rows are frozen in `_build/crypto-stage/bech32-o1if8gzb` and
`_build/crypto-stage/bech32-fcsk_ga9` respectively. Each benchmark result directory
also preserves its own frozen inputs and build provenance.

The optimized runtime passed the same native vector/conversion/guard checks,
independent OCaml interpreter fixture, Wasm64 execution with compiler sanity
checks, and all eight public Ash methods. No valid-input behavior or error
category changed.
