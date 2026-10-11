# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,210.00 | 3,960,904.00 | 196,568.00 | 59,256.00 | 2.10× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,305.00 | 3,397,773.00 | 222,216.00 | 65,400.00 | 1.92× |
| `Map.fromVarArray` | fromVarArray-shuffled | 1,000 | 8,317,854.00 | 3,961,532.00 | 196,720.00 | 59,408.00 | 2.10× |

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 200.00 | 40.00 | 2.07× |
| `Map.add` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 230.00 | 40.00 | 1.92× |
| `Map.all` | all-true | 1,000 | 1,626,450.00 | 351,618.00 | 110,776.00 | 112.00 | 4.63× |
| `Map.any` | any-false | 1,000 | 1,626,450.00 | 320,465.00 | 110,776.00 | 72.00 | 5.08× |
| `Map.clear` | clear | 1,000 | 2,171.00 | 355.00 | 488.00 | 0.00 | 6.12× |
| `Map.clone` | clone | 1,000 | 483,718.00 | 274,607.00 | 66,104.00 | 23,656.00 | 1.76× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 5,334.41 | 2,565.41 | 95.00 | 0.00 | 2.08× |
| `Map.delete` | delete-hit | 1,000 | 10,289.19 | 3,873.62 | 357.75 | 0.00 | 2.66× |
| `Map.delete` | delete-miss | 1,000 | 6,936.62 | 2,921.78 | 320.00 | 0.00 | 2.37× |
| `Map.entries` | entries-consume | 1,000 | 1,696,599.00 | 945,701.00 | 110,776.00 | 352.00 | 1.79× |
| `Map.entries` | entries-create | 1,000 | 3,165.38 | 1,848.38 | 432.00 | 352.00 | 1.71× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 35,069.38 | 24,661.12 | 2,267.00 | 792.00 | 1.42× |
| `Map.filter` | filter | 1,000 | 4,476,594.00 | 1,851,216.00 | 204,784.00 | 32,288.00 | 2.42× |
| `Map.filterMap` | filterMap | 1,000 | 4,514,594.00 | 1,888,216.00 | 204,784.00 | 32,288.00 | 2.39× |
| `Map.find` | find-first | 1,000 | 5,101.00 | 2,027.00 | 544.00 | 72.00 | 2.52× |
| `Map.find` | find-last | 1,000 | 1,704,466.00 | 370,371.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.find` | find-middle | 1,000 | 856,010.00 | 186,188.00 | 55,904.00 | 72.00 | 4.60× |
| `Map.find` | find-missing | 1,000 | 1,704,552.00 | 370,453.00 | 110,776.00 | 72.00 | 4.60× |
| `Map.foldLeft` | foldLeft | 1,000 | 1,696,555.00 | 388,927.00 | 110,776.00 | 72.00 | 4.36× |
| `Map.foldRight` | foldRight | 1,000 | 1,677,742.00 | 396,827.00 | 110,776.00 | 72.00 | 4.23× |
| `Map.forEach` | forEach | 1,000 | 1,821,462.00 | 547,990.00 | 110,776.00 | 112.00 | 3.32× |
| `Map.get` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 95.00 | 0.00 | 2.01× |
| `Map.get` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 96.00 | 0.00 | 2.01× |
| `Map.getEntry` | getEntry-hit | 1,000 | 5,290.91 | 2,536.59 | 135.00 | 0.00 | 2.09× |
| `Map.insert` | insert-mixed | 1,000 | 7,150.06 | 3,649.56 | 214.00 | 40.00 | 1.96× |
| `Map.isEmpty` | isEmpty | 1,000 | 267.09 | 267.09 | 0.00 | 0.00 | 1.00× |
| `Map.map` | map | 1,000 | 621,705.00 | 600,904.00 | 66,104.00 | 59,328.00 | 1.03× |
| `Map.maxEntry` | maxEntry | 1,000 | 5,108.09 | 1,451.59 | 544.00 | 0.00 | 3.52× |
| `Map.minEntry` | minEntry | 1,000 | 4,641.09 | 1,405.59 | 544.00 | 0.00 | 3.30× |
| `Map.remove` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 357.75 | 0.00 | 2.69× |
| `Map.remove` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 320.00 | 0.00 | 2.41× |
| `Map.replace` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 325.00 | 40.00 | 3.85× |
| `Map.replace` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 96.00 | 0.00 | 2.01× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,677,786.00 | 841,552.00 | 110,776.00 | 352.00 | 1.99× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 3,661.38 | 1,848.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 1,000 | 34,323.25 | 24,613.62 | 2,258.00 | 1,032.00 | 1.39× |
| `Map.size` | size | 1,000 | 253.09 | 253.09 | 0.00 | 0.00 | 1.00× |
| `Map.swap` | swap-hit | 1,000 | 5,856.56 | 3,107.09 | 230.00 | 40.00 | 1.88× |
| `Map.take` | take-hit | 1,000 | 10,270.19 | 3,891.62 | 357.75 | 0.00 | 2.64× |
| `Map.take` | take-miss | 1,000 | 6,923.62 | 2,929.78 | 320.00 | 0.00 | 2.36× |
| `Map.toArray` | toArray | 1,000 | 2,180,442.00 | 819,710.00 | 182,992.00 | 8,416.00 | 2.66× |
| `Map.toVarArray` | toVarArray | 1,000 | 2,339,758.00 | 819,710.00 | 191,016.00 | 8,416.00 | 2.85× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.44 | 4,097.62 | 3,337.81 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,800.56 | 3,024.09 | 2,307.03 | 230.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,118.91 | 2,551.59 | 1,835.03 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,344.12 | 2,658.84 | 1,899.53 | 96.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 1,000 | 10,238.19 | 3,807.62 | 3,090.56 | 357.75 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 1,000 | 6,885.12 | 2,855.78 | 2,096.47 | 320.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 10,796.31 | 2,806.59 | 2,090.03 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 5,444.12 | 2,705.84 | 1,946.53 | 96.00 | 0.00 | 0.00 |

## Core baseline details

Explicit adapters are used where Core has no matching public API. All direct baselines use mo:core/Map 2.5.0; find/getEntry use the listed small public API adapters.

| Workload | Core baseline | Note |
| --- | --- | --- |
| find-first | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-last | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-middle | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-missing | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| getEntry-hit | `get + optional pair` | Core.get mapped to the requested key; exact Nat64 key ordering makes keys equivalent. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
