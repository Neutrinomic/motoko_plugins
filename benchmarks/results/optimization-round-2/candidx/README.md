# CandidX primitive variant arrays, second optimization round

Primitive variant arrays now collect observed cases in Wasm integer locals:
one bit per declared case. The compiler emits each selected field once, in
canonical order. This removes the runtime collector, its input-sized scratch
buffer, sort, duplicate checks, three helper exports and five dead internal
errors. Production implementation is 97 lines shorter, excluding removed tests.
The public result, canonical bytes, ABI 1 and all limits are unchanged.

| Workload | Before instructions | After instructions | Change | Allocation before → after |
|---|---:|---:|---:|---:|
| Repeated 6,000 values / 64 tags | 10,756,837 | 6,651,200 | −38.17% | 276,776 → 16,504 B |
| Repeated 4,096 values / 4 tags | 5,562,376 | 3,505,748 | −36.97% | 140,552 → 9,360 B |
| Repeated 1,024 values / 1 tag | 851,588 | 726,171 | −14.73% | 3,016 → 3,008 B |
| 1,024 distinct tags | 2,345,613 | 2,269,134 | −3.26% | 60,288 → 60,280 B |
| Sparse records, 1,024 | 6,140,310 | 6,057,260 | −1.35% | 22,624 → 22,600 B |
| 4,096 declared cases, 2 equal high tags | 11,657 | 12,138 | **+4.13%** | 968 → 960 B |
| 4,096 declared cases, 2 distant tags | 13,044 | 13,933 | **+6.82%** | 1,048 → 1,040 B |
| 4,096 declared cases, 65 spread tags | 151,475 | 172,067 | **+13.59%** | 6,800 → 6,792 B |

The first five rows use the native-comparison actors. Empty and singleton
variant arrays have exactly unchanged costs. The three sparse, wide-type
regressions are the cost of scanning bits in populated words. This tradeoff is
accepted for the large repeated-data gains, lower scratch allocation and
smaller implementation; this is not a universal speedup. The common builder's
removed collector-only count and mode handling also slightly improves records.

All 93 selected phases ran three trials before and after with the same compiler,
actor source and inputs: 558 measurements total. Of 40 plugin/control entries,
15 improve, 22 are unchanged and 3 regress. Every output hash matches; every
phase is deterministic across trials and reports zero synchronous reclamation.
Allocation means cumulative `rts_total_allocation`, not retained or peak heap.
All native canonical-library and normalization-only phase costs remain identical.
One ordinary-Candid contextual phase changes by 32 instructions
(1,365,156 → 1,365,188, +0.00234%); this small variation is retained in the raw data.

## Native comparison

Both implementations run in the same actor with the same input. Native CandidX
includes `to_candid(value)` followed by the Motoko library's `canonicalize` and
successful result unwrapping. Normalizing an already encoded Blob is recorded
separately and is not presented as complete encoding.

| Workload | Native instructions | Plugin instructions | Native / plugin | Native / plugin allocation |
|---|---:|---:|---:|---:|
| Sparse records, 1,024 | 88,379,476 | 6,057,260 | 14.59× | 3,578,064 / 22,600 B |
| Distinct tags, 1,024 | 1,428,890,507 | 2,269,134 | 629.71× | 27,091,416 / 60,280 B |
| Repeated 6,000 / 64 tags | 1,292,451,084 | 6,651,200 | 194.32× | 33,637,552 / 16,504 B |

## Code size and supported widths

Each 64-bit word uses one small generated field-emission helper, with an exact,
collision-free key containing only its ordered canonical labels and primitive
opcodes. Equal groups can share code across source types and word positions.
Helpers propagate typed errors before completing the enclosing shape. Empty
and singleton paths are unchanged. Original element visits and depth checks
still occur before collection; local bits do not suppress visit charges.

The final ordinary and native actors grow by 31,445 bytes (2.3–2.9%); the
4,096-case actor grows 2,375,752 → 2,531,571 bytes (+6.56%). Three alternating
fresh compiler processes took median 2.44 → 2.47 seconds for the main actor.
These host timings were collected during other component work and are not IC
instruction measurements; they establish no meaningful compilation speedup.

An initial inline field-emission candidate failed the IC's per-function
complexity limit at 4,096 source cases. Reusing its status temporary did not
help. Bounded word helpers fix that regression. A whole-source-type helper key
was also discarded because repeated debug names nearly doubled the wide actor.
The final 4,096-case actor installs and passes all comparisons. Both baseline
and final candidate still fail to install the 8,192-case narrow-reference actor
with the same existing complexity 1,646,545 > 1,000,000. These failed installs
are preserved under [rejected/](rejected/); zero measurements is not success.
The broader 8,192-case ordinary serializer also exceeds the limit independently.

## Validation and reproduction

- [Independent audit](audit.md): 23 Rust tests, all 15 Motoko fixtures, and a
  256-subset independent byte oracle across bit positions 0/31/32/63/64/95/127/128
  with mixed primitive payloads, tested in the source, IR, lowered IR and Wasm
  engines. Extra cases check sharing a group at different word positions and
  keeping equal labels with different payload opcodes separate.
- The new committed fixture covers exact 2,000,000 visits versus one too many,
  fresh local bits on repeated helper calls, and successful encoding after an
  error. Six tests specific to the deleted Rust collector were removed.
- [Upstream conformance](conformance.json): 61 frozen golden cases, 93 direct
  typed cases, 476 binary comparisons per implementation, and the native
  library's 473 positive / 397 negative regression cases.
- Two fresh 500-record fuzz seeds, [0xcad1d](fuzz-0xcad1d.json) and
  [0x5eedc0de](fuzz-0x5eedc0de.json), each pass 1,130 typed records, 93 directed
  cases, independent canonical-byte checks and original-value recovery.
  No upstream source was changed, and no `cx.wasm` artifact was loaded.
- [Complete comparison](summary.csv), [provenance](provenance.json), source and
  package hashes, exact actors/manifests and raw trials are archived here.
  `python3 benchmarks/results/optimization-round-2/candidx/verify-summary.py`
  checks complete selected cohorts, all three trials, hashes and outputs before
  regenerating the CSV. Prior optimization reports remain unchanged.

The compiler is frozen at `c320bf90d0b63a058b5de2c41a42c96e8b82243f`; the
before package is plugins revision `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`.
Rebuild that package with this exact compiler, retain it separately, then build
the candidate with `scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build candidx`.
Compile each archived actor with `--plugin <selected-candidx-package>` and
`--plugin dist/sha256`; native actors additionally use `--package candidx
/srv/shared/code/candidx/motoko/src`, `sha2@0.2.5`, and `core@2.5.0` at the exact
paths/hashes in provenance. Run the archived `run.mjs` using three trials and
its original location or the repository runner with the same hash:

```sh
node benchmarks/run.mjs --wasm <actor.wasm> --cases <cases.json> \
  --out <result.json> --label <baseline-or-candidate> --trials 3 \
  --filter <selection-from-provenance> \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js --delete-canisters true
```

Run tests from the compiler's Nix shell, retaining absolute `run`/`fail` paths.
The upstream invocation records and complete commands are in provenance and
`compiler-invocations.jsonl`; the upstream revision and oracle hashes are pinned.
