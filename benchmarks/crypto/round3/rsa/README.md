# RSA-PSS measurements

The retained implementation verifies a SHA-256 digest in **9,822,506 IC
instructions**, versus 23,623,625 before specializing the fixed public exponent:
**58.42% fewer instructions (2.40× faster)**. Signing costs 550,857,988 instructions;
its 2.44% improvement comes from the mandatory public-operation fault check.
The private exponentiation algorithm is unchanged.

| Operation | Generic public exponent | Fixed e=65537 | Instructions saved | Allocated bytes |
| --- | ---: | ---: | ---: | ---: |
| Derive public key | 1,946,943 | 1,946,943 | 0.00% | 440 |
| Validate private CRT components | 1,946,784 | 1,946,784 | 0.00% | 32 |
| Validate public key | 475 | 475 | 0.00% | 32 |
| Sign SHA-256 digest | 564,659,446 | 550,857,988 | 2.44% | 440 |
| Verify SHA-256 digest | 23,623,625 | 9,822,506 | 58.42% | 32 |
| Sign 47-byte message | 564,668,863 | 550,867,405 | 2.44% | 440 |
| Verify 47-byte message | 23,633,043 | 9,831,924 | 58.40% | 32 |

These are measurements of the plugin before and after its own optimization,
not comparisons with a Motoko RSA library. The profile is RSA-3072/e=65537,
PSS with SHA-256, MGF1-SHA256 and exactly 32 bytes of caller-supplied salt.
Key generation happens off-chain; import and derive operations are documented
in [the plugin README](../../../../plugins/rsa/README.md).

## Method and evidence

Both implementations use the same seven actor sources, independent OpenSSL
fixture, compiler/RTS and C toolchain. Each case has three fresh-canister trials;
all 42 observations passed, and all three instruction counts per case were
identical. Configuration and forced GC happen before the measured synchronous
operation; result serialization and independent output checks happen afterward.
There is no empty-loop subtraction. See the complete methodology in the raw
[baseline](baseline-results.json) and [final](final-results.json) results.

Allocation is cumulative managed Motoko allocation during the operation,
including its result. It is unchanged in every case. No measured synchronous
reclamation occurred. These numbers do not include the fixed native stack
workspace, Wasm linear-memory pages, input blobs allocated earlier, or
end-of-message GC. They are not whole-canister peak-memory measurements.
The [summary](summary.json) also records total actor Wasm sizes.

The fixed public operation uses the unchanged BearSSL i31 Montgomery primitives
for sixteen squarings and one multiply. It keeps the original `signature < n`
check and distinct scratch buffers. It accelerates verification and signing's
public fault check; no secret arithmetic was redesigned.

- [Final independent audit](../../../../tests/crypto-audit/round3/rsa/README.md):
  270 public cases on native ASan/UBSan, OCaml and compiled Wasm; 1,223 raw
  exponentiation cases against Python and generic BearSSL; seven ordinary
  imports and 16 restricted RSA-PSS imports rejected.
- [Public module/GC coverage](../../../../packages/fast/tests/ash/coverage/RSA.md):
  all nine Ash methods passed, including dynamic inputs and results retained
  across confirmed collection; targeted package test-runner also passed.
- [C compiler provenance](c-toolchain.json): pinned clang 21.1.8 and llvm-ar,
  with no `RSA_CLANG` or `RSA_AR` override needed by the final build.
- Frozen build manifests:
  [baseline](../../results/r3-rsa-generic-baseline/build.json),
  [final](../../results/round3-rsa-fixed-public/build.json).
  Source archives remain under these local stage directories and are included
  in the repository's shared benchmark source archive during integration.

Reproduce after building the matching `rsa` plugin and installing the locked
benchmark dependencies:

```sh
python3 benchmarks/crypto/round3/rsa/generate.py
python3 benchmarks/crypto/build.py \
  --manifest benchmarks/crypto/round3/rsa/cases.json \
  --stage rsa-reproduction --plugin-roots /path/to/plugin-roots.json \
  --fast-root packages/fast/src
node benchmarks/crypto/run.mjs \
  --build benchmarks/crypto/results/rsa-reproduction/build.json \
  --out /path/to/new-results.json --trials 3
```

Use a new stage/output path and run PocketIC without other benchmark workloads.
The plugin-roots JSON maps `rsa` to the checkout containing its matching `dist/rsa`.
