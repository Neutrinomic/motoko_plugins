# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 8,317,226.00 | 3,960,920.00 | 196,568.00 | 59,256.00 | 2.10× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 98,356,595.00 | 47,261,408.00 | 2,460,248.00 | 591,112.00 | 2.08× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,175,071,733.00 | 566,138,210.00 | 30,051,776.00 | 5,842,360.00 | 2.08× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 6,539,289.00 | 3,397,757.00 | 222,216.00 | 65,400.00 | 1.92× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 81,252,701.00 | 42,662,313.00 | 2,617,368.00 | 656,296.00 | 1.90× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 996,350,488.00 | 514,898,108.00 | 32,024,568.00 | 6,559,048.00 | 1.94× |

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 8,465.94 | 4,097.12 | 200.00 | 40.00 | 2.07× |
| `Map.add` | add-insert | 10,000 | 10,114.62 | 5,153.06 | 230.00 | 63.00 | 1.96× |
| `Map.add` | add-insert | 100,000 | 12,817.78 | 5,497.44 | 324.00 | 40.00 | 2.33× |
| `Map.add` | add-overwrite | 1,000 | 5,801.06 | 3,023.59 | 230.00 | 40.00 | 1.92× |
| `Map.add` | add-overwrite | 10,000 | 6,920.19 | 4,066.75 | 230.00 | 63.00 | 1.70× |
| `Map.add` | add-overwrite | 100,000 | 8,528.56 | 4,490.91 | 286.00 | 40.00 | 1.90× |
| `Map.delete` | delete-hit | 1,000 | 10,290.69 | 3,873.12 | 357.75 | 0.00 | 2.66× |
| `Map.delete` | delete-hit | 10,000 | 11,314.47 | 6,487.03 | 360.25 | 0.00 | 1.74× |
| `Map.delete` | delete-hit | 100,000 | 14,111.88 | 7,832.31 | 520.25 | 0.00 | 1.80× |
| `Map.delete` | delete-miss | 1,000 | 6,937.62 | 2,921.78 | 320.00 | 0.00 | 2.37× |
| `Map.delete` | delete-miss | 10,000 | 8,066.38 | 5,480.22 | 320.00 | 0.00 | 1.47× |
| `Map.delete` | delete-miss | 100,000 | 10,432.66 | 6,945.97 | 464.00 | 0.00 | 1.50× |
| `Map.get` | get-hit | 1,000 | 5,119.91 | 2,551.59 | 95.00 | 0.00 | 2.01× |
| `Map.get` | get-hit | 10,000 | 6,234.53 | 3,080.94 | 95.00 | 0.00 | 2.02× |
| `Map.get` | get-hit | 100,000 | 7,700.66 | 3,875.91 | 123.00 | 0.00 | 1.99× |
| `Map.get` | get-miss | 1,000 | 5,345.12 | 2,658.84 | 96.00 | 0.00 | 2.01× |
| `Map.get` | get-miss | 10,000 | 6,471.03 | 3,183.72 | 96.00 | 0.00 | 2.03× |
| `Map.get` | get-miss | 100,000 | 8,177.19 | 3,985.16 | 128.00 | 0.00 | 2.05× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 8,465.94 | 4,097.12 | 3,339.31 | 200.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-insert | 10,000 | 10,114.62 | 5,153.06 | 4,182.72 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-insert | 100,000 | 12,817.78 | 5,497.44 | 5,048.78 | 324.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 1,000 | 5,801.06 | 3,023.59 | 2,308.53 | 230.00 | 40.00 | 40.00 |
| `Map.addNat64` | add-overwrite | 10,000 | 6,920.19 | 4,066.75 | 3,137.38 | 230.00 | 63.00 | 63.00 |
| `Map.addNat64` | add-overwrite | 100,000 | 8,528.56 | 4,490.91 | 3,441.34 | 286.00 | 40.00 | 40.00 |
| `Map.getNat64` | get-hit | 1,000 | 5,119.91 | 2,551.59 | 1,836.03 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 6,234.53 | 3,080.94 | 2,151.56 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 7,700.66 | 3,875.91 | 2,757.34 | 123.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,345.12 | 2,658.84 | 1,900.53 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 6,471.03 | 3,183.72 | 2,213.38 | 96.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 8,177.19 | 3,985.16 | 2,835.34 | 128.00 | 0.00 | 0.00 |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
