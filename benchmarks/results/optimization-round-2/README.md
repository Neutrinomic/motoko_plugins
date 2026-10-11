# Second optimization round

Six implementation agents covered the SDK and five plugins, followed by six
independent component auditors. Accepted changes remove repeated work and reuse
existing mechanisms. ABI remains **1**; public APIs and wire formats are unchanged.

The paired measurements below compare each change against compiler `c320bf90d`
and plugin revision `0df5cd2`. Each side has three trials with identical inputs,
compiler, dependency versions and validation. The SDK comparison changes only
the compiler to `128a41c06`. Allocation means cumulative allocated bytes,
including temporary garbage, **not peak or retained heap**. No synchronous
reclamation occurred in these measurements.

| Component / workload | Before instructions | After instructions | Reduction | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSON, encode 128 × 128-digit Ints | 9,077,357 | 5,378,517 | 40.75% | 379,336 | 201,672 |
| JSON, encode 1,024 records | 5,081,644 | 5,044,780 | 0.73% | 194,176 | 194,176 |
| JSON, decode 1,024 records | 18,251,729 | 18,210,769 | 0.22% | 172,816 | 172,816 |
| CBOR, decode 1,024 Nats | 1,475,341 | 1,178,719 | 20.11% | 41,360 | 8,688 |
| CBOR, decode 1,024 Ints | 1,458,464 | 1,162,511 | 20.29% | 41,360 | 8,624 |
| CandidX, encode 6,000 values / 64 variant cases | 10,756,837 | 6,651,200 | 38.17% | 276,776 | 16,504 |
| CandidX, encode 1,024 sparse records | 6,140,310 | 6,057,260 | 1.35% | 22,624 | 22,600 |
| Pure map, shuffled `fromIter`, 100,000 entries | 1,255,250,803 | 1,204,273,073 | 4.06% | 76,471,536 | 76,471,536 |
| SDK, 1,000 Nat32 hits in a 100,000-entry map | 1,159,429 | 1,095,405 | 5.52% | 0 | 0 |
| SHA-256, 1 MiB | 78,124,848 | 78,124,848 | unchanged | 56 | 56 |

The [repository README](../../../README.md) compares the plugins with native
libraries and retains the full map function tables at 1,000 / 10,000 / 100,000
entries. Those library comparisons measure complete implementations, including
required conversions and adapters; they do not isolate the plugin boundary.

## Accepted changes and limitations

- [SDK](sdk/README.md): compare same-type small scalar representations directly,
  eliminating two redundant shifts. This saves exactly four IC instructions per
  comparison for Nat8/16/32, Int8/16/32 and Char. Bool normalization, boxed 64-bit
  integers and arbitrary-precision values retain their previous handling.
  Nat32/Int32 map lookups improve 4.03–5.52%; updates improve 1.29–1.41%.
  Production code shrinks by one line. No additional runtime validation was added.
- [JSON](json/README.md): fold known literal byte lengths during compilation and
  write decimal integer chunks with the existing writer, removing intermediate
  formatting Strings. Large-integer encoding benefits most; ordinary records
  improve less than 1%. Six native serde stack-overflow samples per version remain
  recorded as failures, without timings presented as successful results.
- [CBOR](cbor/README.md): reuse integer decode scratch and combine sign/continuation
  handling into the existing byte pass. Unbounded Nat/Int decoding improves;
  fixed-width record, Blob and native-comparison costs remain unchanged. Input
  limits and checks remain in place. The simpler terminal-error fallback was
  retained after measuring a slower alternative.
- [CandidX](candidx/README.md): replace the primitive-variant collector/sort/dedup
  path with generated presence bits and existing canonical field builders.
  Bounded generated helpers preserve acceptance of the tested 4,096-case type.
  Production code shrinks by 97 lines. Three sparse 4,096-case workloads use
  **4.13%, 6.82% and 13.59% more instructions**. Actor size increases about
  **2.3–2.9%** for ordinary actors and **6.56%** for the wide actor. These are
  explicit tradeoffs for repeated-variant throughput and allocation gains.
- [Pure map](pure-map/README.md): express read-only search as a loop, retaining the
  depth guard, and avoid duplicate tuple loads in stable merging. Large lookup
  workloads improve 2.46–3.13% with callbacks and 4.71–5.69% with scalar ordering;
  shuffled construction improves 3.42–4.47%. Allocation and structural sharing
  are unchanged. Shuffled `fromIter` now beats Core at 100,000 entries, while Core
  remains faster at 1,000 and 10,000. Cursor/snapshot creation and previously
  slower intersection cases remain visible in the full comparison.
- [SHA-256](sha256/README.md): production is unchanged. Paired 64-bit loads and a
  counted block/padding loop increased both instructions and Wasm size, so both
  were rejected. The existing implementation remains 4.14× faster than the
  measured Mops implementation at 1 MiB.

## Validation and provenance

Each component report links its independent audit, exact raw results, source and
artifact hashes, unsuccessful experiments, commands and portable archive checks.
Correctness checks include separate integer/encoding oracles, retained values
through forced GC, exact depth boundaries, generic payload identity, compile-time
rejections and CandidX upstream conformance/fuzzing. The
[integration check](integrated/README.md) records compilation with the final
compiler and packages; historical trials retain their measured compiler labels.

CI validates archived samples and regenerates summaries in a temporary copy.
The [first round](../optimization-round/README.md) remains immutable. Benchmarks
are workload-specific evidence: they neither establish a universal speedup nor
compare against a future optimized Motoko component implementation.
