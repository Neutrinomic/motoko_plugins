# Mutable map function costs

1-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.remove` | remove-hit | 100,000 | 14,060.38 | 7,767.81 | 520.25 | 0.00 | 1.81× |
| `Map.remove` | remove-miss | 100,000 | 10,381.66 | 6,880.97 | 464.00 | 0.00 | 1.51× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.removeNat64` | remove-hit | 100,000 | 14,060.38 | 7,767.81 | 6,580.94 | 520.25 | 0.00 | 0.00 |
| `Map.removeNat64` | remove-miss | 100,000 | 10,381.66 | 6,880.97 | 5,651.34 | 464.00 | 0.00 | 0.00 |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
