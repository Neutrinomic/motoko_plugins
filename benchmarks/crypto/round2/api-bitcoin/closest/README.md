# Closest published Bitcoin implementations

This supplement fills two previously blank pure Motoko comparison cells without changing the frozen plugin fixtures. `override.json` supplies explicit comparison identities, contract labels and visible table footnotes. `cases.json` contains only the two new pure peers.

`Address.taprootSecretKey` composes existing `bitcoin@0.2.1` Jacobi/Common operations and tagged hashing with the audited even-Y secret-scalar tweak composition. The complete empty-tree BIP341 operation, including both public-point derivations and all scalar/length checks, is timed. Independent Python affine arithmetic verifies the returned secret and its output-point equation. This reference code uses variable-time Nat/NAF arithmetic, so the table identifies its different security contract with `Bitcoin-secret-composed`.

`Transaction.TaprootHasher.signatureHash` uses the package's existing one-shot `createTaprootKeySpendSignatureHash`. Its actor is copied byte-for-byte from the previously measured pure one-shot fixture. The plugin prepared method is cold: its first lazy common-hash computation remains timed. Both process the same ten-input transaction and produce exactly the same independently derived digest. The visible `Bitcoin-uncached` note identifies the package's lack of retained caching; it is not presented as an equivalent reusable-hasher API.

Five blanks remain, documented in `unavailable.json`: BIP340 key-path signing; BIP143 one-shot, constructor and method; and a Taproot common-hash-state constructor. The pinned packages do not expose these operations. A new signing or signature-hash implementation would not be a published-package comparator, and a fabricated wrapper constructor would measure different work.
