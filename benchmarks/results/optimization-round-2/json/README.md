# JSON second optimization round

Two small changes remove repeated work without changing the format, limits,
error precedence, paths, ABI or API:

- The compiler emits the known UTF-8 byte length of literal field labels and
  punctuation instead of reading it from the same literal's Blob at runtime.
- Arbitrary-precision integer encoding writes decimal chunks into one reserved
  byte vector using the existing `decimal_word` helper. It no longer allocates
  a formatting String for each group of nine digits. The integer conversion
  algorithm and its bounds remain unchanged.

The large gains are for arbitrary-precision integer encoding. Ordinary record
encoding and decoding improve by less than 1%; Blob, Text and integer decoding
are unchanged. All 53 successful measured phases either improve or retain the
same instruction count; none allocate more. Two native-library phases retain
known stack overflows rather than reported timings.

| Workload | Before instructions | After instructions | Reduction | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Nat zero encode | 3,641 | 3,181 | 12.63% | 496 | 472 |
| Nat 123456789 encode | 5,287 | 5,007 | 5.30% | 600 | 560 |
| Nat 1000000000 encode | 8,139 | 5,264 | 35.32% | 696 | 568 |
| Nat 18446744073709551615 encode | 13,338 | 10,394 | 22.07% | 920 | 736 |
| Int −2^127 encode | 26,597 | 21,729 | 18.30% | 1,872 | 1,536 |
| 128-digit Nat encode | 57,819 | 45,287 | 21.67% | 2,360 | 1,560 |
| 4,096-digit Nat encode | 10,721,483 | 10,391,888 | 3.07% | 53,296 | 30,768 |
| 128-element array of 128-digit Ints encode | 9,077,357 | 5,378,517 | 40.75% | 379,336 | 201,672 |
| Focused small record encode | 8,803 | 8,763 | 0.45% | 776 | 776 |
| Focused 1,024 records encode | 5,034,822 | 4,996,590 | 0.76% | 193,832 | 193,832 |
| Focused 1,024 records decode | 18,293,519 | 18,252,559 | 0.22% | 129,104 | 129,104 |
| Late record error | 18,308,310 | 18,267,326 | 0.22% | 129,440 | 129,440 |

The existing native comparison actor has different record fields from the
focused actor. Its results remain a comparison of complete operations,
including required typed/tree or Candid conversions, rather than just the
plugin boundary. Native-library costs are exactly unchanged between versions.

| Native comparison workload | Best successful native instructions | Plugin before | Plugin after | Native / final plugin | Native allocated bytes | Plugin allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Small record encode (`json` 1.4.0) | 79,183 | 9,553 | 9,517 | 8.32× | 8,472 | 976 |
| Small record decode (`json` 1.4.0) | 266,644 | 14,128 | 14,088 | 18.93× | 25,312 | 1,008 |
| 1,024 records encode (`json` 1.4.0) | 53,258,267 | 5,081,644 | 5,044,780 | 10.56× | 7,145,616 | 194,176 |
| 1,024 records decode (`serde` 3.5.0) | 763,222,636 | 18,251,729 | 18,210,769 | 41.91× | 136,203,896 | 172,816 |
| 64 KiB Text encode (`json` 1.4.0) | 89,974,425 | 765,024 | 765,024 | 117.61× | 5,244,360 | 262,576 |
| 64 KiB Text decode (`json` 1.4.0) | 161,941,413 | 739,230 | 739,230 | 219.07× | 8,043,472 | 65,864 |

The `serde` and `serde-core` 64 KiB Text decoders overflow the stack in all three
trials in both versions. All six failed measurements per version remain in
[native/baseline.json](native/baseline.json) and [native/final.json](native/final.json).
Every plugin phase passes. The [complete CSV](summary.csv) contains all
55 phases, including integer decoding, empty collections, escaped error paths,
all three native libraries and their failures.

Fresh paired runs use three trials per workload and version with identical
actors, manifests, compiler and runner. Counters are deterministic and output
hashes match. Inputs and four forced GC increments precede the timed interval;
validation and message-end GC follow it. Synchronous reclamation is zero in all
successful phases. Allocated bytes are cumulative heap allocation, including
scratch, **not peak memory or retained heap**. Decoders return a two-byte `ok`
validation marker, not the decoded heap size.

The literal-only pilot and integer-formatting pilot are retained under
[pilots](pilots/). The latter's numeric actor contains no record field labels,
so it isolates the formatting change. The baseline compiler is frozen at
`c320bf90d0b63a058b5de2c41a42c96e8b82243f`, binary SHA-256
`722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`.
All 19 source hashes recorded by the copied baseline package match plugin
revision `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`.
[Provenance](provenance.json), [baseline package](package-baseline.json) and
[final package](package-final.json) identify sources, dependencies and binaries.
Prior optimization reports remain unchanged.

Validation passed: 20 Rust tests, all 10 JSON Motoko fixtures (including GC and
compile-failure expectations), 604 independent scalar cases, 161 binary/Unicode
cases and 9,263 Python-derived syntax cases. The permanent decimal roundtrip
test now covers nine-digit group boundaries and internal zero groups with both
signs. The benchmark separately checks Python-generated decimal strings against
compiled Motoko integers through 4,096 digits. [Independent audit](audit.md)
adds a direct Python-generated LEB oracle without sharing the runtime decoder.

To reproduce inside the selected compiler's Nix environment, copy the archived
actors/manifests into scratch, save the baseline package before editing, and
compile both versions against those packages. Build only JSON; do not rebuild
the compiler. The native helper verifies the full frozen Mops dependency lock.

```sh
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build json
python3 benchmarks/generate-json-integer-optimization.py --out _build/json-numbers
"$MOTOKO_ROOT/bin/moc" --plugin dist/json \
  _build/json-numbers/main.mo -o _build/json-numbers/main.wasm
node benchmarks/results/optimization-round-2/json/run.mjs \
  --wasm _build/json-numbers/main.wasm --cases _build/json-numbers/cases.json \
  --out _build/json-numbers/results.json --label json-integers --trials 3 \
  --delete-canisters true --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
python3 benchmarks/build-codec-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps "$CODEC_DEPS" --codec json --out _build/json-native
python3 benchmarks/results/optimization-round-2/json/summarize.py
```

For the native command, first copy this report's `native/main.mo` and
`native/cases.json` to `_build/json-native`. Run the same harness on its generated
`main.wasm`; exit 1 is expected only for the six declared stack-overflow rows.
The final command validates the frozen complete paired archive and regenerates
`summary.csv`; it does not substitute fresh results for the archived baseline.
