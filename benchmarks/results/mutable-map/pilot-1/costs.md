# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,226.00 | 4,942,832.00 | 196,568.00 | 59,256.00 | 1.68× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 98,356,595.00 | 57,585,694.00 | 2,460,248.00 | 591,112.00 | 1.71× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,175,071,733.00 | 685,168,784.00 | 30,051,776.00 | 5,842,360.00 | 1.72× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,289.00 | 3,543,591.00 | 222,216.00 | 65,400.00 | 1.85× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 81,252,701.00 | 45,053,148.00 | 2,617,368.00 | 656,296.00 | 1.80× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 996,350,488.00 | 547,540,801.00 | 32,024,568.00 | 6,559,048.00 | 1.82× |

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.94 | 4,985.00 | 200.00 | 40.00 | 1.70× |
| `Map.add` | add-insert | 10,000 | 10,114.62 | 6,318.50 | 230.00 | 63.00 | 1.60× |
| `Map.add` | add-insert | 100,000 | 12,817.78 | 6,503.62 | 324.00 | 40.00 | 1.97× |
| `Map.add` | add-overwrite | 1,000 | 5,801.06 | 3,247.28 | 230.00 | 40.00 | 1.79× |
| `Map.add` | add-overwrite | 10,000 | 6,920.19 | 4,551.59 | 230.00 | 63.00 | 1.52× |
| `Map.add` | add-overwrite | 100,000 | 8,528.56 | 4,902.91 | 286.00 | 40.00 | 1.74× |
| `Map.delete` | delete-hit | 1,000 | 10,290.69 | 6,997.41 | 357.75 | 216.00 | 1.47× |
| `Map.delete` | delete-hit | 10,000 | 11,314.47 | 10,805.94 | 360.25 | 216.00 | 1.05× |
| `Map.delete` | delete-hit | 100,000 | 14,111.88 | 11,740.53 | 520.25 | 216.00 | 1.20× |
| `Map.delete` | delete-miss | 1,000 | 6,937.62 | 3,203.38 | 320.00 | 0.00 | 2.17× |
| `Map.delete` | delete-miss | 10,000 | 8,066.38 | 6,901.75 | 320.00 | 0.00 | 1.17× |
| `Map.delete` | delete-miss | 100,000 | 10,432.66 | 8,081.50 | 464.00 | 0.00 | 1.29× |
| `Map.get` | get-hit | 1,000 | 5,119.91 | 2,775.28 | 95.00 | 0.00 | 1.84× |
| `Map.get` | get-hit | 10,000 | 6,234.53 | 3,419.47 | 95.00 | 0.00 | 1.82× |
| `Map.get` | get-hit | 100,000 | 7,700.66 | 4,287.91 | 123.00 | 0.00 | 1.80× |
| `Map.get` | get-miss | 1,000 | 5,345.12 | 2,908.78 | 96.00 | 0.00 | 1.84× |
| `Map.get` | get-miss | 10,000 | 6,471.03 | 3,547.41 | 96.00 | 0.00 | 1.82× |
| `Map.get` | get-miss | 100,000 | 8,177.19 | 4,423.41 | 128.00 | 0.00 | 1.85× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.94 | 4,985.00 | 4,227.19 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-insert | 10,000 | 10,114.62 | 6,318.50 | 5,348.16 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-insert | 100,000 | 12,817.78 | 6,503.62 | 6,054.97 | 324.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,801.06 | 3,247.28 | 2,532.22 | 230.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 10,000 | 6,920.19 | 4,551.59 | 3,622.22 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-overwrite | 100,000 | 8,528.56 | 4,902.91 | 3,853.34 | 286.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,119.91 | 2,775.28 | 2,059.72 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 6,234.53 | 3,419.47 | 2,490.09 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 7,700.66 | 4,287.91 | 3,169.34 | 123.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,345.12 | 2,908.78 | 2,150.47 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 6,471.03 | 3,547.41 | 2,577.06 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 8,177.19 | 4,423.41 | 3,273.59 | 128.00 | 0.00 | 0.00 |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
