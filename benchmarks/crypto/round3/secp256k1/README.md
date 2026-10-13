# Secp256k1 optimization round three

The first candidate selects k256 0.13.4's unchanged 10x26 coordinate field
backend for Wasm64 instead of its 5x52 backend. Wasm has no native 128-bit
multiply. Scalar arithmetic, constant-time multiplication and signing remain
unchanged. This is a checkpoint pending the broader independent audit.

Seven identical public API fixtures were compiled with the frozen baseline
and candidate artifacts using the existing `benchmarks/crypto/build.py` and
`run.mjs` protocol, three fresh PocketIC canisters per case. All 42 oracle
checks passed; instruction counts were identical across each three trials.
Both variants include all normal input decoding/validation. Allocation below
is cumulative Motoko allocation during the measured call, not retained heap.

| Operation | Baseline instructions | Field26 instructions | Allocated bytes, both |
|---|---:|---:|---:|
| derivePublicKey | 6,351,616 | 2,525,775 | 128 |
| verifyPrehash | 10,093,629 | 4,358,915 | 56 |
| signPrehash | 7,452,214 | 3,626,759 | 120 |
| schnorrSign | 12,762,954 | 5,114,993 | 120 |
| schnorrVerify | 9,920,617 | 4,187,087 | 56 |

`baseline/` and `field26/` retain full build manifests, raw trial results and
compressed exact source snapshots. Total canister Wasm sizes appear in each
build manifest. The source snapshots also contain the compiler/plugin hashes
and fixture source. Executable artifacts remain under local ignored
`benchmarks/crypto/results/round3-secp-{baseline-v2,field26}/`.
