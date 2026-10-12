# Bech32 round-two workloads

Regenerate with `PYTHONDONTWRITEBYTECODE=1 python3 benchmarks/crypto/round2/bech32-workloads/generate.py`.

The manifest contains 48 native-only cases, all with `family: bech32` and
`plugins: [bech32]`, for `round2/run-stage.py --manifest`:

- 28 generic encode/decode cases: both checksum variants; empty and small data;
  33 and 53 groups; a 90-character address with an ordinary HRP; an 83-character
  HRP with empty data; and a one-character HRP with 82 groups.
- 12 conversions: 8-to-5 and strict 5-to-8 for 20, 32, 40 and 4096 program bytes;
  general 7-to-3, same-width 5-to-5, and empty input in both common directions.
- Eight SegWit operations: encoding and decoding version 0 with 20/32 bytes,
  version 1 with 32 bytes and version 16 with two bytes.

Expected results come from independent Python code in `generate.py`, never from
the native plugin or its OCaml interpreter. Bit conversion constructs a literal
bitstring. The separately written checksum recurrence follows
[BIP173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki) and
[BIP350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki). Generation
asserts published generic checksums and four published SegWit address/program
pairs; those same pairs are used for the SegWit workloads. No downloaded oracle
library or changing external dependency is required to regenerate the suite.

Inputs are assigned in `configure()`. The measured region contains only the
public API call, successful-result unwrap and result assignment. UTF-8 conversion
and decode-result serialization occur in `bytesResult()` after measurement.
Decode bytes include all result fields: HRP UTF-8 bytes, a zero-byte delimiter,
one tag byte, then raw data/program bytes. The generic tag is zero for Bech32 and
one for Bech32m; the SegWit tag is the witness version. This verifies HRP and
variant/version alongside the payload without timing benchmark-only assertions.

Run the baseline and candidate with distinct stage names, using the same manifest
and three-trial protocol provided by `round2/run-stage.py`. This generator does
not execute benchmarks or modify shared benchmark scripts.
