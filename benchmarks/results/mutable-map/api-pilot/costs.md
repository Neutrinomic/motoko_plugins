# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 8,317,854.00 | 4,943,444.00 | 196,720.00 | 59,408.00 | 1.68× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,210.00 | 4,942,816.00 | 196,568.00 | 59,256.00 | 1.68× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,305.00 | 3,543,607.00 | 222,216.00 | 65,400.00 | 1.85× |
| `Map.fromVarArray` | fromVarArray-shuffled | 1,000 | 8,317,854.00 | 4,943,444.00 | 196,720.00 | 59,408.00 | 1.68× |

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.44 | 4,984.50 | 200.00 | 40.00 | 1.70× |
| `Map.add` | add-overwrite | 1,000 | 5,800.56 | 3,246.78 | 230.00 | 40.00 | 1.79× |
| `Map.all` | all-true | 1,000 | 1,626,402.00 | 714,632.00 | 110,776.00 | 40,112.00 | 2.28× |
| `Map.any` | any-false | 1,000 | 1,626,402.00 | 683,479.00 | 110,776.00 | 40,072.00 | 2.38× |
| `Map.clear` | clear | 1,000 | 2,171.00 | 355.00 | 488.00 | 0.00 | 6.12× |
| `Map.clone` | clone | 1,000 | 483,718.00 | 274,575.00 | 66,104.00 | 23,656.00 | 1.76× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 5,334.91 | 2,795.16 | 95.00 | 0.00 | 1.91× |
| `Map.delete` | delete-hit | 1,000 | 10,290.19 | 6,996.91 | 357.75 | 216.00 | 1.47× |
| `Map.delete` | delete-miss | 1,000 | 6,937.12 | 3,202.88 | 320.00 | 0.00 | 2.17× |
| `Map.entries` | entries-consume | 1,000 | 1,696,551.00 | 945,717.00 | 110,776.00 | 352.00 | 1.79× |
| `Map.entries` | entries-create | 1,000 | 3,167.38 | 1,848.38 | 432.00 | 352.00 | 1.71× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 35,071.38 | 26,059.12 | 2,267.00 | 1,192.00 | 1.35× |
| `Map.filter` | filter | 1,000 | 4,476,594.00 | 2,119,298.00 | 204,784.00 | 32,288.00 | 2.11× |
| `Map.filterMap` | filterMap | 1,000 | 4,514,594.00 | 2,156,298.00 | 204,784.00 | 32,288.00 | 2.09× |
| `Map.find` | find-first | 1,000 | 5,085.00 | 2,345.00 | 544.00 | 112.00 | 2.17× |
| `Map.find` | find-last | 1,000 | 1,704,418.00 | 733,231.00 | 110,776.00 | 40,072.00 | 2.32× |
| `Map.find` | find-middle | 1,000 | 855,962.00 | 368,017.00 | 55,904.00 | 20,112.00 | 2.33× |
| `Map.find` | find-missing | 1,000 | 1,704,504.00 | 733,467.00 | 110,776.00 | 40,072.00 | 2.32× |
| `Map.foldLeft` | foldLeft | 1,000 | 1,696,507.00 | 591,773.00 | 110,776.00 | 72.00 | 2.87× |
| `Map.foldRight` | foldRight | 1,000 | 1,677,694.00 | 599,673.00 | 110,776.00 | 72.00 | 2.80× |
| `Map.forEach` | forEach | 1,000 | 1,821,414.00 | 750,836.00 | 110,776.00 | 112.00 | 2.43× |
| `Map.get` | get-hit | 1,000 | 5,119.41 | 2,774.78 | 95.00 | 0.00 | 1.84× |
| `Map.get` | get-miss | 1,000 | 5,344.62 | 2,908.28 | 96.00 | 0.00 | 1.84× |
| `Map.getEntry` | getEntry-hit | 1,000 | 5,291.41 | 2,759.78 | 135.00 | 0.00 | 1.92× |
| `Map.insert` | insert-mixed | 1,000 | 7,151.06 | 4,247.00 | 214.00 | 40.00 | 1.68× |
| `Map.isEmpty` | isEmpty | 1,000 | 267.59 | 266.59 | 0.00 | 0.00 | 1.00× |
| `Map.map` | map | 1,000 | 621,705.00 | 638,283.00 | 66,104.00 | 59,328.00 | 0.97× |
| `Map.maxEntry` | maxEntry | 1,000 | 5,107.59 | 1,604.59 | 544.00 | 40.00 | 3.18× |
| `Map.minEntry` | minEntry | 1,000 | 4,640.59 | 1,558.59 | 544.00 | 40.00 | 2.98× |
| `Map.remove` | remove-hit | 1,000 | 10,238.19 | 6,930.91 | 357.75 | 216.00 | 1.48× |
| `Map.remove` | remove-miss | 1,000 | 6,885.12 | 3,136.88 | 320.00 | 0.00 | 2.19× |
| `Map.replace` | replace-hit | 1,000 | 10,797.31 | 3,029.78 | 325.00 | 40.00 | 3.56× |
| `Map.replace` | replace-miss | 1,000 | 5,444.62 | 2,955.28 | 96.00 | 0.00 | 1.84× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,677,738.00 | 841,568.00 | 110,776.00 | 352.00 | 1.99× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 3,663.38 | 1,848.38 | 432.00 | 352.00 | 1.98× |
| `Map.reverseEntriesFrom` | reverseEntriesFrom-seek16 | 1,000 | 34,325.25 | 26,033.12 | 2,258.00 | 1,437.00 | 1.32× |
| `Map.size` | size | 1,000 | 253.59 | 252.59 | 0.00 | 0.00 | 1.00× |
| `Map.swap` | swap-hit | 1,000 | 5,857.56 | 3,329.78 | 230.00 | 40.00 | 1.76× |
| `Map.take` | take-hit | 1,000 | 10,271.19 | 7,014.91 | 357.75 | 216.00 | 1.46× |
| `Map.take` | take-miss | 1,000 | 6,924.12 | 3,210.88 | 320.00 | 0.00 | 2.16× |
| `Map.toArray` | toArray | 1,000 | 2,180,410.00 | 819,726.00 | 182,992.00 | 8,416.00 | 2.66× |
| `Map.toVarArray` | toVarArray | 1,000 | 2,339,726.00 | 819,726.00 | 191,016.00 | 8,416.00 | 2.85× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.44 | 4,984.50 | 4,225.69 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,800.56 | 3,246.78 | 2,530.72 | 230.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,119.41 | 2,774.78 | 2,059.22 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,344.62 | 2,908.28 | 2,149.97 | 96.00 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-hit | 1,000 | 10,238.19 | 6,930.91 | 6,214.84 | 357.75 | 216.00 | 216.00 |
| `Map.removeNat64` | remove-miss | 1,000 | 6,885.12 | 3,136.88 | 2,378.06 | 320.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 10,797.31 | 3,029.78 | 2,313.72 | 325.00 | 40.00 | 40.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 5,444.62 | 2,955.28 | 2,196.97 | 96.00 | 0.00 | 0.00 |

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
