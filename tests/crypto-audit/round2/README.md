# Crypto optimization verification

The [integration report](integration/report.json) records the combined build,
source/artifact inventories, Rust and Motoko tests, Ash checks, and packaging.
Its adjacent logs retain complete command output without accepting new test
expectations.

| Independent checks | Evidence |
| --- | --- |
| Hashes and codecs, final shared artifacts | [Report](hash-codec/final-shared-report.json) |
| Hash/codec optimizations, memory bounds and differential cases | [Candidate audits](hash-codec/report.json) |
| secp256k1, P256 and Bitcoin composition, final shared artifacts | [Report](final-curves-bitcoin/report.json) |
| BLS arithmetic, profiles and bounded message reuse | [Report](bls/report.json) |
| Curve and Bitcoin candidate reviews and promotion records | [Retained evidence](retained/) |
| Public API benchmark coverage, values and provenance | [Table audit](hash-codec/benchmark-table-audit.json), [counterpart review](hash-codec/benchmark-semantic-review.json) |

The [public benchmark table](../../../benchmark_crypto.md) compares native
Motoko and plugins. The [optimization report](../../../benchmarks/crypto/round2/RESULTS.md)
compares the previous and current plugins, including regressions and code-size
tradeoffs. Each report identifies the exact source and artifacts it checked;
candidate results and final combined-build results have separate records.
