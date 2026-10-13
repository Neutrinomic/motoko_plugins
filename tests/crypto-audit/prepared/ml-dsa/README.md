# Independent prepared ML-DSA audit

Scope: `MLDSA.preparePublicKey`, `prepareSecretKey`, `verifyPrepared`,
`signPrepared` and `signRandomizedPrepared`; their nominal compiler types;
managed immutable caches; and the narrow vendored `fips204 = 0.4.6` hooks.
The previous [direct ML-DSA audit](../../round3/ml-dsa/README.md) is unchanged.

## Final seeded-signing checkpoint

**Approved at production commit `8d67a9f`**, runtime
`07ae75432d55ddcbb4741f0d0aa40bb0d086f365d1c68c0648bde3dd20850c3f`.
The final delta reuses key generation's matrix during ordinary seeded signing.
It adds no managed cache or serialization. Direct and prepared signing now
share the same facade with unchanged FIPS parameters, framing, randomness,
error order and exact signature bytes.

The [independent source review](direct-sign-review.json) and
[executed delta validation](direct-sign-validation.json) pin this change.
Native debug/release each passed all 10 groups; the public fixture passed
Motoko, IR, lowered IR and Wasm again. [Disassembly evidence](direct-sign-codegen.json)
shows direct signing passes the same matrix address from keygen to signing,
and the signing core has no reachable matrix expansion. Direct `publicKey`
still passes a null matrix output.

[Final stack analysis](direct-sign-stack.json) covers all 38 functions and
171 direct call sites. All bounds remain within the 4 MiB reservation:

| Operation | Final additional native shadow stack |
|---|---:|
| Prepare public key | 53,888 B |
| Prepare secret key | 137,952 B |
| Direct public key | 134,144 B |
| Direct sign / randomized sign | 137,984 B |
| Prepared sign / randomized sign | 121,312 B |
| Direct verify | 103,232 B |
| Prepared verify | 138,624 B |

Direct signing intentionally retains the useful matrix until signing finishes;
its bound increases from 129,776 B to 137,984 B. Instruction and heap benchmark
comparisons remain a separate measurement scope. The existing 10 negative-type
and actual-GC tests below were not repeated for this narrow change: the SDK,
compiler plugin, RTS, public module, cache format and managed pointer/allocation
boundaries are unchanged. Their original runtime pins and logs remain intact.

## Initial prepared checkpoint

**Approved for the frozen implementation after one performance regression was
fixed.** No unresolved blocking correctness, type-boundary, memory-lifetime or
native-stack finding remains. Production source is `4657a21`; runtime is
`104aedb9853a4f039c825e14136db44af879d17edb692812751ab75393f44696`.
The compiler plugin, SDK executable, RTS, private Ash runner and input sources
are pinned in [source/artifact provenance](source-artifact-provenance.json),
[runner provenance](runner-provenance.json) and [executed validation](validation.json).

| Executed gate | Result |
|---|---|
| Native debug and release | 10 test groups each; direct 70-case ACVP corpus, prepared exact signatures/verdicts, immutable reuse, error boundaries and unaligned output canaries |
| Independent public API fixture | Passed Motoko, IR, lowered IR and compiled Wasm; all expected silent outputs present |
| Nominal type boundary | All 10 compile-fail fixtures rejected for the intended diagnostics, then passed checked expectations |
| PocketIC/Ash retention | Passed; two prepared keypairs survive 13 message boundaries, exact signatures and wrong-key checks, with more than 4 MiB actually reclaimed |
| Native shadow stack | All 41 functions / 221 direct call sites covered; maximum 138,784 B |

The native tests were independently rerun after the corrected build. The
negative diagnostics were generated using `test-runner -a`, inspected, then
checked without acceptance. The private Ash snapshot selects the prepared SDK
without changing global tools or `HOME`. Benchmark speed and retained-heap
comparisons are separate from this correctness/GC audit.

## Reviewed design

| Cache | Explicit byte fields, in order | Payload size |
|---|---|---:|
| Public | rho (32 B), tr (64 B), t1 NTT/Montgomery 4×256×i32, A 4×4×256×i32 | 20,576 B |
| Secret | rho (32 B), K (32 B), tr (64 B), s1/s2/t0 NTT/Montgomery each 4×256×i32, A 4×4×256×i32 | 28,800 B |

Coefficients are serialized as signed little-endian i32, preserving the exact
upstream domains and ordering. The A matrix and key-polynomial fields are not
interchangeable Montgomery representations. Readers reconstruct initialized
stack objects. There are no native struct dumps, padding bytes or pointers in
the managed caches. A pointer cast to a fixed byte array requires alignment 1;
there is no cast to an upstream Rust object.

Factories validate the original seed/key length, initialize their entire fixed
payload and publish a protected handle only on success. The compiler registers
separate public/secret nominal identities and unwraps arguments using their
actual specialization types. Native consumers take only a fixed-size byte
pointer; they rely on that construction boundary instead of repeating key
validation. Pointer derivation follows any output allocation and resolves
managed Blob forwarding on each synchronous call. No native pointer survives
the call, and caches are never modified.

The vendor hooks select the already computed matrix but retain the original
arithmetic, domain framing, signature decoding, norm/hint checks and rejection
loop. All message-, context- and randomness-dependent calculations remain per
operation. Signing includes the exact supplied 32-byte `rnd`; deterministic
signing uses zeros. The reference privately retains canonical seed/public bytes
and recomputes with the independent implementation, rather than duplicating the
optimization or interpreting native cache bytes.

Prepared secrets intentionally retain expanded secret material while their
managed handles remain reachable. Dropping the last reference permits ordinary
GC reclamation; it does not guarantee secure erasure. Temporary upstream key
and polynomial objects still zeroize on drop, with the same incomplete raw
scratch-erasure limitation documented in the direct audit. Prepared types are
nonshared/nonstable, so these cache bytes are not a key interchange or upgrade
format. The source key must be retained separately when reconstruction is needed.

## Independent fixtures

- [Cases.mo](Cases.mo) verifies exact NIST ACVP signatures and verification
  verdicts, direct/prepared equality, deterministic/randomized parity, changed
  messages, malformed challenges/z/hints, context lengths 255/256 and randomness
  boundaries, error precedence, zero/all-ones seeds/public encodings, repeated
  interleaved keys, ordinary typed callbacks and argument evaluation order.
- [Compile-fail fixtures](fail/) reject forged Blob handles, public/secret
  interchange, exposing handles as Blob, shared/stable use, and Candid
  encoding/decoding and `debug_show` exposure of prepared types. Expected diagnostics must establish the
  intended type boundary, not an unrelated parser or import error.
- [Retained.mo](Retained.mo) retains two distinct dynamically prepared keypairs
  through transient state, an async frame and a closure. It checks exact
  signatures and correct/wrong-key verification after 13 message boundaries,
  applies a bounded 72 MiB main pressure loop plus setup, and requires more
  than 4 MiB actually reclaimed.
  Its printed Ash metrics cover only the empty final `Test.test` block and are
  not cryptographic or GC benchmark costs.

The SDK's nominal-type implementation is a separate reviewed dependency; these
fixtures verify the plugin's actual public surface. This is an engineering
review, not cryptographic certification.

## Resolved source finding and stack evidence

The first prepared build unnecessarily returned a 16 KiB matrix on direct
`publicKey` and `sign` calls. Rust discarded it, but the Wasm still copied it.
The [initial finding](initial-returned-matrix-finding.json) and
[initial stack report](stack.initial-returned-matrix.json) are retained.
Commit `4657a21` restores the original key-pair return and uses an optional
matrix output only for preparation. [Disassembly evidence](matrix-output-resolution.json)
confirms both direct callers pass null and skip all sixteen 1,024-byte copies.

The [final stack analysis](stack.json) covers all 41 functions and 221 direct
call sites in runtime `104aedb9853a4f039c825e14136db44af879d17edb692812751ab75393f44696`.
It rejects unfamiliar frame patterns and unresolved, indirect, imported or
recursive calls. These are conservative native shadow-stack bounds, not
heap allocations or total host stack usage.

| Operation | Additional native shadow stack |
|---|---:|
| Prepare public key | 53,888 B |
| Prepare secret key | 138,112 B |
| Direct public key | 134,304 B |
| Direct sign / randomized sign | 129,776 B |
| Prepared sign / randomized sign | 105,984 B |
| Direct verify | 103,392 B |
| Prepared verify | 138,784 B |

All bounds fit within the SDK's 4 MiB native scratch reservation. This does
not impose a fixed instruction bound on signing's inherited rejection loop.
The [static review](static-review.json) pins the source and upstream comparison;
the [executed validation](validation.json) closes its originally pending public
API, compile-fail and real-GC checks. This audit executes the wasm64 plugin;
there is no claim of a separately executed wasm32 build.
