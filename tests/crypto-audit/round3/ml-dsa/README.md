# Independent ML-DSA-44 audit

**Approved** against production commit `3aea298d5ec7f027c2f76c55024ad47566c755f1`.
No blocking finding. [Source/artifact pins](source-pin.json) and
[execution evidence](execution.json) identify the exact candidate.

Review scope: the `ml-dsa` compiler plugin, pinned `fips204 = 0.4.6` runtime,
independent OCaml reference, and `mo:fast/MLDSA` public API. This is an engineering
review and interoperability test record, not cryptographic certification.

## Evidence

- [ACVP provenance](acvp-provenance.json): independently downloaded the pinned
  NIST source files, checked their hashes, and compared every selected case ID,
  group ID and field. All **25 key-generation, 30 seed-format signing and 15
  verification** cases match. [Checker](check-acvp.py) does not use the owner's
  extraction script. Selection is final FIPS 204 **external, pure ML-DSA**;
  internal-interface and HashML-DSA vectors require different domain framing.
- [Independent public-API cases](Cases.mo): selected official exact answers,
  malformed keys/signatures, hint count/order/duplicate/padding failures, strict
  `z` norm boundary, modified keys/messages/signatures, context lengths 255/256,
  zero/all-ones seed acceptance, randomness lengths and deterministic equivalence,
  combined-invalid-input error precedence, higher-order invocation/evaluation
  order and retained outputs after unrelated calls.
- [Forced-GC actor](Retained.mo): dynamically copied inputs and returned native
  Blobs are rooted in persistent state, transient state and an async frame over
  thirteen real message boundaries. The test compares exact official answers, uses
  retained values again, and requires the RTS reclaimed-byte counter to advance.
- [Stack audit](stack/README.md): conservative native Wasm frame bounds and
  reproducible checks against the measured runtime hash.

The selected Motoko vector set has three key-generation cases, six signing
cases (deterministic and explicit randomness; empty and 255-byte contexts;
messages from one byte through 8 KiB), and all 15 verification cases. Native
runtime tests cover all 70 curated ACVP cases. Expected ACVP bytes originate
from NIST, not the plugin or its reference implementation.

## Execution outcome

Both the public-module fixture and independently authored audit fixture passed
`test-runner` through Motoko, IR and lowered interpretation, Wasm validation and
Wasm execution. All expected silent outputs and interpreter-diff files were
inspected. The final retained-GC Ash test passed; its `tick` helper is correctly
skipped because it does not return test metrics. The plugin owner executed
these fixtures in the assigned integration slot; the independent auditor
inspected the logs, hashes, output files and assertions.

The first GC fixture passed all retained-value and cryptographic checks but
allocated too little garbage to establish its reclaimed-byte assertion. The
retained initial failure documents that limit. The corrected fixture applies
bounded 72 MiB pressure over nine rounds and four settling boundaries, then
requires **more than 4 MiB actually reclaimed**. No production change was needed.
Ash's displayed **529 instructions / 0 B** measures only the final empty
`Test.test` return; it is **not** the cost of the async cryptographic/GC work.
Actual public-API costs belong in the separate benchmark report.

## Reviewed invariants

- The public secret-key representation is exactly a 32-byte seed. There is no
  unchecked expanded-private-key import. Every 32-byte seed is valid.
- Key generation includes final FIPS 204 parameter domain separation. Pure
  signing/verification frames the message with `0 || len(context) || context`;
  a caller-supplied digest is simply a message, not HashML-DSA.
- Public keys are exactly 1,312 bytes; all bit patterns of that size are
  syntactically valid `rho || packed-t1`. Signatures are exactly 2,420 bytes.
  Verification rejects noncanonical hint encodings and out-of-range `z`, and
  checks the challenge commitment. Full-width polynomial packing has no unused
  padding bits to normalize.
- Native buffer lengths remain Wasm64 `usize`/`i64`; fixed output buffers are
  initialized and never overlap inputs by compiler construction. No input
  pointer survives the synchronous native call and no native GC safepoint,
  callback, allocator or persistent plugin state is present. This plugin's
  artifact targets the current Wasm64 SDK; this audit does not establish a
  separate Wasm32 plugin implementation.
- Compiler locals retain managed arguments across the output allocation.
  Signature verification allocates only its result variant; key generation and
  signing additionally allocate their fixed output Blob before validation.
  Therefore an invalid signing request can discard a bounded 2,420-byte output
  allocation. This is ordinary collectable Motoko garbage, not retained state.
- Runtime and interpreter use the same error order. Signing expands the seed
  on every call; public-API performance must include this expansion.

## Limits retained from upstream

The caller's secret-seed Blob is borrowed and unchanged. Expanded private keys
and polynomial types have upstream zeroization on drop. This does **not** prove
all secret material is erased: seed copies, SHAKE state, raw mask buffers and
other byte-array temporaries are not comprehensively guaranteed to be wiped.
The interpreter reference is not a constant-time secret-key implementation.

Signing uses rejection sampling and has variable instruction cost. Upstream's
16-bit candidate nonce repeats after 16,384 rejected ML-DSA-44 attempts in its
release build; the reference mirrors that behavior. No practical triggering
input was demonstrated. This review does not claim a fixed signing instruction
bound; ordinary canister instruction limits remain relevant. No speculative
cryptographic fork was introduced to address this theoretical limit.

Primary specification: [FIPS 204](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf),
particularly Algorithms 6–8 and 21, §3.6.3 and Appendix C.
