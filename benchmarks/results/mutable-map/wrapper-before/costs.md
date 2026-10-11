# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.find` | find-first | 10,000 | 5,101.00 | 2,361.00 | 544.00 | 112.00 | 2.16× |
| `Map.find` | find-first | 100,000 | 5,804.00 | 2,773.00 | 624.00 | 112.00 | 2.09× |
| `Map.find` | find-last | 10,000 | 17,031,699.00 | 7,328,490.00 | 1,104,912.00 | 400,072.00 | 2.32× |
| `Map.find` | find-last | 100,000 | 170,277,725.00 | 81,716,460.00 | 11,059,840.00 | 4,000,072.00 | 2.08× |
| `Map.find` | find-middle | 10,000 | 8,521,226.00 | 3,667,357.00 | 552,800.00 | 200,112.00 | 2.32× |
| `Map.find` | find-middle | 100,000 | 85,147,697.00 | 40,888,067.00 | 5,528,224.00 | 2,000,112.00 | 2.08× |
| `Map.find` | find-missing | 10,000 | 17,031,785.00 | 7,328,726.00 | 1,104,912.00 | 400,072.00 | 2.32× |
| `Map.find` | find-missing | 100,000 | 170,277,811.00 | 81,716,686.00 | 11,059,840.00 | 4,000,072.00 | 2.08× |
| `Map.foldLeft` | foldLeft | 10,000 | 16,951,788.00 | 5,911,546.00 | 1,104,912.00 | 72.00 | 2.87× |
| `Map.foldLeft` | foldLeft | 100,000 | 169,477,814.00 | 62,643,773.00 | 11,059,840.00 | 72.00 | 2.71× |
| `Map.foldRight` | foldRight | 10,000 | 16,768,184.00 | 5,990,544.00 | 1,104,912.00 | 72.00 | 2.80× |
| `Map.foldRight` | foldRight | 100,000 | 167,556,992.00 | 63,434,089.00 | 11,059,840.00 | 72.00 | 2.64× |
| `Map.map` | map | 10,000 | 6,270,601.00 | 6,373,844.00 | 665,536.00 | 591,184.00 | 0.98× |
| `Map.map` | map | 100,000 | 60,103,049.00 | 79,876,842.00 | 6,441,152.00 | 5,842,432.00 | 0.75× |


## Core baseline details

Explicit adapters are used where Core has no matching public API. All direct baselines use mo:core/Map 2.5.0; find/getEntry use the listed small public API adapters.

| Workload | Core baseline | Note |
| --- | --- | --- |
| find-first | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-last | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-middle | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |
| find-missing | `Iter.find(entries)` | Ordered predicate search; Core has no direct find function. |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
