# BLS12-381 round-four results

The selected implementation reduces verification instructions by **1.80–6.16%** across the measured direct/prepared workloads, with larger key-preparation gains. Streaming two-term pairings removes temporary coefficient tables: single IC and Ethereum verification allocate **64 bytes**, and preparing eight Ethereum PoP keys allocates **1,688 bytes instead of 315,416**. The cost is **47,054 additional runtime Wasm bytes** and **45,621 additional bytes per measured canister Wasm**.

This compares the already optimized prepared-crypto baseline `0e1e96a` with final production `5e72dab`, using the same compiler, RTS, actors, fixtures and dependencies. It does not compare prepared calls against direct calls or count prior-round gains again.

## Measured costs

Three fresh PocketIC canisters per row and revision; every result matches its independent oracle. All three instruction/allocation samples in each row are identical. A row is one complete public operation; an aggregate row verifies the specified aggregate once. `prepare` is a separate timed preparation interval: the distinct-eight row constructs eight PoP-validated keys, including proof checks. Prepared verification excludes setup, which is measured separately.

| Operation / mode | Instructions, baseline → selected | Saving | Allocated bytes, baseline → selected |
|---|---:|---:|---:|
| IC verification — direct | 222,072,725 → 210,673,356 | 5.13% | 19,672 → 64 |
| IC verification — prepare | 49,992,831 → 43,312,942 | 13.36% | 19,736 → 19,736 |
| IC verification — prepared | 172,121,515 → 167,427,790 | 2.73% | 64 → 64 |
| Ethereum verification — direct | 286,405,944 → 274,974,367 | 3.99% | 39,280 → 64 |
| Ethereum verification — prepare | 12,239,690 → 11,144,375 | 8.95% | 200 → 200 |
| Ethereum verification — prepared | 274,167,416 → 263,831,154 | 3.77% | 39,280 → 64 |
| Ethereum aggregate, 8 distinct keys — direct | 3,285,303,573 → 3,175,970,967 | 3.33% | 494,840 → 181,112 |
| Ethereum aggregate, 8 distinct keys — prepare | 2,291,247,278 → 2,199,794,662 | 3.99% | 315,416 → 1,688 |
| Ethereum aggregate, 8 distinct keys — prepared | 994,060,838 → 976,180,848 | 1.80% | 181,552 → 181,552 |
| IC aggregate, 2 distinct keys — direct | 310,532,835 → 291,392,273 | 6.16% | 40,552 → 40,552 |
| IC aggregate, 2 distinct keys — prepared | 210,626,139 → 204,848,489 | 2.74% | 544 → 544 |
| Ethereum aggregate, 8 references to one key — direct | 565,078,557 → 542,281,614 | 4.03% | 82,680 → 43,464 |
| Ethereum aggregate, 8 references to one key — prepared | 278,645,699 → 267,280,333 | 4.08% | 43,904 → 43,904 |
| Fast Ethereum aggregate, 2 distinct keys — direct | 850,994,532 → 816,711,191 | 4.03% | 118,064 → 416 |
| Fast Ethereum aggregate, 2 distinct keys — prepared | 278,183,952 → 266,763,765 | 4.11% | 39,840 → 624 |

Prepared payload sizes are unchanged: 19,680 bytes per IC key and 144 bytes per plain or PoP-validated Ethereum key, excluding object/array overhead. The distinct-eight prepared group retains eight separately constructed values (1,152 payload bytes). The repeated-eight group retains one returned prepared value referenced eight times (144 payload bytes); factories do not cache or intern equal values. IC aggregate two retains 39,360 payload bytes, and fast Ethereum aggregate two retains 288. Direct rows retain no prepared payload.

Exact rows, oracle metadata, ranges, allocation, payload and memory snapshots are in [main comparison](c3-comparison.md) / [JSON](c3-comparison.json) and [additional aggregate comparison](final-extra-comparison.md) / [JSON](final-extra-comparison.json).

## What changed

1. **Fixed exponentiation chains:** reuse the existing upstream addition chain for Fp square root/inversion and both Fp2 square-root powers. This independently saves 4.48% on direct IC verification, 13.36% on IC preparation and 8.95% on plain Ethereum preparation. Zero handling and exact root/sign selection remain unchanged. [C1 measurements](c1-comparison.md).
2. **Final-exponentiation conjugation:** replace six Frobenius maps with the exact quadratic-extension conjugation. This saves 1,435,108 instructions per final exponentiation and reduces runtime Wasm by 34,497 bytes relative to C1. [C2 incremental measurements](c2-incremental.md).
3. **Streaming two-term Miller coefficients:** reuse the existing upstream Miller driver, doubling/addition and line evaluation with two bounded states. The immutable generator table is still reused; general aggregate and prepared IC table reuse stay intact. The main benefit is allocation, with small additional instruction savings. [C3 incremental measurements](c3-incremental.md).

C3 alone increases prepared IC verification by **4,558 instructions (0.00272%)**, while leaving its allocation at 64 bytes. The complete selected implementation still reduces that row by 4,693,725 instructions (2.73%). This small instruction regression is retained alongside the measured allocation savings elsewhere. No further arithmetic/backend variants were added.

The runtime sizes were 608,575 bytes at baseline, 685,243 after C1, 650,746 after C2, and 655,629 after C3. Unchanged payload or managed allocation does not imply unchanged static code/data. Tests bound the streaming driver's Rust state to 1,024 bytes; this is **not** a bound on the complete compiled Wasm stack or peak memory.

All measured snapshots retained 128 MiB Wasm capacity and reported zero reclaimed bytes, including the post-trigger snapshots. The measured allocation reduction is real; these samples do not establish peak-memory, live-retention or actual-collection savings. Occupied-heap snapshots and cumulative counters remain in the JSON evidence.

## Validation and reproducibility

Canonical decoding, subgroup and identity rejection, PoP checks, profile/domain separation, distinct-message constraints, argument evaluation and error precedence are preserved. Public APIs, ordinary aggregate callbacks, prepared payload layout, SDK and GC ownership are unchanged. No hidden cache, unchecked mode or retained native pointer was added. [Research and primary sources](RESEARCH.md).

Final owner gates passed: 111 vendor group tests, 129 vendor experimental tests and 28 runtime tests, replayed under the exact Nix/nightly toolchain used to build the runtime. Independent validation passed 18 commands: symbolic chain proof, guarded native ABI tests, 128 factory / 32 single / 68 prepared-aggregate cases, 270 retained direct aggregate cases, boundaries and ordinary callbacks in the interpreter and validated memory64 Wasm. Exact-root, general-field conjugation and raw Miller-result differential tests preserve isolated test-only baseline oracles. [Independent audit](../../../../tests/crypto-audit/round4/bls12-381/report.json).

The earlier prepared-type rejection and actual-GC evidence is reused because layout, SDK and ownership are unchanged; those tests were not rerun in this round. The independent audit records this scope explicitly.

- Compiler: `9f6ebeedc`, ELF SHA-256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`, original release/debug RTS.
- Final runtime SHA-256: `ebc5fa2fd9fc6ed3698bd523f5101d4883ef51c0e7bf4783f4b2da64d691972c`.
- Runtime toolchain: `rustc 1.99.0-nightly (da86f4d07 2026-07-24)`; native host replay is also retained.
- Six immutable stages contain **144 successful observations**: 90 paired baseline/final observations across 15 cases, plus 54 intermediate C1/C2 observations. No modeled costs or per-call division are used.
- [Final stage/evidence manifest](validation/final.json), [final build/test pins](validation/c3.json), [C1](validation/c1.json) and [C2](validation/c2.json).

Central stages are under `benchmarks/crypto/round4/results/`: `prepared-round4-bls12-381-c1-{baseline,candidate}`, `prepared-round4-bls12-381-c2-candidate`, `prepared-round4-bls12-381-c3-candidate`, and `prepared-round4-bls12-381-final-extra-{baseline,candidate}`. Their build metadata freezes source, dependencies, compiler/RTS/plugin artifacts, actor Wasms and the exact runner. The independent performance audit verifies those frozen inputs and every reported statistic before final promotion.
