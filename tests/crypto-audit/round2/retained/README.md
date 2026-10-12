# Retained candidate evidence

These are unchanged copies of the selected secp256k1, P256 and Bitcoin round-two promotion and audit records. They describe isolated candidate runs; final combined-build validation belongs in [integration](../integration/). [manifest.json](manifest.json) records each copied file's original path, SHA256 and size, and separately pins 60 promoted production files checked when this inventory was created.

| Component | Copied evidence | Evidence already retained elsewhere |
| --- | --- | --- |
| secp256k1 | [Promotion manifest](secp256k1/promotion-manifest.json), adapter patch, [independent execution](secp256k1/independent/evidence.json), [encoding checks](secp256k1/independent/encoding/evidence.json), logs and original audit scripts | [Vendored dependency provenance, exact patch, licenses and registry comparator](../../../../plugins/secp256k1/runtime/vendor/k256/VENDOR.md) |
| P256 | [Final candidate report](p256/round2-report.json), promotion files and patch, [fresh execution evidence](p256/independent/evidence.json), native/Motoko/Ash logs, [combined review](p256/review/combined-review.json), recoding checker and reviewed Wasm text | [Independent comb-table generator and proof](../../../../plugins/p256/tests/vectors/README.md) |
| Bitcoin | [Promoted source hashes](bitcoin/candidate-source.json), patch, [static review](bitcoin/review.json), [execution audit](bitcoin/audit.json), path differential fixture, official fixture/Ash logs | [Common oracle generators and fixtures](../../bitcoin/) |

Reports retain their original absolute paths and candidate-era status wording. A path mentioned inside a report is a reference, not a claim that its target was copied: use `copied_files` or `already_retained_repository_files` in the manifest to locate retained evidence. Original audit scripts are historical harness snapshots and may require their original staging layout; they have not been rewritten into new runners.

P256's fresh report records the comment-only source change after validation and the identical executable artifacts. Its copied stale `findings.json` and precursor-only reviews are excluded. The secp256k1 [documentation refresh](secp256k1/docs-refresh.json) similarly explains the metadata change after audit. Bitcoin's isolated execution audit used the frozen earlier primitive artifacts; it validates the promoted composition source, and does not establish final combined primitive validation. Any `implementation: native` label inside older candidate performance records means the plugin variant; the public benchmark table uses **native** for pure Motoko.

P256's report pins an older external comparison-file hash. Its [exact historical version](../../../../benchmarks/crypto/round2/source-versions/p256-combined-f9cb7ec6ce85107e0972bd88f97c579e46540fdc8ee2457a3fa25e084715b229.json) is retained by the benchmark owner. The current comparison has regenerated metadata; all 25 measurement rows still match the private candidate copy and every measurement field embedded in the report. The manifest records this version relationship separately. Its eight other audit/log reference hashes match.

No binary artifacts, build caches or duplicate benchmark archives are copied here. Benchmark measurements remain under [benchmarks/crypto](../../../../benchmarks/crypto/); hash/codec and BLS audits remain in their [own](../hash-codec/) [directories](../bls/).

Verify copy integrity with `python3 tests/crypto-audit/round2/retained/verify.py`; add `--production` to also compare the promoted source files with their candidate pins.
