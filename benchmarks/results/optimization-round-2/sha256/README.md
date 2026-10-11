# SHA-256 second optimization round

**Retained the existing implementation.** Two small alternatives increased both
instruction cost and Wasm size. No production source, API, ABI, or tests changed.
This report records a bounded investigation rather than claiming a new speedup.

The existing kernel keeps its unrolled rolling schedule in Wasm locals, borrows
input directly, and folds the padding for 32/64-byte inputs. Its fixed-size
length restriction is already checked at compilation. The empty path writes its
constant digest directly. There is no heap allocation inside the Rust kernel;
Motoko allocates the result Blob.

## Fresh measurements

Both versions use Motoko `c320bf90d0b63a058b5de2c41a42c96e8b82243f` and the
unchanged SHA sources from plugins `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`.
The compiler was not rebuilt. Baseline used the copied, matching package; final
used a fresh package build after reverting both experiments.

All 18 input sizes have three fresh PocketIC trials per implementation/version.
Every baseline/final count is identical, every digest matches Python
`hashlib.sha256`, and no measured phase reclaims memory.

| Input bytes | Baseline = final plugin instructions | Mops sha2 instructions |
| ---: | ---: | ---: |
| 0 | 445 | 19,766 |
| 1 | 5,770 | 25,154 |
| 31 | 5,800 | 28,080 |
| 32 | 4,966 | 27,968 |
| 33 | 5,802 | 28,278 |
| 55 | 5,824 | 30,456 |
| 56 | 10,598 | 49,213 |
| 63 | 10,605 | 50,117 |
| 64 | 8,322 | 41,857 |
| 65 | 10,538 | 46,891 |
| 119 | 10,592 | 52,193 |
| 120 | 15,366 | 70,950 |
| 127 | 15,373 | 71,854 |
| 128 | 15,200 | 61,614 |
| 129 | 15,306 | 66,648 |
| 1,024 | 81,952 | 338,212 |
| 65,536 | 4,888,128 | 20,253,300 |
| 1,048,576 | 78,124,848 | 323,721,060 |

Each plugin call allocates **56 bytes**; Mops `sha2` 0.2.5 allocates **1,008 bytes**.
These are cumulative managed allocations, not peak or live memory. The native
comparison calls `Sha256.fromBlob(#sha256, bytes)` with `core` 2.5.0.
All 100 archived dependency files were checked against the frozen cache.

Both runtime Wasm files are byte-identical (29,350 bytes), as are both complete
benchmark actors (440,571 bytes). The native `.cmxs` files differ because final
was rebuilt in this worktree; their sources are unchanged. We do not claim
whole-package byte identity. Exact hashes are in [provenance.json](provenance.json).

## Rejected pilots

These are one-trial exploratory measurements using the same actor and oracle;
the full baseline/final comparison above uses three trials.

| Alternative | 1 MiB instructions | Change | Runtime Wasm bytes |
| --- | ---: | ---: | ---: |
| Existing implementation | 78,124,848 | — | 29,350 |
| Load two schedule words through one big-endian `u64` | 81,123,303 | +3.84% | 30,167 |
| Counted input/padding block selector | 78,403,395 | +0.36% | 29,580 |

Paired loads also regress at 32 bytes (4,966 → 5,056) and 64 bytes
(8,322 → 8,505). A counted selector preserves one compression body but adds
index/bounds work: 55 bytes rises from 5,824 to 5,843, and 56 bytes from 10,598
to 10,624. Empty and fixed-size paths are unchanged where the pilot does not
touch them. All pilot allocation counts and outputs match baseline.

[experiments.csv](experiments.csv) preserves every pilot row, including unchanged
rows. [rejected/](rejected/) contains exact patches and raw results. Prior-round
iterator-chain and grouped-round experiments were not repeated.

## Validation and reproduction

Three Rust tests pass, including standard vectors, a million-byte message,
padding boundaries, 32/64-byte extremes, unaligned buffers, output sentinels,
and input immutability. Seven Motoko fixtures pass, including composition,
argument rejection, and GC stress. No expectations changed. See
[rust-tests.log](rust-tests.log), [motoko-tests.log](motoko-tests.log), and the
independent [audit](audit.md).

The exact actor, cases, generator, and runner are archived here. Input setup and
output validation are outside the measured call. Each workload/trial uses a
fresh canister; output is cleared and four forced GC increments precede each
phase. Counter/assignment overhead and synchronous GC are included;
end-of-message GC is excluded. Raw files retain the complete protocol.

Enter `nix develop` from the frozen compiler checkout, then change to the plugin
checkout. Build only SHA with
`scripts/build.sh --motoko "$MOTOKO" --skip-motoko-build sha256`. Compile
`main.mo` with `--plugin "$PACKAGE"`, `--package sha2 "$DEPS/sha2@0.2.5/src"`,
and `--package core "$DEPS/core@2.5.0/src"`. Run the archived `run.mjs` with
`--wasm "$WASM" --cases "$REPORT/cases.json" --out "$RESULT" --trials 3`
and the SDK/canonicalizer overrides documented in the benchmark guide.
Preserve baseline before rebuilding and use fresh output paths.

`python3 benchmarks/results/optimization-round-2/sha256/verify.py` checks the
216 paired measurements, 28 pilot measurements, regenerated input oracles,
artifact links, and both CSV summaries without running a canister.
