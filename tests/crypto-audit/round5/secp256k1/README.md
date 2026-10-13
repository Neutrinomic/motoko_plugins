# Secp256k1 round-five audit

Found and fixed two inherited BIP340 signing boundary errors. The native signer
rejected nonce hashes at or above the group order instead of reducing modulo n,
and rejected a computed zero signature S. Both direct and prepared signing use
the corrected implementation. Nonce zero after reduction still fails. Signature
encoding now permits zero r/s and rejects wrong widths and noncanonical values.
The public verifier already handled zero components correctly.

[BIP340 signing](https://github.com/bitcoin/bips/blob/f98774a68c23269d9bfa78c8d9c4671ebf4ceb69/bip-0340.mediawiki#default-signing)
requires nonce reduction and serializes S without a nonzero restriction. These
branches have negligible probability with real SHA256. The regression replaces
only tagged-hash outputs in a disposable source copy and exercises the actual
production signer, parser, direct/prepared FFI and debug verification. It is not
a naturally occurring SHA256 vector or a claim of an observed attack.

Three regressions fail on baseline `cf55e909` and pass after the fix in both debug
and release: nonce 0/n rejection and 1/n-1/n+1/maximum handling; zero-S signing and
verification (`d=k=1`, challenge `n-1`); canonical zero-component parsing. The
[baseline diagnostics](baseline-failure.txt) and [native evidence](native-evidence.json)
record exact commands, source hashes and results. The temporary hash injection is
absent from shipped source. No public API, prepared layout or ABI changed.

New ordinary coverage uses the pinned [official reference](oracle/README.md),
first checked against all 19 published verification vectors and eight exact
signatures. Twelve additional exact signatures cover message lengths 55/56/57,
63/64/65, 119/120/121 and 127/128/129, six even and six odd source keys, four
auxiliary patterns, and independently rejected mutations. Native tests replay
these through direct/prepared APIs with unaligned inputs and output canaries.
All 23 operations are checked at several byte offsets; valid input aliasing,
null predicate output, malformed lengths, error precedence, initialized errors
and input immutability are also checked. All **22 native tests pass in debug and
release**, including the existing arithmetic/protocol suites.

Source review covered the public module, OCaml reference, compiler bridge,
512/64-byte prepared formats, fixed tables, arithmetic/scalar bounds, DER/high-S,
tweaks, infinity, field wrap, borrowing and secret-dependent operations. Prior
rounds already test broad Wycheproof/official vectors, independent table constants
and actual-GC lifecycle. No duplicate large corpus was added. Recovery is not an
exposed operation. The separate P256 lane owns the shared ECDSA rare-error
reference alignment; it is not part of this Schnorr patch.

The nonce reduction uses the existing constant-time scalar reducer, and its
local is zeroized. Signing still uses constant-time point operations; variable-time
helpers remain limited to public verification. This is source-level review,
not a formal constant-time or secure-erasure certification.

Reproduce native checks inside the selected SDK environment:

```sh
bash tests/crypto-audit/round5/secp256k1/run-native.sh
```

The hook uses its scoped Cargo.lock and pinned test-only oracle. A fresh checkout
may fetch locked Cargo dependencies; set `CARGO_NET_OFFLINE=true` for cached runs.

Central validation against the rebuilt runtime passed all 13 public/composition
fixtures and packaging checks. Both Secp256k1 fixtures passed source, IR, lowered
and Wasm execution plus Wasm validation. Ash passed all nine existing Secp256k1
tests, both new `Secp256k1Audit5` tests, and the prepared-composition test that
requires an actual collection. [Public evidence](public-evidence.json) records
artifact and log hashes. Runtime SHA256 is
`730329b0a01941777375b0b60f7d4454ae7f609cb3d7cab3c127896ebd074d02`.
Focused performance and emitted-Wasm review remain integration-owned.
