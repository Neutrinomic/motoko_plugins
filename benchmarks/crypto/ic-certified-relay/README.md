# Client-relayed IC certified data

This report preserves the initial measurements before the subsequent BLS
optimizations. The same fixtures and verifier have since been remeasured:
100,000-entry cold verification now costs **218,268,043 instructions**, and the
cached-delegation/prepared-key path costs **87,091,402**. Root-cache proof cost
remains **904,898**. [Current results and comparison](../bls-verify-round7/README.md).

Canister B can authenticate data committed by canister A using a certificate and
Merkle witness carried by an untrusted client. Our PocketIC prototype measures
about **424 million instructions for cold verification**, **169 million with a
verified delegation and prepared subnet key cached**, and **905,000 with A's
authenticated root cached**, for a proof in a 100,000-entry tree.

The useful shared cache is an authenticated snapshot of A's certified root.
Every client proving a record against that snapshot can reuse it. A fresh,
previously unverified root still requires certificate signature verification.
These are measurements of a bounded research prototype, not a production
certificate verifier.

## What B verifies

The trust chain is:

```text
B's trusted IC root key
  → root-signed delegation: subnet key and authorized canister ranges
  → subnet-signed state tree: time and /canister/A/certified_data
  → A's application Merkle witness
  → the exact record being accepted
```

For an application subnet this normally means two BLS signature checks, plus
SHA-256 tree reconstruction and authenticated path lookup. B must check that A
is in the delegation's authorized ranges and extract A's own certified-data
entry. An NNS/root-subnet certificate does not need the delegation check.
The IC certificate hash-tree domains and SHA-256 are fixed by the protocol.
[Certification specification](https://docs.internetcomputer.org/references/ic-interface-spec/certification/).

A commits up to 32 bytes with the certified-data system API, normally the root
of its application tree. A client obtains the certificate through a query and
submits the certificate, witness and record to B. B verifies locally without a
call to A or the NNS. The existing compiler exposes the network trust anchor as
`Prim.rootKey()`; our prototype checks it against the captured local-network
root. The relay must not choose the trust anchor.
[Certified-data system API](https://docs.internetcomputer.org/references/ic-interface-spec/canister-interface/#certified-data).

## Measured cost

Measured on 2026-10-13 with PocketIC 10.0.0, compiler `9f6ebeedc`, and the existing
`mo:fast` BLS12-381 and SHA256 plugins. Each row has three identical trials for
each tree size, with a fresh verifier canister per trial.

| Verification path | Instructions, 1,000 entries | Instructions, 100,000 entries | Allocated B, 1,000 / 100,000 entries |
| --- | ---: | ---: | ---: |
| Cold: root delegation and subnet signatures | 423,376,817 | 423,716,169 | 102,320 / 117,552 |
| Prepared root key; both signatures still checked | 380,095,882 | 380,435,234 | 100,128 / 115,360 |
| Cached verified delegation; raw subnet key | 211,982,593 | 212,321,945 | 65,408 / 80,640 |
| Cached verified delegation; prepared subnet key | 168,737,010 | 169,076,362 | 65,408 / 80,640 |
| Cached authenticated A root; application proof only | **565,546** | **904,898** | **26,176 / 41,408** |

The last row is about **187–298× cheaper** than verifying each certificate with
a cached delegation and prepared subnet key. Its remaining work grows with the
proof depth rather than the number of entries in A's tree.

Additional component measurements:

| Component | Instructions | Allocated B |
| --- | ---: | ---: |
| Prepare subnet key once | 43,313,268 | 19,736 |
| Subnet signature plus certificate-tree hashing, raw key | 211,108,832 | 16,504 |
| Subnet signature plus certificate-tree hashing, prepared key | 167,863,212 | 16,504 |
| Parse/hash both certificate trees and 1,000-entry application witness; no signatures | 1,873,056 | 93,000 |
| Parse/hash both certificate trees and 100,000-entry application witness; no signatures | 2,212,408 | 108,232 |

The signature component rows include state-tree hashing; they are not isolated
BLS calls. The parse/hash rows are diagnostics and **do not authenticate data**.
The prepared key contains 19,680 bytes of table payload, excluding object and
cache-record overhead. It can be shared across sources on the same subnet/key.

## Cache and application design

Two conceptual operations would expose the useful separation:

```text
registerSnapshot(A, certificate) → authenticated snapshot identifier
consume(snapshot identifier, record, witness) → verify inclusion and apply action
```

Any client can submit a valid certificate for registration. Other clients then
use that snapshot without repeating BLS verification. A can certify an outbox
containing many records under one root to amortize registration. General cache
lookup/insertion and the business action were not measured here.

Keep three kinds of cached data distinct:

- Prepared BLS tables accelerate a known public key. They do not establish that
  the key is authorized. These plugin handles are transient and can be rebuilt
  after an upgrade from authenticated key bytes.
- Verified delegations bind the trusted root, subnet identity/key and permitted
  canister ranges. Reuse them only under the corresponding validity policy;
  invalidate or reauthorize when that binding changes.
- Verified snapshots bind A, its certified root, signed time and delegation
  validity. They are shared across clients and retain their original acceptance
  deadline. An unverified certificate or a cache hit must not refresh it.

The benchmark requires a certificate no older than five minutes and a
delegation no older than seven days, with no future clock skew. These are
benchmark policies, not universal protocol constants. IC guidance distinguishes
short-lived certificate freshness from delegations that refresh infrequently.
[HTTPS certificate validation guidance](https://docs.internetcomputer.org/references/ic-interface-spec/https-interface/).

Certification proves what A committed at a certified time. It does not prove
that the data is the latest state, that the relayer owns it, or that B has not
already consumed it. For commands, certify a protocol/version, destination B,
unique event ID or sequence, payload and expiry. B must check these and record
consumption atomically. Historical immutable events can have a different
freshness policy from balances or other mutable state. Choosing that policy is
part of the application protocol.

## Evidence and measurement boundaries

[results.json](results.json) retains all **45 observations**, **12 passing
negative controls**, and compiler, plugin, source and Wasm hashes.
[fixtures.json](fixtures.json) contains the authentic certificates and proofs.

A committed actual roots for exactly 1,000 and 100,000 leaves, with maximum
depths 10 and 17. Each selected value is 32 bytes with an 8-byte label. The
certificate is 910 bytes, including the NNS delegation; application witnesses
are 430 and 696 bytes. `@icp-sdk/core` 6.1.0 independently verified the chains and
canister ranges, and its tree reconstruction agreed with the fixture generator.
A separate protocol review checked the benchmark verifier and cache policy.

Certificates were captured on a dedicated NNS-plus-application PocketIC instance
and replayed to fresh verifier canisters in another instance with the same
deterministic trusted root, checked through `Prim.rootKey()`. This measures
cryptographic verification of genuine certificates, not capture or delivery
latency. A's identity is fixed; B's destination identity is not part of this
benchmark's record format.

Input setup, cache initialization and four GC increments precede timing.
Ingress Candid decoding, reply encoding, general multi-source cache lookup,
replay tracking and application state changes are excluded. Cold verification
includes one application proof; it is not a measurement of a complete
persistent snapshot-registration API.

Allocation is cumulative managed-heap allocation, including temporary garbage,
not retained or peak heap. Every measured call reported zero synchronous
reclamation. Native BLS stack scratch is excluded. The proof-only path still
allocates 26–41 KB in the Motoko decoder/tree walker; a specialized streaming
verifier could target that cost, but its improvement has not been measured.

Negative controls reject altered payloads, labels, witnesses, truncated input,
both altered signatures, a valid certificate for a different source canister,
altered signed time, an out-of-range canister, substituted delegation identity,
an expired cached snapshot and a future certificate. Another 13 parser
rejection checks passed; their local evidence is in the ignored
`_build/ic-certified-relay/parser-negative/` directory. An initial runner attempt
hit PocketIC's prohibition on moving time backwards; the final complete run
uses a separate instance for the future-time control.

## Prototype limits and next step

`Verify.mo` is a bounded definite-length CBOR decoder supporting these captured
classic certificates, positive inclusion proofs and the classic delegation
range path. It limits input to 64 KiB, depth to 64 and nodes/ranges to 4,096.
Production support must also cover the current sharded canister-range layout,
the chosen supported certificate encodings, and full application policy. This
does not implement the standardized canister-signature profile.
[Current interface specification](https://docs.internetcomputer.org/references/ic-interface-spec/).

The current generic `mo:fast/CBOR` decoder is not a drop-in certificate decoder:
certificate tag 55799 and the heterogeneous numeric-tag tree arrays need
specialized handling. No plugin or compiler/SDK changes were needed for this
investigation. The practical next step is a reviewed certificate/proof verifier
with the snapshot API above, keeping trust, expiry and replay policy in B's
typed Motoko state. Native decoding/tree hashing is a subsequent optimization.

## Reproduce

Run from the plugins repository root with the matching installed `moc`, built
`dist/sha256` and `dist/bls12-381`, PocketIC 10.0.0 and the pinned core 2.5.0
dependency. The local harness currently resolves `@icp-sdk/core` 6.1.0 from
`/srv/shared/code/candidx/ts/package.json` and uses tool paths under
`/home/devbox/.local/bin`; adjust those paths on another machine.

```sh
mkdir -p _build/ic-certified-relay
moc --plugin dist/sha256 --plugin dist/bls12-381 \
  --package fast packages/fast/src \
  --package core benchmarks/crypto/dependencies/.mops/core@2.5.0/src \
  benchmarks/crypto/ic-certified-relay/main.mo \
  -o _build/ic-certified-relay/main.wasm
node benchmarks/crypto/ic-certified-relay/run.mjs _build/ic-certified-relay/new-results.json
```

To capture replacement fixtures first, compile `source.mo` to
`_build/ic-certified-relay/source.wasm` and run
`node benchmarks/crypto/ic-certified-relay/capture.mjs`. This overwrites
`Fixture.mo` and `fixtures.json`; rebuild the verifier before measuring them.
Use a new output path to preserve earlier results.
