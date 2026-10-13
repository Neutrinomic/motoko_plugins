# P-256 signing and key derivation

The retained change reuses P-256's existing constant-time fixed-base comb for
RFC6979 nonce multiplication. Both signing and public-key derivation now use
an affine comb table and RustCrypto's complete mixed addition. The public API,
RFC6979 bytes, high-S behavior, validation order and portable OCaml interpreter
remain unchanged. No compiler, RTS or SDK changes are involved.

| Operation | Baseline instructions | Candidate instructions | Reduction | Allocated bytes, both |
|---|---:|---:|---:|---:|
| RFC6979 signing | 13,458,880 | 7,225,034 | 46.32% | 120 |
| `derivePublicKey` | 5,207,095 | 4,968,688 | 4.58% | 96 |
| Compressed-key verification | 12,873,707 | 12,873,707 | 0% | 32 |

All 30 workloads passed in three fresh canisters each for the baseline and
candidate, for 180 trials. Every selected case is retained in the
[comparison](comparison.json), including four independently generated exact
signatures at digest boundaries. Instruction counts were identical across the
three trials. The remaining key-conversion, verification, DER and normalization
workloads have exactly unchanged instruction counts.

Allocation, reclaimed bytes, occupied-heap snapshots and Wasm capacity are
unchanged for every case. The whole-canister Wasm grows by 8,416 bytes; the
runtime object grows from 91,872 to 100,407 bytes. The code-size increase reduces signing
instruction cost by 46.32% and public-key derivation by 4.58%. Verification
performance is unchanged. Occupied-heap snapshots include ordinary
runtime state and garbage. They are neither peak heap nor a retained-live-data
measurement; see the [common protocol](../README.md).

The unchanged verification path already combines public scalars with width-5
nonadjacent forms. RustCrypto P-256's 32-bit field implementation repacks to the
same 64-bit arithmetic, so selecting it would not provide secp256k1's separate
32-bit-multiplication optimization. A new field backend was not introduced.

## Correctness and security

The eight native tests pass, covering the pinned 484-case Wycheproof corpus,
published RFC6979 signatures and digest reduction, 1,284 generator-comb cases,
147 verification linear combinations and 530 exact-byte signing comparisons
against upstream arithmetic. The additional signing comparisons cover boundary
secrets and digests, all 256 single-bit secrets and 256 deterministic inputs.

The [independent audit](audit/README.md) adds 43 signatures calculated with
Python HMAC/integer arithmetic and OpenSSL point multiplication, tests the
exported pointer ABI and output canaries, and inspects the emitted comb loop.
The comb scans all 15 entries for each of 64 iterations, including zero digits.
Signing uses constant-time scalar inversion. Variable-time verification remains
restricted to public inputs. Explicit temporary scalar and nonce copies are
zeroized; this is not a guarantee that all upstream or caller-owned copies are
erased.

## Reproduction and provenance

[`generate-cases.py`](generate-cases.py) copies the 25 delivered round-two
hotspot fixtures, adds the public derivation alias, and appends four existing
independent RFC6979 digest-boundary vectors. An untimed memory query is the only
change to copied workloads. Expected cryptographic bytes never come from the
candidate plugin.

```sh
python3 benchmarks/crypto/round3/p256/generate-cases.py
python3 benchmarks/crypto/round3/run-stage.py --stage p256-baseline-new \
  --manifest benchmarks/crypto/round3/p256/cases.json
python3 benchmarks/crypto/round3/run-stage.py --stage p256-comb-new \
  --manifest benchmarks/crypto/round3/p256/cases.json \
  --root /absolute/candidate/root --plugin p256
```

The immutable [baseline](../../results/round3-p256-baseline/results.json) and
[candidate](../../results/round3-p256-comb/results.json) stages retain exact
input, output, compiler, RTS, PocketIC, dependency, runtime and Wasm hashes.
Local stage archives also retain the corresponding frozen inputs and binaries.
