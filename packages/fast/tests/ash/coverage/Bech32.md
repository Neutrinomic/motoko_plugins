# Bech32 and Segwit test coverage

The eight Ash methods exercise `Bech32.encode`, `Bech32.decode`,
`Bech32.convertBits`, `Segwit.encode`, and `Segwit.decode` through their public
`mo:fast` modules. The configuration loads only the Bech32 plugin. The matching
`tests/run/crypto-bech32.mo` runs the same checks through the compiler test runner.

| Ash test | Behavior checked |
| --- | --- |
| `test_generic_bip173_bip350_vectors` | All 14 published generic positive vectors, exact checksum variant, uppercase acceptance, lowercase canonical encoding, empty payloads, alphabet order and reversed alphabet. |
| `test_generic_invalid_vectors` | All published generic negative vectors, plus mixed case, empty/truncated text, embedded NUL and non-ASCII text. |
| `test_encode_hrp_and_length_bounds` | Empty/invalid/oversize HRPs, all printable ASCII HRP characters including `1`, uppercase normalization, mixed-case rejection, invalid 5-bit symbols, and exact 90/91-character limits. |
| `test_convert_bits_values_widths_and_padding` | Independent hand-derived bit-grouping answers, zero and nonzero tails, excessive padding, illegal symbol values and widths, empty input, and exact-grouping round trips for all 64 legal width pairs. |
| `test_segwit_bip350_vectors` | All eight published BIP350 valid address/program pairs, uppercase acceptance and lowercase encoding, v0/v1/v2/v16, plus custom-network HRPs. |
| `test_segwit_invalid_vectors_and_checksum_rules` | Published invalid address vectors, exact error categories, nonzero and excess padding, wrong checksum variants, and rejection of superseded BIP173 v1+ Bech32 examples. |
| `test_segwit_versions_and_program_bounds` | All versions 0–16 across twelve program lengths; invalid versions 17/31/32/255; generic-HRP 90/91-character address bounds; version-dependent checksum selection. |
| `test_callbacks_evaluation_and_retained_results` | Function aliases, exactly-once left-to-right evaluation, retained decoded values across 128 subsequent calls and allocations, and repeated encode/decode operation. |

Published vectors come from [BIP173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki#test-vectors)
and [BIP350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki#test-vectors),
both licensed BSD-2-Clause. Address tests use BIP350's replacement vectors for
witness versions above zero. Expected witness programs are the published
scriptPubKey payloads with opcode and push-length bytes removed. Conversion
answers are derived directly by grouping fixed MSB-first bit strings; the tests
do not generate these expected values with another copy of the checksum kernel.

The Segwit API is deliberately network-generic. The published `tc` network
mismatch examples are accepted with `hrp = "tc"`; applications must compare the
returned HRP with their expected network. Published raw 0x80/0xFF invalid Text
examples are tested as corresponding Unicode code points because Motoko Text
cannot contain invalid UTF-8 bytes.

These are finite correctness checks, not performance measurements or a proof
of every possible address. The suite does not allocate inputs near the
convertBits 16 MiB quota, exercise canister upgrades, or prove GC reclamation.
