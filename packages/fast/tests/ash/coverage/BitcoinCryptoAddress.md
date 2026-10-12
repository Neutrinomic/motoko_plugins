# Bitcoin hash and address composition coverage

`Bitcoin/Hash.mo` composes SHA256 and RIPEMD160. `Bitcoin/Address.mo` composes
those hashes with secp256k1, Base58Check, and Bech32/Bech32m. Production modules
are original implementations from the Bitcoin specifications; they do not copy
code from the Mops `bitcoin` package.

| Shared test group | Coverage |
| --- | --- |
| `hashes` | Independent Python hashlib HASH160/double-SHA256/tagged SHA256 constants; tag-cache equivalence and domain separation. |
| `legacyAndWitness` | Compressed and uncompressed secret-1 P2PKH, testnet, P2SH, P2WPKH, P2WSH; exact locking scripts; BIP350 witness v16 preserved rather than classified as Taproot; regtest. |
| `bip86` | All three BIP86 internal keys, tweaked output keys, Bech32m addresses, direct output-key encoding, and a fixed scriptPubKey. |
| `bip341Outputs` | All seven BIP341 wallet output-construction vectors: empty and nonempty script-tree roots, tweaked keys, output parity, Bech32m addresses, and scriptPubKeys. |
| `invalidInputs` | Wrong networks/checksums, empty input, invalid hash/program sizes, witness versions, invalid public keys, malformed Merkle roots, and off-curve x-only keys. |
| `signedTaprootSpends` | All seven official BIP341 wallet spending vectors: even/odd internal secret normalization, scalar tweak, prepared sighash, local Schnorr signing with zero auxiliary bytes, exact witness, verification against output key, complete published signed wire transaction; malformed secret/digest/auxiliary input. |
| `signedSegwitSpend` | Official BIP143 key derivation, HASH160/scriptCode, sighash, RFC6979 ECDSA signature, DER+witness, exact published signed transaction; changed lockTime rejects signature. |
| `composedWallet` | Official BIP86 account xpub -> two public BIP32 children -> child xpub -> x-only internal key -> tweaked Taproot address, exercising six plugins together. |

The native fixture `crypto-bitcoin-address.mo` and Ash suite
`BitcoinCryptoAddress.mo` call the same assertion groups. The Ash configuration
loads sha256, ripemd160, base58, bech32, secp256k1 and hmac-sha2.

Vector sources:

- [BIP86 test vectors](https://github.com/bitcoin/bips/blob/master/bip-0086.mediawiki).
- [BIP143 native P2WPKH signing example](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki).
- [BIP173 SegWit encoding](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki).
- [BIP350 valid witness address vectors](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki).
- [BIP341 Taproot output construction](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki).

The native scalar parser checks TapTweak against secp256k1's group order, not
its field prime. A null Merkle root means no script tree; an explicitly supplied
root must contain exactly 32 bytes. Neither this module nor its tests performs
script execution, wallet key custody, transaction broadcast, or network lookup.
Testnet and regtest legacy version bytes intentionally coincide; witness HRPs
distinguish the networks.

Validation completed: the shared fixture passed the source interpreter, IR,
lowered IR, compiled Wasm validation and execution with sanity checks. All eight
Ash/PocketIC methods passed, including the locally signed BIP143 and BIP341
transactions. Ash instruction/heap values include assertions and fixture setup;
they are correctness-test metrics, not isolated performance measurements.
