# Final shared-artifact curve and Bitcoin audit

All checks passed on 2026-10-12. `report.json` records the results and hashes;
`inputs-before.json` and `inputs-after.json` confirm that 147 sources, 18
artifacts and six compiler/RTS paths stayed unchanged during execution.

- Curves: 17 native tests; five fixtures executed by the source, IR and lowered
  interpreters and Wasm, with Wasm validation. Coverage includes 960 Wycheproof
  cases, 36 RFC6979 boundary cases, 19 BIP340 vectors and 24 BIP341 secret tweaks.
  The native audit used the exact locally patched k256 dependency.
- Bitcoin: three fixtures passed in the source interpreter and Wasm with sanity
  checks, including 1,791 Bitcoin Core oracle cases, 15 wallet tweak/signature
  cases, 23 BIP350 cases and additional boundary/rejection checks.

The prior curve report is retained as `curves-previous-evidence.json`. Current
reports, logs and generated curve fixtures are retained here without binaries.
The unrelated BLS wrapper was excluded from the surrounding input snapshot.

From the sibling `motoko_sha` directory, reproduce with:

```sh
nix develop --command python3 ../plugins/tests/crypto-audit/curves/run_audit.py \
  --motoko . --secp ../plugins/dist/secp256k1 --p256 ../plugins/dist/p256
nix develop --command python3 ../plugins/tests/crypto-audit/bitcoin/run.py \
  --report ../plugins/tests/crypto-audit/round2/final-curves-bitcoin/bitcoin-evidence.json
```
