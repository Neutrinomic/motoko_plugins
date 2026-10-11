# Motoko plugins

Native compiler plugins for fast computation in Motoko. Each package
adds functions to `Prim`, specializes calls during compilation, and links its
optional Wasm runtime into the canister. Plugin code reads Motoko values through the
compiler's memory and GC helpers. The SDK also supports typed mutation of
caller-owned Motoko arrays and records through the ordinary GC write barriers.

## Instruction and allocation costs

Recorded PocketIC measurements for the ABI 1 plugins, using the same compiler
and typed inputs within each comparison. Lower is better. For JSON/CBOR, the
comparison below uses the lowest instruction count among the three tested
native libraries for each row.

| Operation | Native Motoko library | Native instructions | Plugin instructions | Native/plugin | Native allocated bytes | Plugin allocated bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| JSON encode, 1,024 records | `json 1.4.0` | 53,258,267 | 5,044,780 | 10.56× | 7,145,616 | 194,176 |
| JSON decode, 1,024 records | `serde 3.5.0` | 763,222,636 | 18,210,769 | 41.91× | 136,203,896 | 172,816 |
| CBOR encode, 1,024 records | `cbor 4.1.0` | 49,934,053 | 5,395,241 | 9.26× | 2,452,232 | 174,160 |
| CBOR decode, 1,024 records | `cbor 4.1.0` | 152,527,112 | 7,324,274 | 20.82× | 11,545,504 | 173,128 |
| CandidX encode, 1,024 sparse records | CandidX `94c2868` | 88,379,476 | 6,057,260 | 14.59× | 3,578,064 | 22,600 |
| SHA-256, 1 MiB | `sha2 0.2.5` | 323,721,060 | 78,124,848 | 4.14× | 1,008 | 56 |

Three trials; medians shown. Counts include conversions between typed values
and each library's representation. Input setup, validation, reply encoding,
and message-end GC are excluded. These measure complete implementations,
not the isolated benefit of the plugin boundary or Wasm components.
Allocated bytes include results and temporary garbage during the measured call;
they measure allocation pressure, not peak memory or retained live bytes after
GC. The same library supplies native instruction and allocation counts, chosen
by instruction cost.
Measured results: [JSON](benchmarks/results/optimization-round-2/json/README.md),
[CBOR](benchmarks/results/optimization-round-2/cbor/README.md),
[CandidX](benchmarks/results/optimization-round-2/candidx/README.md), and
[SHA-256](benchmarks/results/optimization-round-2/sha256/README.md).
They include smaller inputs, large payloads, and the observed serde stack
overflows on 64 KiB JSON strings.
The [second optimization report](benchmarks/results/optimization-round-2/README.md)
compares each plugin and the SDK before/after, with independent audits and
tradeoffs. Large-integer JSON encoding uses 40.75% fewer instructions and 46.84%
less allocation; CBOR Nat/Int array decoding uses about 20% fewer instructions
and 79% fewer allocated bytes.
These are different workloads from the record comparison above. Repeated-variant
CandidX encoding uses about 38% fewer instructions and 94% fewer allocated bytes,
while three sparse 4,096-case variant workloads use 4–14% more instructions. SHA-256 is unchanged after rejecting
slower alternatives.
The [first optimization report](benchmarks/results/optimization-round/README.md)
and [original library comparison](benchmarks/results/codec-comparison/README.md)
retain their original measurements.

## Mutable map costs

The mutable plugin updates ordinary Motoko nodes in place; keys and values stay
shared references. The baseline here is **mutable `mo:core/Map` 2.5.0**.
These measurements use compiler `abfba892f`, ABI 1, boxed `Nat64` keys and `Nat`
values. The callback path uses the same Motoko comparator as Core. Scalar
ordering removes that callback while keeping values generic.

Selected results at **100,000 entries** follow. Point operations are averages
per call in a 32-call batch; scans, transformations and construction are whole
function calls. Each result is the median of three identical trials.

| Operation | Core instructions | Plugin callback instructions | Plugin scalar instructions | Core allocated B | Plugin allocated B | Core/callback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `get`, hit | 7,700.16 | 3,877.41 | 2,755.84 | 123.00 | 0.00 | 1.99× |
| `add`, new key | 12,818.28 | 5,499.44 | 5,046.28 | 324.00 | 40.00 | 2.33× |
| `add`, overwrite | 8,528.06 | 4,492.91 | 3,439.84 | 286.00 | 40.00 | 1.90× |
| `delete`, hit | 14,111.88 | 7,835.81 | — | 520.25 | 0.00 | 1.80× |
| `find`, full scan | 170,277,593.00 | 40,524,835.00 | — | 11,059,840.00 | 72.00 | 4.20× |
| `fromIter`, shuffled construction | 1,175,071,733.00 | 566,138,242.00 | — | 30,051,776.00 | 5,842,360.00 | 2.08× |
| `map`, full transform | 60,103,065.00 | 76,139,742.00 | — | 6,441,152.00 | 5,842,432.00 | 0.79× |

Allocation is cumulative allocated bytes, including temporary garbage and
results, **not peak or retained live memory**. Scalar allocation matches the
callback path in these headline rows. Setup, seed cloning, correctness checks,
and message-end GC are outside the measured interval; all 900 measured samples
had zero synchronous reclamation. Normal updates do not clone the map.
Core has no matching `find` or `getEntry` function; their baselines use the small
public-API adapters listed in the full table.

The plugin uses fewer instructions in 135 workloads, ties in two, and loses in
one; `size` and `isEmpty` are effectively at parity. The 100,000-entry `map`
transform uses **26.7% more instructions**, with fewer allocated bytes.
Scalar ordering is not always cheaper: 100,000-entry `removeNat64` uses more
instructions than the callback path, while both use fewer than Core.
These are comparisons of complete implementations, including
wrapper functions, rather than a measurement of plugin dispatch alone.

The [full report](benchmarks/results/mutable-map/README.md) records reproduction
commands, the [independent audit](benchmarks/results/mutable-map/audit/README.md),
and the [performance review](benchmarks/results/mutable-map/performance-review.md).
The tables below retain all **138 workloads** at **1,000, 10,000, and 100,000
entries**, plus **24 scalar comparisons**. They cover lookup, insertion,
replacement, removal, predicate search, iteration, folds, transforms, cloning,
clearing and construction. Sorted input is ascending; shuffled input uses a
fixed permutation of the same entries. These are 46 workload variants per
size, not a claim that every convenience wrapper was benchmarked.

<details>
<summary>Full mutable-map function and scalar comparison tables</summary>

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](benchmarks/results/mutable-map/final/README.md) for exact semantics and validation.

### Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |
| `Map.fromArray` | fromArray-shuffled | 10,000 | 98,357,223.00 | 47,262,036.00 | 2,460,400.00 | 591,264.00 | 2.08× |
| `Map.fromArray` | fromArray-shuffled | 100,000 | 1,175,072,361.00 | 566,138,870.00 | 30,051,928.00 | 5,842,512.00 | 2.08× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,210.00 | 3,960,904.00 | 196,568.00 | 59,256.00 | 2.10× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 98,356,595.00 | 47,261,408.00 | 2,460,248.00 | 591,112.00 | 2.08× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,175,071,733.00 | 566,138,242.00 | 30,051,776.00 | 5,842,360.00 | 2.08× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,305.00 | 3,397,773.00 | 222,216.00 | 65,400.00 | 1.92× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 81,252,701.00 | 42,662,313.00 | 2,617,368.00 | 656,296.00 | 1.90× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 996,350,488.00 | 514,898,108.00 | 32,024,568.00 | 6,559,048.00 | 1.94× |
| `Map.fromVarArray` | fromVarArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |
| `Map.fromVarArray` | fromVarArray-shuffled | 10,000 | 98,357,223.00 | 47,262,036.00 | 2,460,400.00 | 591,264.00 | 2.08× |
| `Map.fromVarArray` | fromVarArray-shuffled | 100,000 | 1,175,072,377.00 | 566,138,870.00 | 30,051,928.00 | 5,842,512.00 | 2.08× |

### Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 200.00 | 40.00 | 2.07× |
| `Map.add` | add-insert | 10,000 | 10,115.12 | 5,153.06 | 230.00 | 63.00 | 1.96× |
| `Map.add` | add-insert | 100,000 | 12,818.28 | 5,499.44 | 324.00 | 40.00 | 2.33× |
| `Map.add` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 230.00 | 40.00 | 1.92× |
| `Map.add` | add-overwrite | 10,000 | 6,920.69 | 4,066.25 | 230.00 | 63.00 | 1.70× |
| `Map.add` | add-overwrite | 100,000 | 8,528.06 | 4,492.91 | 286.00 | 40.00 | 1.90× |
| `Map.all` | all-true | 1,000 | 1,626,450.00 | 351,618.00 | 110,776.00 | 112.00 | 4.63× |
| `Map.all` | all-true | 10,000 | 16,250,883.00 | 3,510,212.00 | 1,104,912.00 | 112.00 | 4.63× |
| `Map.all` | all-true | 100,000 | 162,473,523.00 | 38,624,994.00 | 11,059,840.00 | 112.00 | 4.21× |
| `Map.any` | any-false | 1,000 | 1,626,450.00 | 320,465.00 | 110,776.00 | 72.00 | 5.08× |
| `Map.any` | any-false | 10,000 | 16,250,883.00 | 3,200,059.00 | 1,104,912.00 | 72.00 | 5.08× |
| `Map.any` | any-false | 100,000 | 162,473,523.00 | 35,524,792.00 | 11,059,840.00 | 72.00 | 4.57× |
| `Map.clear` | clear | 1,000 | 2,171.00 | 355.00 | 488.00 | 0.00 | 6.12× |
| `Map.clear` | clear | 10,000 | 2,171.00 | 371.00 | 488.00 | 0.00 | 5.85× |
| `Map.clear` | clear | 100,000 | 2,171.00 | 371.00 | 488.00 | 0.00 | 5.85× |
| `Map.clone` | clone | 1,000 | 483,718.00 | 274,607.00 | 66,104.00 | 23,656.00 | 1.76× |
| `Map.clone` | clone | 10,000 | 4,890,614.00 | 2,715,273.00 | 665,536.00 | 235,200.00 | 1.80× |
| `Map.clone` | clone | 100,000 | 46,303,078.00 | 27,726,005.00 | 6,441,152.00 | 2,268,456.00 | 1.67× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 5,334.41 | 2,565.41 | 95.00 | 0.00 | 2.08× |
| `Map.containsKey` | containsKey-mixed | 10,000 | 6,389.16 | 3,108.16 | 95.00 | 0.00 | 2.06× |
| `Map.containsKey` | containsKey-mixed | 100,000 | 7,939.84 | 3,911.09 | 125.00 | 0.00 | 2.03× |
| `Map.delete` | delete-hit | 1,000 | 10,289.19 | 3,873.62 | 357.75 | 0.00 | 2.66× |
| `Map.delete` | delete-hit | 10,000 | 11,314.97 | 6,486.53 | 360.25 | 0.00 | 1.74× |
| `Map.delete` | delete-hit | 100,000 | 14,111.88 | 7,835.81 | 520.25 | 0.00 | 1.80× |
| `Map.delete` | delete-miss | 1,000 | 6,936.62 | 2,921.78 | 320.00 | 0.00 | 2.37× |
| `Map.delete` | delete-miss | 10,000 | 8,066.88 | 5,480.22 | 320.00 | 0.00 | 1.47× |
| `Map.delete` | delete-miss | 100,000 | 10,433.16 | 6,947.97 | 464.00 | 0.00 | 1.50× |
| `Map.entries` | entries-consume | 1,000 | 1,696,599.00 | 945,701.00 | 110,776.00 | 352.00 | 1.79× |
| `Map.entries` | entries-consume | 10,000 | 16,951,848.00 | 9,447,915.00 | 1,104,912.00 | 352.00 | 1.79× |
| `Map.entries` | entries-consume | 100,000 | 169,477,640.00 | 104,840,203.00 | 11,059,840.00 | 352.00 | 1.62× |
| `Map.entries` | entries-create | 1,000 | 3,165.38 | 1,848.38 | 432.00 | 352.00 | 1.71× |
| `Map.entries` | entries-create | 10,000 | 3,167.38 | 1,850.38 | 432.00 | 352.00 | 1.71× |
| `Map.entries` | entries-create | 100,000 | 3,868.75 | 1,890.75 | 512.00 | 352.00 | 2.05× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 35,069.38 | 24,661.12 | 2,267.00 | 792.00 | 1.42× |
| `Map.entriesFrom` | entriesFrom-seek16 | 10,000 | 36,321.12 | 26,986.38 | 2,292.00 | 927.00 | 1.35× |
| `Map.entriesFrom` | entriesFrom-seek16 | 100,000 | 38,699.75 | 29,808.75 | 2,376.00 | 1,082.00 | 1.30× |
| `Map.filter` | filter | 1,000 | 4,476,594.00 | 1,851,216.00 | 204,784.00 | 32,288.00 | 2.42× |
| `Map.filter` | filter | 10,000 | 54,291,831.00 | 23,460,534.00 | 2,377,656.00 | 327,552.00 | 2.31× |
| `Map.filter` | filter | 100,000 | 634,923,429.00 | 307,720,064.00 | 26,747,752.00 | 3,280,048.00 | 2.06× |
| `Map.filterMap` | filterMap | 1,000 | 4,514,594.00 | 1,888,216.00 | 204,784.00 | 32,288.00 | 2.39× |
| `Map.filterMap` | filterMap | 10,000 | 54,671,831.00 | 23,830,534.00 | 2,377,656.00 | 327,552.00 | 2.29× |
| `Map.filterMap` | filterMap | 100,000 | 638,723,429.00 | 311,420,064.00 | 26,747,752.00 | 3,280,048.00 | 2.05× |
| `Map.find` | find-first | 1,000 | 5,101.00 | 2,027.00 | 544.00 | 72.00 | 2.52× |
| `Map.find` | find-first | 10,000 | 5,101.00 | 2,043.00 | 544.00 | 72.00 | 2.50× |
| `Map.find` | find-first | 100,000 | 5,788.00 | 2,448.00 | 624.00 | 72.00 | 2.36× |
| `Map.find` | find-last | 1,000 | 1,704,466.00 | 370,371.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.find` | find-last | 10,000 | 17,031,715.00 | 3,699,965.00 | 1,104,912.00 | 72.00 | 4.60× |
| `Map.find` | find-last | 100,000 | 170,277,507.00 | 40,524,763.00 | 11,059,840.00 | 72.00 | 4.20× |
| `Map.find` | find-middle | 1,000 | 856,010.00 | 186,188.00 | 55,904.00 | 72.00 | 4.60× |
| `Map.find` | find-middle | 10,000 | 8,521,210.00 | 1,852,989.00 | 552,800.00 | 72.00 | 4.60× |
| `Map.find` | find-middle | 100,000 | 85,147,713.00 | 20,294,803.00 | 5,528,224.00 | 72.00 | 4.20× |
| `Map.find` | find-missing | 1,000 | 1,704,552.00 | 370,453.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.find` | find-missing | 10,000 | 17,031,801.00 | 3,700,047.00 | 1,104,912.00 | 72.00 | 4.60× |
| `Map.find` | find-missing | 100,000 | 170,277,593.00 | 40,524,835.00 | 11,059,840.00 | 72.00 | 4.20× |
| `Map.foldLeft` | foldLeft | 1,000 | 1,696,555.00 | 388,927.00 | 110,776.00 | 72.00 | 4.36× |
| `Map.foldLeft` | foldLeft | 10,000 | 16,951,804.00 | 3,884,523.00 | 1,104,912.00 | 72.00 | 4.36× |
| `Map.foldLeft` | foldLeft | 100,000 | 169,477,596.00 | 42,370,980.00 | 11,059,840.00 | 72.00 | 4.00× |
| `Map.foldRight` | foldRight | 1,000 | 1,677,742.00 | 396,827.00 | 110,776.00 | 72.00 | 4.23× |
| `Map.foldRight` | foldRight | 10,000 | 16,768,200.00 | 3,963,521.00 | 1,104,912.00 | 72.00 | 4.23× |
| `Map.foldRight` | foldRight | 100,000 | 167,556,774.00 | 43,161,296.00 | 11,059,840.00 | 72.00 | 3.88× |
| `Map.forEach` | forEach | 1,000 | 1,821,462.00 | 547,990.00 | 110,776.00 | 112.00 | 3.32× |
| `Map.forEach` | forEach | 10,000 | 18,201,711.00 | 5,474,586.00 | 1,104,912.00 | 112.00 | 3.32× |
| `Map.forEach` | forEach | 100,000 | 181,977,503.00 | 61,871,056.00 | 11,059,840.00 | 112.00 | 2.94× |
| `Map.get` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 95.00 | 0.00 | 2.01× |
| `Map.get` | get-hit | 10,000 | 6,235.03 | 3,080.44 | 95.00 | 0.00 | 2.02× |
| `Map.get` | get-hit | 100,000 | 7,700.16 | 3,877.41 | 123.00 | 0.00 | 1.99× |
| `Map.get` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 96.00 | 0.00 | 2.01× |
| `Map.get` | get-miss | 10,000 | 6,471.53 | 3,183.72 | 96.00 | 0.00 | 2.03× |
| `Map.get` | get-miss | 100,000 | 8,177.69 | 3,986.66 | 128.00 | 0.00 | 2.05× |
| `Map.getEntry` | getEntry-hit | 1,000 | 5,290.91 | 2,536.59 | 135.00 | 0.00 | 2.09× |
| `Map.getEntry` | getEntry-hit | 10,000 | 6,407.03 | 3,065.44 | 135.00 | 0.00 | 2.09× |
| `Map.getEntry` | getEntry-hit | 100,000 | 7,872.16 | 3,862.41 | 163.00 | 0.00 | 2.04× |
| `Map.insert` | insert-mixed | 1,000 | 7,150.06 | 3,649.56 | 214.00 | 40.00 | 1.96× |
| `Map.insert` | insert-mixed | 10,000 | 8,927.03 | 4,686.22 | 244.00 | 63.00 | 1.90× |
| `Map.insert` | insert-mixed | 100,000 | 10,794.69 | 4,942.53 | 304.00 | 40.00 | 2.18× |
| `Map.isEmpty` | isEmpty | 1,000 | 267.09 | 267.09 | 0.00 | 0.00 | 1.00× |
| `Map.isEmpty` | isEmpty | 10,000 | 267.59 | 267.09 | 0.00 | 0.00 | 1.00× |
| `Map.isEmpty` | isEmpty | 100,000 | 267.59 | 266.09 | 0.00 | 0.00 | 1.01× |
| `Map.map` | map | 1,000 | 621,705.00 | 600,904.00 | 66,104.00 | 59,328.00 | 1.03× |
| `Map.map` | map | 10,000 | 6,270,601.00 | 6,000,018.00 | 665,536.00 | 591,184.00 | 1.05× |
| `Map.map` | map | 100,000 | 60,103,065.00 | 76,139,742.00 | 6,441,152.00 | 5,842,432.00 | 0.79× |
| `Map.maxEntry` | maxEntry | 1,000 | 5,108.09 | 1,451.59 | 544.00 | 0.00 | 3.52× |
| `Map.maxEntry` | maxEntry | 10,000 | 5,107.59 | 1,452.09 | 544.00 | 0.00 | 3.52× |
| `Map.maxEntry` | maxEntry | 100,000 | 5,969.09 | 1,873.59 | 624.00 | 0.00 | 3.19× |
| `Map.minEntry` | minEntry | 1,000 | 4,641.09 | 1,405.59 | 544.00 | 0.00 | 3.30× |
| `Map.minEntry` | minEntry | 10,000 | 4,641.09 | 1,406.09 | 544.00 | 0.00 | 3.30× |
| `Map.minEntry` | minEntry | 100,000 | 5,296.59 | 1,827.59 | 624.00 | 0.00 | 2.90× |
| `Map.remove` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 357.75 | 0.00 | 2.69× |
| `Map.remove` | remove-hit | 10,000 | 11,262.97 | 6,420.53 | 360.25 | 0.00 | 1.75× |
| `Map.remove` | remove-hit | 100,000 | 14,059.88 | 7,769.31 | 520.25 | 0.00 | 1.81× |
| `Map.remove` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 320.00 | 0.00 | 2.41× |
| `Map.remove` | remove-miss | 10,000 | 8,014.88 | 5,414.22 | 320.00 | 0.00 | 1.48× |
| `Map.remove` | remove-miss | 100,000 | 10,381.16 | 6,881.47 | 464.00 | 0.00 | 1.51× |
| `Map.replace` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 325.00 | 40.00 | 3.85× |
| `Map.replace` | replace-hit | 10,000 | 13,003.06 | 3,337.44 | 325.00 | 40.00 | 3.90× |
| `Map.replace` | replace-hit | 100,000 | 16,024.56 | 4,148.91 | 409.00 | 40.00 | 3.86× |
| `Map.replace` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 96.00 | 0.00 | 2.01× |
| `Map.replace` | replace-miss | 10,000 | 6,571.53 | 3,230.72 | 96.00 | 0.00 | 2.03× |
| `Map.replace` | replace-miss | 100,000 | 8,277.69 | 4,033.66 | 128.00 | 0.00 | 2.05× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,677,786.00 | 841,552.00 | 110,776.00 | 352.00 | 1.99× |
| `Map.reverseEntries` | reverseEntries-consume | 10,000 | 16,768,244.00 | 8,404,549.00 | 1,104,912.00 | 352.00 | 2.00× |
| `Map.reverseEntries` | reverseEntries-consume | 100,000 | 167,556,818.00 | 94,416,057.00 | 11,059,840.00 | 352.00 | 1.77× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 3,661.38 | 1,848.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntries` | reverseEntries-create | 10,000 | 3,663.38 | 1,850.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntries` | reverseEntries-create | 100,000 | 4,573.75 | 1,890.75 | 512.00 | 352.00 | 2.42× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 1,000 | 34,323.25 | 24,613.62 | 2,258.00 | 1,032.00 | 1.39× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 10,000 | 35,910.00 | 27,235.38 | 2,306.00 | 1,227.00 | 1.32× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 100,000 | 38,254.00 | 30,717.75 | 2,376.00 | 1,472.00 | 1.25× |
| `Map.size` | size | 1,000 | 253.09 | 253.09 | 0.00 | 0.00 | 1.00× |
| `Map.size` | size | 10,000 | 253.59 | 253.09 | 0.00 | 0.00 | 1.00× |
| `Map.size` | size | 100,000 | 253.59 | 252.09 | 0.00 | 0.00 | 1.01× |
| `Map.swap` | swap-hit | 1,000 | 5,856.56 | 3,107.09 | 230.00 | 40.00 | 1.88× |
| `Map.swap` | swap-hit | 10,000 | 6,977.69 | 4,149.25 | 230.00 | 63.00 | 1.68× |
| `Map.swap` | swap-hit | 100,000 | 8,585.06 | 4,576.41 | 286.00 | 40.00 | 1.88× |
| `Map.take` | take-hit | 1,000 | 10,270.19 | 3,891.62 | 357.75 | 0.00 | 2.64× |
| `Map.take` | take-hit | 10,000 | 11,295.97 | 6,504.53 | 360.25 | 0.00 | 1.74× |
| `Map.take` | take-hit | 100,000 | 14,092.88 | 7,853.81 | 520.25 | 0.00 | 1.79× |
| `Map.take` | take-miss | 1,000 | 6,923.62 | 2,929.78 | 320.00 | 0.00 | 2.36× |
| `Map.take` | take-miss | 10,000 | 8,053.88 | 5,488.22 | 320.00 | 0.00 | 1.47× |
| `Map.take` | take-miss | 100,000 | 10,420.16 | 6,955.97 | 464.00 | 0.00 | 1.50× |
| `Map.toArray` | toArray | 1,000 | 2,180,442.00 | 819,710.00 | 182,992.00 | 8,416.00 | 2.66× |
| `Map.toArray` | toArray | 10,000 | 21,782,195.00 | 8,187,172.00 | 1,825,128.00 | 80,416.00 | 2.66× |
| `Map.toArray` | toArray | 100,000 | 217,778,205.00 | 92,236,670.00 | 18,260,056.00 | 800,416.00 | 2.36× |
| `Map.toVarArray` | toVarArray | 1,000 | 2,339,758.00 | 819,710.00 | 191,016.00 | 8,416.00 | 2.85× |
| `Map.toVarArray` | toVarArray | 10,000 | 23,372,543.00 | 8,187,156.00 | 1,905,152.00 | 80,416.00 | 2.85× |
| `Map.toVarArray` | toVarArray | 100,000 | 233,678,905.00 | 92,236,638.00 | 19,060,080.00 | 800,416.00 | 2.53× |

### Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 3,337.81 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-insert | 10,000 | 10,115.12 | 5,153.06 | 4,182.72 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-insert | 100,000 | 12,818.28 | 5,499.44 | 5,046.28 | 324.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 2,307.03 | 230.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 10,000 | 6,920.69 | 4,066.25 | 3,136.88 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-overwrite | 100,000 | 8,528.06 | 4,492.91 | 3,439.84 | 286.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 1,835.03 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 6,235.03 | 3,080.44 | 2,151.06 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 7,700.16 | 3,877.41 | 2,755.84 | 123.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 1,899.53 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 6,471.53 | 3,183.72 | 2,213.38 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 8,177.69 | 3,986.66 | 2,834.34 | 128.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 3,090.56 | 357.75 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 10,000 | 11,262.97 | 6,420.53 | 5,494.69 | 360.25 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 100,000 | 14,059.88 | 7,769.31 | 8,884.69 | 520.25 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 2,096.47 | 320.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 10,000 | 8,014.88 | 5,414.22 | 4,445.62 | 320.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 100,000 | 10,381.16 | 6,881.47 | 7,262.44 | 464.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 2,090.03 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-hit | 10,000 | 13,003.06 | 3,337.44 | 2,408.06 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-hit | 100,000 | 16,024.56 | 4,148.91 | 3,138.34 | 409.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 1,946.53 | 96.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 10,000 | 6,571.53 | 3,230.72 | 2,260.38 | 96.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 100,000 | 8,277.69 | 4,033.66 | 2,881.34 | 128.00 | 0.00 | 0.00 |

### Core baseline details

Explicit adapters are used where Core has no matching public API. All direct baselines use mo:core/Map 2.5.0; find/getEntry use the listed small public API adapters.

| Workload | Core baseline | Note |
| --- | --- | --- |
| find-first | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-last | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-middle | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-missing | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| getEntry-hit | `get + optional pair` | Core.get mapped to the requested key; exact Nat64 key ordering makes keys equivalent. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](benchmarks/results/mutable-map/final/summary.csv).

</details>

## Persistent map costs

The complete matrix below covers **111 workloads** at **1,000, 10,000, and
100,000 entries**: 37 variants per size across 27 generic public functions and
three scalar helpers. Each reported count is the median of three identical trials.

The [second optimization round](benchmarks/results/optimization-round-2/pure-map/README.md)
refreshed 30 workloads: `get-hit/miss`, `getEntry-hit`, `containsKey-mixed`, all
construction rows, `add-overwrite`, `find-missing`, and `foldLeft` at each size.
These rows use compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f` and include
207 measurements per version. The remaining 81 workloads retain the
[previous full comparison](benchmarks/results/optimization-round/pure-map/README.md),
measured with compiler `f1ccbba5e445df9db03bbc35be557187ade9b436`.
Its [compiler audit](benchmarks/results/optimization-round/integrated/pure-map/audit.md)
confirms unchanged benchmark function bodies under `c320bf90d`; it adds no new
measurements. The original full run validated all 720 measurements.

The baseline is `core 2.5.0` pure Map. Keys are boxed `Nat64` values, with
the same input order for both implementations. The plugin callback path uses
the same ordinary Motoko comparator as Core; scalar ordering is shown separately.
Input setup is outside timing, and construction is measured separately from
operations on populated maps. Sorted input arrives in ascending key order;
shuffled input contains the same entries in a deterministic randomized order.
The plugin builds directly from sorted input, avoiding the sorting step needed
for shuffled input. `add` is put; `swap` also returns the previous
value. `find` is tested at the first, middle, last, and absent positions.
The iterator-related APIs tested are `fromIter`, `entriesFrom`, and the other names
shown below; there is no public `findIter` function.

This round reduces callback lookup instructions by 2.5–3.1%, scalar Nat64 lookup
by 4.7–5.7%, and shuffled construction by 3.4–4.5%, with allocation unchanged.
At 100,000 entries, shuffled `fromIter` now uses 2.34% fewer instructions and
65.9% fewer allocated bytes than Core. It still uses 3.38% more instructions at
1,000 entries and 2.92% more at 10,000. Core also uses fewer instructions for
cursor creation alone and full-map snapshot creation.

Both folds use fewer instructions than Core and allocate zero bytes. The prior
wrapper optimization reduced fold instructions by about 32% and full iterator
consumption by about 8.4%; bounded seek-and-consume workloads also improved.
Both libraries share unchanged branches. Plugin updates copy changed paths and
retain payload references; separate GC tests verify that updating a map with a
1 MiB payload allocates the same amount as with a 5-byte payload.
Core adapters are identified below where it lacks a matching public operation;
these compare complete algorithms and capabilities.

PocketIC 14 runs use fresh canisters and four forced GC increments before each
phase. Synchronous reclamation is reported separately; none occurred in these
measurements. End-of-message GC is outside the measured interval.

Three-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, split, and construction rows measure the complete function call. Snapshot creation is per captured root/snapshot. Core adapters are listed below; see [methodology](benchmarks/results/optimization-round/pure-map/README.md) for exact semantics and validation.

### Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 7,606,083.00 | 6,788,543.00 | 1,395,104.00 | 463,216.00 | 1.12× |
| `Map.fromArray` | fromArray-shuffled | 10,000 | 102,601,814.00 | 93,269,585.00 | 18,838,600.00 | 6,369,896.00 | 1.10× |
| `Map.fromArray` | fromArray-shuffled | 100,000 | 1,233,077,190.00 | 1,089,625,017.00 | 224,253,736.00 | 73,573,936.00 | 1.13× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 7,605,488.00 | 7,862,332.00 | 1,394,952.00 | 487,880.00 | 0.97× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 102,601,219.00 | 105,596,698.00 | 18,838,448.00 | 6,712,416.00 | 0.97× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,233,076,595.00 | 1,204,273,073.00 | 224,253,584.00 | 76,471,536.00 | 1.02× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 10,203,874.00 | 1,727,096.00 | 1,831,072.00 | 96,688.00 | 5.91× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 135,473,401.00 | 18,857,900.00 | 23,988,728.00 | 1,062,544.00 | 7.18× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 1,694,931,186.00 | 179,953,531.00 | 297,345,304.00 | 10,097,624.00 | 9.42× |

### Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 1,840.50 | 850.50 | 1.51× |
| `Map.add` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 2,034.50 | 1,107.00 | 1.35× |
| `Map.add` | add-insert | 100,000 | 14,112.34 | 10,148.47 | 2,524.25 | 1,289.25 | 1.39× |
| `Map.add` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 1,395.50 | 677.25 | 2.16× |
| `Map.add` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 1,816.75 | 913.50 | 2.10× |
| `Map.add` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 2,230.50 | 1,143.00 | 2.11× |
| `Map.alter` | alter-mixed | 1,000 | 11,258.12 | 5,561.62 | 1,647.00 | 822.75 | 2.02× |
| `Map.alter` | alter-mixed | 10,000 | 13,678.84 | 7,205.69 | 1,944.00 | 1,077.00 | 1.90× |
| `Map.alter` | alter-mixed | 100,000 | 16,945.25 | 8,521.84 | 2,422.75 | 1,281.75 | 1.99× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 2,183.69 | 1,644.38 | 0.00 | 0.00 | 1.33× |
| `Map.containsKey` | containsKey-mixed | 10,000 | 2,831.84 | 2,187.19 | 0.00 | 0.00 | 1.29× |
| `Map.containsKey` | containsKey-mixed | 100,000 | 3,450.09 | 2,581.88 | 0.00 | 0.00 | 1.34× |
| `Map.delete` | delete-mixed | 1,000 | 10,437.75 | 4,015.50 | 1,987.75 | 357.50 | 2.60× |
| `Map.delete` | delete-mixed | 10,000 | 14,751.44 | 5,245.69 | 2,885.00 | 467.75 | 2.81× |
| `Map.delete` | delete-mixed | 100,000 | 17,230.59 | 6,426.88 | 3,373.00 | 596.00 | 2.68× |
| `Map.entries` | entries-consume | 1,000 | 1,608,622.00 | 1,134,244.00 | 256,176.00 | 40,400.00 | 1.42× |
| `Map.entries` | entries-consume | 10,000 | 16,219,373.00 | 11,320,184.00 | 2,560,176.00 | 400,432.00 | 1.43× |
| `Map.entries` | entries-consume | 100,000 | 161,456,649.00 | 113,128,799.00 | 25,600,176.00 | 4,000,464.00 | 1.43× |
| `Map.entries` | entries-create | 1,000 | 1,072.38 | 2,363.38 | 176.00 | 400.00 | 0.45× |
| `Map.entries` | entries-create | 10,000 | 1,072.38 | 2,427.38 | 176.00 | 432.00 | 0.44× |
| `Map.entries` | entries-create | 100,000 | 1,108.75 | 2,519.75 | 176.00 | 464.00 | 0.44× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 794,041.00 | 25,771.38 | 131,432.00 | 1,072.00 | 30.81× |
| `Map.entriesFrom` | entriesFrom-seek16 | 10,000 | 7,819,157.12 | 27,718.00 | 1,283,656.00 | 1,104.00 | 282.10× |
| `Map.entriesFrom` | entriesFrom-seek16 | 100,000 | 77,630,138.25 | 28,683.00 | 12,804,424.00 | 1,136.00 | 2706.49× |
| `Map.entriesInRange` | entriesInRange-seek16 | 1,000 | 798,511.00 | 27,276.12 | 131,584.00 | 1,040.00 | 29.28× |
| `Map.entriesInRange` | entriesInRange-seek16 | 10,000 | 7,823,627.12 | 30,075.38 | 1,283,808.00 | 1,072.00 | 260.13× |
| `Map.entriesInRange` | entriesInRange-seek16 | 100,000 | 77,634,608.25 | 31,463.75 | 12,804,576.00 | 1,104.00 | 2467.43× |
| `Map.filterMap` | filterMap | 1,000 | 4,885,562.00 | 746,683.00 | 829,640.00 | 68,904.00 | 6.54× |
| `Map.filterMap` | filterMap | 10,000 | 65,605,684.00 | 7,101,817.00 | 11,134,592.00 | 614,448.00 | 9.24× |
| `Map.filterMap` | filterMap | 100,000 | 825,830,263.00 | 75,473,263.00 | 140,072,896.00 | 7,070,760.00 | 10.94× |
| `Map.find` | find-first | 1,000 | 11,292.00 | 1,927.00 | 2,224.00 | 112.00 | 5.86× |
| `Map.find` | find-first | 10,000 | 21,897.00 | 2,253.00 | 4,528.00 | 112.00 | 9.72× |
| `Map.find` | find-first | 100,000 | 24,253.00 | 2,645.00 | 5,040.00 | 112.00 | 9.17× |
| `Map.find` | find-last | 1,000 | 1,616,489.00 | 329,393.00 | 256,176.00 | 112.00 | 4.91× |
| `Map.find` | find-last | 10,000 | 16,299,240.00 | 3,288,081.00 | 2,560,176.00 | 112.00 | 4.96× |
| `Map.find` | find-last | 100,000 | 162,256,516.00 | 32,805,905.00 | 25,600,176.00 | 112.00 | 4.95× |
| `Map.find` | find-middle | 1,000 | 817,769.00 | 166,211.00 | 129,968.00 | 112.00 | 4.92× |
| `Map.find` | find-middle | 10,000 | 8,159,271.00 | 1,648,899.00 | 1,281,200.00 | 112.00 | 4.95× |
| `Map.find` | find-middle | 100,000 | 81,141,704.00 | 16,407,115.00 | 12,802,224.00 | 112.00 | 4.95× |
| `Map.find` | find-missing | 1,000 | 1,616,602.00 | 329,278.00 | 256,176.00 | 72.00 | 4.91× |
| `Map.find` | find-missing | 10,000 | 16,299,353.00 | 3,287,966.00 | 2,560,176.00 | 72.00 | 4.96× |
| `Map.find` | find-missing | 100,000 | 162,256,629.00 | 32,805,790.00 | 25,600,176.00 | 72.00 | 4.95× |
| `Map.foldLeft` | foldLeft | 1,000 | 315,007.00 | 312,965.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldLeft` | foldLeft | 10,000 | 3,204,063.00 | 3,127,653.00 | 0.00 | 0.00 | 1.02× |
| `Map.foldLeft` | foldLeft | 100,000 | 31,665,567.00 | 31,205,477.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldRight` | foldRight | 1,000 | 315,007.00 | 312,965.00 | 0.00 | 0.00 | 1.01× |
| `Map.foldRight` | foldRight | 10,000 | 3,204,063.00 | 3,127,653.00 | 0.00 | 0.00 | 1.02× |
| `Map.foldRight` | foldRight | 100,000 | 31,665,567.00 | 31,205,477.00 | 0.00 | 0.00 | 1.01× |
| `Map.get` | get-hit | 1,000 | 2,041.19 | 1,604.38 | 0.00 | 0.00 | 1.27× |
| `Map.get` | get-hit | 10,000 | 2,736.97 | 2,129.44 | 0.00 | 0.00 | 1.29× |
| `Map.get` | get-hit | 100,000 | 3,324.09 | 2,524.38 | 0.00 | 0.00 | 1.32× |
| `Map.get` | get-miss | 1,000 | 2,237.69 | 1,710.88 | 0.00 | 0.00 | 1.31× |
| `Map.get` | get-miss | 10,000 | 2,942.59 | 2,248.19 | 0.00 | 0.00 | 1.31× |
| `Map.get` | get-miss | 100,000 | 3,518.72 | 2,649.88 | 0.00 | 0.00 | 1.33× |
| `Map.getEntry` | getEntry-hit | 1,000 | 2,213.19 | 1,742.38 | 40.00 | 40.00 | 1.27× |
| `Map.getEntry` | getEntry-hit | 10,000 | 2,908.97 | 2,267.44 | 40.00 | 40.00 | 1.28× |
| `Map.getEntry` | getEntry-hit | 100,000 | 3,496.09 | 2,662.38 | 40.00 | 40.00 | 1.31× |
| `Map.insert` | insert-mixed | 1,000 | 9,122.19 | 5,332.62 | 1,607.00 | 782.75 | 1.71× |
| `Map.insert` | insert-mixed | 10,000 | 11,000.25 | 6,976.69 | 1,904.00 | 1,037.00 | 1.58× |
| `Map.insert` | insert-mixed | 100,000 | 13,585.41 | 8,292.34 | 2,382.75 | 1,241.75 | 1.64× |
| `Map.map` | map | 1,000 | 629,222.00 | 504,947.00 | 88,112.00 | 72,072.00 | 1.25× |
| `Map.map` | map | 10,000 | 6,340,550.00 | 5,043,811.00 | 880,112.00 | 720,072.00 | 1.26× |
| `Map.map` | map | 100,000 | 63,111,408.00 | 50,442,421.00 | 8,800,112.00 | 7,200,072.00 | 1.25× |
| `Map.rank` | rank | 1,000 | 743,056.50 | 1,906.12 | 129,264.00 | 40.00 | 389.83× |
| `Map.rank` | rank | 10,000 | 7,449,898.00 | 2,962.38 | 1,281,776.00 | 40.00 | 2514.84× |
| `Map.rank` | rank | 100,000 | 74,044,883.88 | 3,350.88 | 12,802,192.00 | 40.00 | 22097.18× |
| `Map.replace` | replace-hit | 1,000 | 9,848.69 | 3,851.75 | 1,355.50 | 677.25 | 2.56× |
| `Map.replace` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 1,776.75 | 913.50 | 2.52× |
| `Map.replace` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 2,190.50 | 1,143.00 | 2.56× |
| `Map.replace` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 0.00 | 0.00 | 1.16× |
| `Map.replace` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 0.00 | 0.00 | 1.17× |
| `Map.replace` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 0.00 | 0.00 | 1.18× |
| `Map.replay` | replay-consume | 1,000 | 1,608,622.00 | 1,134,024.00 | 256,176.00 | 40,344.00 | 1.42× |
| `Map.replay` | replay-consume | 10,000 | 16,219,373.00 | 11,319,964.00 | 2,560,176.00 | 400,376.00 | 1.43× |
| `Map.replay` | replay-consume | 100,000 | 161,456,649.00 | 113,128,579.00 | 25,600,176.00 | 4,000,408.00 | 1.43× |
| `Map.replay` | replay-create | 1,000 | 1,072.38 | 2,143.38 | 176.00 | 344.00 | 0.50× |
| `Map.replay` | replay-create | 10,000 | 1,072.38 | 2,207.38 | 176.00 | 376.00 | 0.49× |
| `Map.replay` | replay-create | 100,000 | 1,108.75 | 2,299.75 | 176.00 | 408.00 | 0.48× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,608,628.00 | 1,134,352.00 | 256,176.00 | 40,400.00 | 1.42× |
| `Map.reverseEntries` | reverseEntries-consume | 10,000 | 16,219,379.00 | 11,320,292.00 | 2,560,176.00 | 400,432.00 | 1.43× |
| `Map.reverseEntries` | reverseEntries-consume | 100,000 | 161,456,655.00 | 113,128,907.00 | 25,600,176.00 | 4,000,464.00 | 1.43× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 1,078.38 | 2,471.38 | 176.00 | 400.00 | 0.44× |
| `Map.reverseEntries` | reverseEntries-create | 10,000 | 1,078.38 | 2,535.38 | 176.00 | 432.00 | 0.43× |
| `Map.reverseEntries` | reverseEntries-create | 100,000 | 1,114.75 | 2,627.75 | 176.00 | 464.00 | 0.42× |
| `Map.select` | select | 1,000 | 753,479.12 | 1,069.38 | 129,264.00 | 40.00 | 704.60× |
| `Map.select` | select | 10,000 | 7,554,302.62 | 1,481.62 | 1,281,776.00 | 40.00 | 5098.66× |
| `Map.select` | select | 100,000 | 75,094,764.50 | 1,702.38 | 12,802,192.00 | 40.00 | 44111.76× |
| `Map.snapshot` | snapshot-create | 1,000 | 229.38 | 443.38 | 0.00 | 56.00 | 0.52× |
| `Map.snapshot` | snapshot-create | 10,000 | 229.38 | 443.38 | 0.00 | 56.00 | 0.52× |
| `Map.snapshot` | snapshot-create | 100,000 | 267.75 | 479.75 | 0.00 | 56.00 | 0.56× |
| `Map.splitLookup` | splitLookup | 1,000 | 11,357,872.75 | 7,113.75 | 2,084,524.00 | 898.00 | 1596.61× |
| `Map.splitLookup` | splitLookup | 10,000 | 147,468,978.00 | 10,385.75 | 26,562,892.00 | 1,420.00 | 14199.17× |
| `Map.splitLookup` | splitLookup | 100,000 | 1,826,728,244.33 | 14,913.33 | 325,209,429.33 | 1,496.00 | 122489.60× |
| `Map.swap` | swap-hit | 1,000 | 8,044.25 | 4,016.75 | 1,355.50 | 717.25 | 2.00× |
| `Map.swap` | swap-hit | 10,000 | 10,408.78 | 5,236.44 | 1,776.75 | 953.50 | 1.99× |
| `Map.swap` | swap-hit | 100,000 | 12,734.72 | 6,317.84 | 2,190.50 | 1,183.00 | 2.02× |
| `Map.take` | take-hit | 1,000 | 10,700.91 | 5,910.31 | 2,060.75 | 717.25 | 1.81× |
| `Map.take` | take-hit | 10,000 | 15,427.75 | 7,725.25 | 3,014.00 | 931.00 | 2.00× |
| `Map.take` | take-hit | 100,000 | 17,354.00 | 9,607.38 | 3,402.50 | 1,187.50 | 1.81× |
| `Map.update` | update-mixed | 1,000 | 11,186.12 | 5,514.62 | 1,607.00 | 782.75 | 2.03× |
| `Map.update` | update-mixed | 10,000 | 13,606.84 | 7,158.69 | 1,904.00 | 1,037.00 | 1.90× |
| `Map.update` | update-mixed | 100,000 | 16,873.25 | 8,474.84 | 2,382.75 | 1,241.75 | 1.99× |

### Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 5,824.16 | 1,840.50 | 850.50 | 850.50 |
| `Map.addNat64` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 7,575.50 | 2,034.50 | 1,107.00 | 1,107.00 |
| `Map.addNat64` | add-insert | 100,000 | 14,112.34 | 10,148.47 | 8,919.41 | 2,524.25 | 1,289.25 | 1,289.25 |
| `Map.addNat64` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 3,052.16 | 1,395.50 | 677.25 | 677.25 |
| `Map.addNat64` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 4,031.53 | 1,816.75 | 913.50 | 913.50 |
| `Map.addNat64` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 4,876.94 | 2,230.50 | 1,143.00 | 1,143.00 |
| `Map.getNat64` | get-hit | 1,000 | 2,041.19 | 1,604.38 | 891.78 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 2,736.97 | 2,129.44 | 1,174.53 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 3,324.09 | 2,524.38 | 1,345.19 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 2,237.69 | 1,710.88 | 955.53 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 2,942.59 | 2,248.19 | 1,248.75 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 3,518.72 | 2,649.88 | 1,420.81 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 9,848.69 | 3,851.75 | 3,139.16 | 1,355.50 | 677.25 | 677.25 |
| `Map.replaceNat64` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 4,118.53 | 1,776.75 | 913.50 | 913.50 |
| `Map.replaceNat64` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 4,964.44 | 2,190.50 | 1,143.00 | 1,143.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 1,423.59 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 1,776.44 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 2,008.06 | 0.00 | 0.00 | 0.00 |

### Core baseline details

Explicit adapters are used where Core has no matching public API. Seek, rank, selection, and split differences include additional plugin algorithms and subtree metadata, not just plugin boundary overhead.

| Workload | Core baseline | Note |
| --- | --- | --- |
| alter-mixed | `get + callback + add/remove` | Core has no alter: call callback once after get, then add/remove; unchanged absence keeps the original root. |
| entriesFrom-seek16 | `entries + Iter.dropWhile` | Core has no seek: ordered iterator scans the prefix, then both consume 16 entries. |
| entriesInRange-seek16 | `entries + Iter.dropWhile + Iter.takeWhile` | Core has no bounded seek: scan to lower bound and stop at upper bound; both consume 16 entries. |
| find-first | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-last | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-middle | `Iter.find(entries)` | Ordered scan adapter; predicate matches all keys at or above the threshold. |
| find-missing | `Iter.find(entries)` | Ordered scan adapter; threshold lies above every key. |
| fromArray-shuffled | `fromIter(array.values())` | Core has no fromArray; array iterator creation is included in its adapter. |
| getEntry-hit | `get + optional pair` | Core.get mapped to the requested key; equivalent for exact Nat64 ordering. |
| rank | `ordered entries count` | Core lacks subtree counts; scan ordered entries until the probe key. |
| replay-consume | `entries(retained root)` | Full snapshots are prepared before timing; both create an iterator and consume it completely. |
| replay-create | `entries(retained root)` | Full snapshots are prepared before timing; Core replays a retained root with entries. |
| select | `entries + index scan` | Core lacks rank selection; consume the ordered iterator to the requested index. |
| snapshot-create | `retain persistent map root` | Full-map snapshot only: Core root capture is already persistent; plugin snapshot additionally stores rank/range metadata. |
| splitLookup | `entries + add into two maps` | Core has no split: one ordered pass reconstructs left/right maps with public add; plugin shares untouched branches. |
| swap-hit | `swap` | Both return the old optional value; this is put-with-old-value semantics. |
| update-mixed | `get + callback + add/remove` | Same adapter as alter, returning the original optional value. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in the
[round 2 CSV](benchmarks/results/optimization-round-2/pure-map/functions/after.csv)
and the [prior full CSV](benchmarks/results/optimization-round/pure-map/functions/after.csv)
for rows not remeasured this round.

The [new before/after tables](benchmarks/results/optimization-round-2/pure-map/functions/costs.md),
[validation record](benchmarks/results/optimization-round-2/pure-map/functions/validation.json),
and [independent audit](benchmarks/results/optimization-round-2/pure-map/audit.md)
provide the current changes, including empty and small lookup checks. The
[prior full comparison](benchmarks/results/optimization-round/pure-map/functions/costs.md)
retains every original measurement, including losses.
The [updated point](benchmarks/results/optimization-round/pure-map/point/costs.md)
and [bulk tables](benchmarks/results/optimization-round/pure-map/bulk/costs.md)
also cover `remove`, retained histories, and set operations. Intersecting a
256-entry map with a small map remains a weak case: **57,509 instructions /
6,016 allocated bytes** for the Core adapter versus **80,690 / 12,184** for
the plugin. The [earlier report](benchmarks/results/pure-map/README.md) remains
available as historical evidence.

## Plugins

| Plugin | Function | Description |
| --- | --- | --- |
| [CandidX](plugins/candidx/) | `Prim.to_candid_canonical(...) : { #ok : Blob; #err : Text }` | Canonical Candid encoding from typed Motoko values |
| [CBOR](plugins/cbor/) | `Prim.to_cbor(value)`, `Prim.from_cbor<T>(bytes)` | Deterministic CBOR encoding and typed decoding with `#ok`/`#err` results |
| [JSON](plugins/json/) | `Prim.to_json(value)`, `Prim.from_json<T>(text)` | Typed JSON encoding/decoding with `#ok`/`#err` results |
| [Mutable map](plugins/mutable-map/) | `Map.get`, `Map.add`, `Map.remove`, `Prim.mmap_*` | In-place ordered maps with generic keys/values, shared payloads, and managed GC writes |
| [Pure map](plugins/pure-map/) | `Map.get`, `Map.add`, `Map.remove`, `Prim.pmap_*` | Persistent ordered maps with generic keys/values, Motoko callbacks, and native scalar comparisons |
| [SHA-256](plugins/sha256/) | `Prim.sha256(Blob) : Blob` | One-shot SHA-256 with direct Blob access |

The compiler support is proposed in
[Motoko PR #6443](https://github.com/caffeinelabs/motoko/pull/6443).
This repository is independent of the compiler checkout. It is not a submodule.

## Build and use

Use a compiler checkout with the plugin API; the tested revision is recorded in
[`toolchains/motoko.json`](toolchains/motoko.json). Enter that checkout's Nix
development shell. With this repository at `../plugins`:

```sh
cd /path/to/motoko
nix develop
make -C rts
../plugins/scripts/build.sh --motoko "$PWD"
bin/moc --plugin ../plugins/dist/candidx \
        --plugin ../plugins/dist/sha256 \
        --plugin ../plugins/dist/json \
        --plugin ../plugins/dist/cbor \
        --plugin ../plugins/dist/pure-map \
        --package pure-map ../plugins/plugins/pure-map/motoko \
        --plugin ../plugins/dist/mutable-map \
        --package mutable-map ../plugins/plugins/mutable-map/motoko \
        app.mo -o app.wasm
```

```motoko
import Prim "mo:⛔";
import Map "mo:pure-map/Map";
import MutableMap "mo:mutable-map/Map";

switch (Prim.to_candid_canonical({ value = 42 })) {
  case (#ok bytes) { let digest = Prim.sha256(bytes) };
  case (#err message) { Prim.debugPrint(message) };
};
type User = { name : Text; age : Nat8 };
let user = Prim.from_json<User>("{\"name\":\"Ada\",\"age\":37}");
let binary = Prim.to_cbor({ name = "Ada"; age = 37 : Nat8 });
let key : Nat64 = 42;
let original = Map.empty<Nat64, Text>();
let updated = Map.addNat64(original, key, "answer");
assert Map.getNat64(updated, key) == ?"answer";
let mutable = MutableMap.empty<Nat64, Text>();
MutableMap.addNat64(mutable, key, "answer");
assert MutableMap.getNat64(mutable, key) == ?"answer";
```

The build creates a matching dynamically linked native compiler and independent
packages in `dist/<name>/`, each containing `plugin.cmxs`. Kernel-based packages
also contain `runtime.wasm`; both map packages emit managed Wasm directly.
To build selected plugins, append their names:

```sh
../plugins/scripts/build.sh --motoko "$PWD" sha256
```

Prebuilt packages load with `--plugin` without rebuilding the compiler. Native
compiler modules must match the compiler interfaces, OCaml toolchain, and host
platform; incompatible packages produce an unsupported-plugin error. Rebuild
packages when changing the compiler. The development SDK uses ABI 1; all plugin
functions use the same specialization mechanism and can return managed Motoko
values. Static Linux/musl and JavaScript compiler builds cannot load native
`.cmxs` files.

## Repository layout

```text
plugins/
  candidx/
    plugin.json       package and build metadata
    compiler/         registration, code generator, interpreter reference
    runtime/          Rust crate compiled to Wasm
    tests/            plugin-specific Motoko tests and fuzz adapter
  json/
    ...
  cbor/
    ...
  pure-map/
    compiler/         generated managed Wasm and interpreter reference
    motoko/           public Map library
    tests/            differential, sharing, and GC checks
  mutable-map/
    compiler/         native B-tree operations and interpreter reference
    motoko/           public Map library and optional Core conversion module
    tests/            differential, aliasing, GC, and upgrade checks
  sha256/
    ...
scripts/              shared build and test commands
tests/integration/    tests combining plugins and exercising GC
benchmarks/           PocketIC harness and recorded results
docs/                 architecture and authoring guide
toolchains/           compiler revision used by CI
dist/                 generated loadable packages (ignored)
_build/               generated intermediates (ignored)
```

Each plugin owns its implementation and tests. Shared tools discover plugin
manifests so adding another plugin does not require a new build script. See
[adding a plugin](docs/adding-a-plugin.md).

## Validation and performance

From the Motoko checkout's Nix shell:

```sh
../plugins/scripts/test.sh --motoko "$PWD"
```

The suite exercises source and IR interpretation, compiled Wasm, diagnostics,
package loading, native kernels, and GC behavior. The
[benchmark guide](benchmarks/README.md) covers PocketIC instruction counts and
the CandidX repository's conformance and fuzz tests.

The [managed-mutation SDK audit](docs/audits/managed-mutation-sdk/README.md)
records independent tests across four execution engines and mutation during
incremental marking, evacuation, and pointer updating. Container and assignment
type checks happen during compilation; runtime bounds and GC barriers remain.

The [JSON optimization report](benchmarks/results/json-optimized/README.md)
records a 22.8% instruction reduction and 90.6% less allocation when decoding
1,024 records. Its [independent audit](plugins/json/tests/audit/README.md)
includes 9,263 syntax cases, 765 scalar/binary/Unicode cases, and regressions
for error paths, excessive scratch allocation, and GC.

Earlier [CandidX conformance and fuzz results](benchmarks/results/typed-results/README.md)
and [historical benchmarks](benchmarks/results/README.md) retain their original
artifact hashes and ABI labels.

## Design and licensing

The [design document](docs/design.md) describes compiler specialization, memory
borrowing, compatibility, and the relationship to Wasm components. Plugins are
trusted compiler extensions; the shared-memory interface is not a sandbox.
The [persistent-map research](docs/pure-map-research.md) compares structurally
shared trees and records the SDK options considered. The implementation uses
integrated synchronous callbacks and optional native scalar ordering. Point
updates copy changed paths and share untouched branches and payloads.

Existing licenses are preserved. CandidX carries MIT licenses in its compiler
and runtime directories. Other extracted material uses the Motoko license in
[LICENSE](LICENSE). See [NOTICE](NOTICE) for extraction provenance.
