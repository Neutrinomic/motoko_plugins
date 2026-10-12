# Cryptographic test vectors

- `bip340.csv`: all 19 vectors from
  <https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv>,
  downloaded 2026-10-12 and normalized to LF. The native test verifies every
  acceptance result and all eight supplied-secret exact signatures.
- `bip341-secret-tweaks.csv`: all seven `keyPathSpending[0].inputSpending`
  entries from <https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json>.
  Columns are `given.internalPrivkey`, `intermediary.tweak` and
  `intermediary.tweakedPrivkey`. The native and Motoko tests check exact values
  and agreement between secret/public tweaking.
- `ecdsa-rfc6979.csv`: eight independently generated python-ecdsa 0.19.2
  answers. The reproduction procedure is in
  `packages/fast/tests/ash/coverage/Secp256k1.md` at the repository root.
  Inputs include digests `0`, `n - 1`, `n`, and `2^256 - 1` to exercise
  RFC6979 `bits2octets`, as well as low/high-S and canonical DER encodings.

The runtime's test module reads these fixtures directly. The shared Motoko
public suite embeds their expected bytes to require neither file I/O nor an
external cryptographic oracle at test time.
