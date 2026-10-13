# Pure Motoko verification controls

These two actors retain the byte-oriented `ecdsa@8.0.1` verification adapters from `round3/controls`, with key, digest and signature literals from the prepared plugins' independent fixtures. The timed result handling matches the native cases: Secp256k1 unwraps the Result and selects the oracle Blob inside the interval; P256 runs a one-iteration loop and keeps the Result for the later oracle query. `cases.json` records the original adapter hashes, these small scaffold changes, exact native comparison groups and copied fixture hashes. Each case is a standalone `control`, with independently expected output `01`; no historical timing is reused.

| Control | Native comparison group | Fixture |
|---|---|---|
| `pure-secp256k1-verify-ecdsa-rfc6979-key1-sample` | `secp256k1-ecdsa-verify-ecdsa-rfc6979-key1-sample-payload512` | RFC6979, secret scalar 1, SHA-256 of `sample`, low-S signature |
| `pure-p256-verify-rfc-sample` | `p256-w8-rfc-sample` | RFC6979 P256 sample key, SHA-256 of `sample`, high-S signature |

Curve construction and immutable input literals stay outside the measured interval. Compressed public-key parsing, compact signature parsing, range checks, signature verification and the public `Result` remain inside. This comparison covers valid inputs only. The P256 library normalizes S internally before verification; the plugin verifies the supplied high-S signature. Their result agrees for this vector, but the comparison does not establish identical malformed-input, canonicality or error semantics.

Dependencies use the existing `benchmarks/crypto/dependencies/mops.lock`: `ecdsa@8.0.1`, including its pinned `core@2` 2.5.0, `sha2@0` 0.1.14, `asn1@3` 3.1.0, `xtended-numbers@2` 2.3.0, `base-x-encoder@2` 2.1.0, `buffer@0` 0.1.0 and `xtended-iter@1` 1.1.0 aliases and their transitive dependencies. No new package resolution is needed. Build and run using the prepared protocol with the same compiler, RTS, PocketIC and frozen runner/dependency pins as the native cases; schedule three fresh canisters for each case.

Report library/native ratios separately from direct/prepared reuse ratios. The controls are not preparation groups, and prepared-call costs exclude the separately reported key factory. Compare the copied fixture hash and bytes against the final native stage before publishing a ratio.
