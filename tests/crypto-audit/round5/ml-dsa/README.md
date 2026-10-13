# ML-DSA round-five audit

No production defect was found. This is a test-only change against baseline
`cf55e909`, the frozen SDK compiler, and the existing distributed ML-DSA runtime.
[Validation](validation.json) records exact artifact/test hashes and results.

## Coverage added

- **Hint malleability:** reuse official deterministic case 4 and randomized
  case 373. Swap two existing indices in each row, or insert a duplicate and
  adjust all following endpoints; also change first/last unused padding.
  All 20 mutations preserve the valid signature's mathematical hint set.
  Direct and prepared native verification reject every mutation. The new
  public fixture repeats case 4's ten mutations and independently confirms
  the unchanged hint bits with a deliberately permissive decoder. This is
  stronger than replacing the original hint set: a commitment mismatch cannot
  conceal an omitted canonicality check.
- **FFI:** cases 4 and 373 pass exact official key/signature answers with input,
  output and prepared-payload offsets 1 through 8. Every exported operation is
  exercised; deterministic and randomized signing agree with the official
  answers, prepared payloads and input buffers stay unchanged, and output
  prefix/suffix canaries stay intact. Invalid factory/signing inputs initialize
  exactly the output region to zero, with context/randomness error precedence
  checked and valid retained handles usable afterward.
- **Binary framing and aliases:** context/message pairs with identical
  concatenated bytes, including NUL and high-bit bytes, remain distinct
  domains. Direct/prepared deterministic signatures agree; explicitly zero
  randomness gives the same result. Overlapping immutable seed/message/context/
  randomness inputs work. A 255-byte all-zero context works; 256 bytes produces
  the documented error before invalid randomness. These checks run at native
  and public Motoko APIs.
- **Public encoding extremes:** all-zero and all-one correctly sized public
  keys prepare successfully, round-trip through native serialization, and
  return false when used against another key's official signature. Packed
  `t1` fills its entire ten-bit range; the maximum scaled coefficient is `q-1`.

Tests live in the maintained native suite and `plugins/ml-dsa/tests/run/`, which
`scripts/test.sh` discovers automatically. Both public fixtures reuse
`Vectors.mo`; no official vector corpus was copied.

## Source review

Reviewed the public module, compiler registration/reference adapters, native
exports, prepared serialization, and underlying key generation/signature
encoding/framing. The registration evaluates and saves arguments before result
allocation, obtains payload pointers afterward, and makes a synchronous runtime
call without callbacks or GC. Prepared caches contain initialized byte values,
never retained native pointers; only nominal matching factory output reaches
the trusted cache consumer.

Both implementations frame pure messages with the zero domain byte and an
explicit context length. Only 32-byte secret seeds enter the public API, so
inconsistent expanded-secret-key imports are unavailable. Exact official seed
and public-key answers, deterministic/randomized signatures and existing
prepared parity tests were rerun. Hint count/order/padding checks and the strict
signature coefficient norm checks agree across native and reference code.
No new constant-time, secure-erasure, or rejection-loop bound claim is made.

## Executed validation

From `/srv/shared/code/motoko_experiments/prepared-crypto/sdk`, enter
`nix develop --command bash <wrapper>` with the SDK's `bin` first on `PATH`,
`CARGO_BUILD_JOBS=2`, `RUST_TEST_THREADS=2`, and the frozen Core 2.5.0 path as
`MOTOKO_CORE`. Here `lane` is this worktree's absolute root:

```sh
cargo test --manifest-path "$lane/Cargo.toml" --locked \
  --target-dir "$lane/_build/native-tests" -p motoko-compute-ml-dsa
cargo test --manifest-path "$lane/Cargo.toml" --locked --release \
  --target-dir "$lane/_build/native-tests" -p motoko-compute-ml-dsa
test-runner -b -j2 "$lane/plugins/ml-dsa/tests/run"
```

- Native debug: **15 passed**, 0 failed (2.29 s).
- Native release: **15 passed**, 0 failed (0.06 s).
- Public fixtures: **2 passed**, 0 failed (2.19 s); each passes Motoko, IR,
  lowered IR and compiled Wasm. All diagnostics/output/diffs are empty.
- `git diff --check`: clean.

An initial public-key-edge test used the reserved identifier `public`; that
fixture-only syntax error was corrected to `rawPublic` and the public suite
rerun successfully. Production code did not change. Raw logs and generated
Wasm remain in ignored `_build/round5` and test `_out` directories; the validation
record pins the compact evidence.

Existing direct/prepared Ash suites already test retained handles and confirmed
collection. Central integration was asked to rerun them; no new Ash result is
claimed here. These bounds tests respect the native FFI's live-buffer/disjoint-
output preconditions; they are not arbitrary invalid-pointer fuzzing or a
sanitizer run.
