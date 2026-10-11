# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.get` | get-hit | 1,000 | 5,119.41 | 2,552.09 | 95.00 | 0.00 | 2.01× |
| `Map.get` | get-miss | 1,000 | 5,344.62 | 2,659.34 | 96.00 | 0.00 | 2.01× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.getNat64` | get-hit | 1,000 | 5,119.41 | 2,552.09 | 1,835.53 | 95.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 5,344.62 | 2,659.34 | 1,900.03 | 96.00 | 0.00 | 0.00 |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
