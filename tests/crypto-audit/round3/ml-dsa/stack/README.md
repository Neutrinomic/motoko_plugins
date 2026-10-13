# ML-DSA runtime shadow-stack audit

This is read-only analysis of the built `dist/ml-dsa/runtime.wasm`, using WABT
`wasm2wat` 1.0.36. [report.json](report.json) pins the 126,649-byte input:

```text
565cd01223c5d2ce3018e2279e9dd4e371e70f74bde0b78ef20784b44cbbd35e
```

From the plugins repository root, reproduce without changing any artifact:

```sh
python3 tests/crypto-audit/round3/ml-dsa/stack/analyze.py \
  dist/ml-dsa/runtime.wasm \
  --expect-sha256 565cd01223c5d2ce3018e2279e9dd4e371e70f74bde0b78ef20784b44cbbd35e
```

| Export | Own frame, bytes | Conservative additional shadow stack, bytes |
|---|---:|---:|
| `mldsa_public_key` | 45,504 | 134,016 |
| `mldsa_sign` | 35,632 | 129,776 |
| `mldsa_sign_randomized` | 35,632 | 129,776 |
| `mldsa_verify` | 67,104 | 93,696 |

The script checks all 30 binary-defined functions against both the function and
code-section counts; 18 functions have frames. All 138 direct-call sites resolve
inside this module, and the complete direct-call graph is acyclic. There are no
function imports, indirect calls, reference calls or tail calls in this artifact.
The JSON retains every function's frame and callees, plus each export's maximum
call path. Some maximum paths include zero-frame panic helpers; this deliberately
overestimates feasible successful execution.

For each function, the analyzer permits only a fixed, initial
`global.get __stack_pointer; i64.const N; i64.sub; local.tee L; global.set`
allocation. Every subsequent stack-pointer access must restore that same frame
base plus `N`, and the base local must remain unchanged. Unrecognized patterns,
unparsed calls or call cycles fail the analysis. The conservative bound is each
frame plus its largest descendant bound; calls in loops do not accumulate live
frames. This is a structural audit of compiler-generated code, not a full
control-flow or memory-safety proof.

These are **additional linear-memory shadow-stack bytes per invocation**, not
managed-heap allocation, retained memory, engine-native stack or a whole-canister
stack bound. The reviewed Motoko compiler reserves 4 MiB at
`src/codegen/compile.ml:1436`; callers already using part of that space must still
fit. The plugin has no callbacks/reentrancy, variable-length stack arrays or
input-dependent recursive calls. Rebuilds require rerunning this audit; these
numbers do not establish a bound for a different runtime hash.

## Related source review

- Wrapper `plugins/ml-dsa/runtime/src/lib.rs:52` borrows `usize`-length byte
  slices; exports and compiler imports use 64-bit pointers and lengths. Output
  blobs have fixed sizes, are initialized before use, and must be disjoint from
  inputs. No GC safepoint occurs inside the runtime call.
- [fips204 0.4.6 `types.rs`](https://docs.rs/crate/fips204/0.4.6/source/src/types.rs)
  lines 19, 45 and 52 clear expanded keys and polynomial arrays on drop. This
  does **not** guarantee erasure of all intermediate secret bytes: raw
  `rho_prime` arrays and mask buffers in `ml_dsa.rs:71,200` and `hashing.rs:283`
  have no explicit clearing, and SHA3's optional `zeroize` feature is disabled
  in the reviewed dependency graph. Original seed blobs remain owned by Motoko.
- [fips204 0.4.6 `ml_dsa.rs`](https://docs.rs/crate/fips204/0.4.6/source/src/ml_dsa.rs)
  lines 204, 281 and 316 use an unchecked `u16` rejection counter. After 16,384
  rejected ML-DSA-44 attempts, release arithmetic repeats mask inputs; debug
  arithmetic panics. This is a theoretical upstream robustness limitation, not
  a demonstrated practical failure, and it does not increase stack usage.

## July 2026 potential errata

[NIST's publication page](https://csrc.nist.gov/pubs/fips/204/final) links the
[July 31, 2026 spreadsheet](https://csrc.nist.gov/files/pubs/fips/204/final/docs/fips-204-potential-updates.xlsx).
[errata-review.json](errata-review.json) records its hash and the applicable
review. These are proposed corrections, not a revised standard or new algorithm.

The proposed minimum signing-loop limit is **821**, replacing the original
814; expected ML-DSA-44 repetitions become 4.36. The implementation's theoretical
counter limit is well above both. Reviewed code already follows the corrected
message/challenge ordering, NTT definition, signed Montgomery reduction and hint
range. Upstream verification returns false for excessive context length; our
public API deliberately reports a typed `#invalidContext` before invoking it.
