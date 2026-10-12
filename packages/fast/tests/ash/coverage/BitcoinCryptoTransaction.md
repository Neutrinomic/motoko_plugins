# Bitcoin transaction and script coverage

`Bitcoin/Transaction.mo` and `Bitcoin/Script.mo` require only the SHA256 plugin.
They are original implementations from Bitcoin specifications. Production code
is not copied from the Mops `bitcoin` package.

| Ash test | Shared assertions |
| --- | --- |
| `test_bitcoin_core_bip143_bip341_vectors` | All 500 Bitcoin Core legacy sighash vectors; all 14 published BIP143 hashes and two swapped-input variants; seven official BIP341 wallet sighashes; 35 independent Core-derived annex/tapscript combinations; nine signed transaction serialization and ID cases; twelve TapLeaf hashes and six Merkle roots. Both one-shot and prepared hashers are checked. |
| `test_serialization_sighash_and_script_edges` | Every truncation of a minimal transaction; trailing bytes; nonminimal CompactSize encodings and hostile counts; unknown/superfluous witness flags; empty witness item versus empty stack; 252/253/65535/65536-byte fields; invalid outpoints, hash modes, annexes and extensions; historical SIGHASH_SINGLE behavior; minimal PUSHDATA boundaries and standard locking scripts. |

The shared libraries are `BitcoinCryptoTransactionVectors.mo` and
`BitcoinCryptoTransactionCases.mo`. Thin native run fixtures and the Ash actor
call the same assertions, avoiding duplicate vector corpora. Both groups passed
source interpretation, compiled Wasm/WASI execution and Ash/PocketIC. The full
official corpus uses approximately 335 million instructions and 17 MB heap in
Ash; boundary checks use approximately 311 million instructions and 10 MB heap.
These include setup/assertions and are correctness metrics.

Primary vector provenance and source SHA256 hashes are retained in the vector
library. Bitcoin Core vectors are MIT licensed, BIP143 is public domain, and
BIP341 is BSD-3-Clause:

- [Bitcoin Core sighash corpus](https://github.com/bitcoin/bitcoin/blob/master/src/test/data/sighash.json).
- [BIP143 examples](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki).
- [BIP341 wallet vectors](https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json).
- [BIP342 signature extension](https://github.com/bitcoin/bips/blob/master/bip-0342.mediawiki).

An independent reviewer additionally retained a generator and oracle fixture in
`tests/crypto-audit/bitcoin`. It passed 1,791 cases against unmodified Bitcoin Core
v29.0 reference functions: 660 legacy, 495 BIP143 and 636 Taproot combinations.
That corpus includes all hash modes, unknown legacy modes, invalid indices,
missing SINGLE outputs, pushed CODESEPARATOR bytes, a 253-byte annex, and script
path separator positions 0, 0x7fffffff and 0xffffffff. Source and Wasm executions
with sanity checks matched the independent expected bytes.

The parser validates wire structure, not monetary limits, duplicate inputs,
script execution or UTXO existence. Legacy malformed script pushes return null;
callers verifying existing scripts must supply scriptCode after the last
executed separator and apply legacy signature FindAndDelete themselves. Hash
caches capture immutable transaction/prevout records. Display-order transaction
IDs are explicitly distinguished from wire-order outpoints and raw signature
digests in the module documentation.
