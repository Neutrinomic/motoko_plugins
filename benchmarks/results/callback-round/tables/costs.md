# Selected callback operations at 1,000, 10,000, and 100,000 entries

Three identical trials per version. Counts are instructions or cumulative allocated bytes per complete operation, averaged over32 calls. Every implementation runs in a fresh canister. Allocation is unchanged before/after; it is not peak/live memory.

| Map | Operation | Entries | Core instructions | Callback before | Callback after | Scalar after | Callback reduction | Core allocated B | Plugin allocated B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pure-map | get-hit | 1,000 | 2,041.19 | 1,604.38 | 1,536.59 | 891.78 | 4.22% | 0.00 | 0.00 |
| pure-map | get-miss | 1,000 | 2,237.69 | 1,710.88 | 1,639.34 | 955.53 | 4.18% | 0.00 | 0.00 |
| pure-map | add-insert | 1,000 | 9,952.34 | 6,580.50 | 6,508.97 | 5,825.16 | 1.09% | 1,840.50 | 850.50 |
| pure-map | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 3,697.97 | 3,053.16 | 1.80% | 1,395.50 | 677.25 |
| pure-map | take-hit | 1,000 | 10,700.91 | 5,911.31 | 5,843.53 | — | 1.15% | 2,060.75 | 717.25 |
| pure-map | delete-mixed | 1,000 | 10,437.75 | 4,015.50 | 3,945.84 | — | 1.73% | 1,987.75 | 357.50 |
| pure-map | get-hit | 10,000 | 2,736.97 | 2,129.44 | 2,037.62 | 1,174.53 | 4.31% | 0.00 | 0.00 |
| pure-map | get-miss | 10,000 | 2,942.59 | 2,248.19 | 2,152.47 | 1,248.75 | 4.26% | 0.00 | 0.00 |
| pure-map | add-insert | 10,000 | 11,554.31 | 8,574.94 | 8,479.22 | 7,575.50 | 1.12% | 2,034.50 | 1,107.00 |
| pure-map | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 4,893.62 | 4,030.53 | 1.84% | 1,816.75 | 913.50 |
| pure-map | take-hit | 10,000 | 15,427.75 | 7,724.25 | 7,632.44 | — | 1.19% | 3,014.00 | 931.00 |
| pure-map | delete-mixed | 10,000 | 14,751.44 | 5,244.69 | 5,150.53 | — | 1.80% | 2,885.00 | 467.75 |
| pure-map | get-hit | 100,000 | 3,324.09 | 2,524.38 | 2,410.75 | 1,345.19 | 4.50% | 0.00 | 0.00 |
| pure-map | get-miss | 100,000 | 3,518.72 | 2,649.88 | 2,531.88 | 1,420.81 | 4.45% | 0.00 | 0.00 |
| pure-map | add-insert | 100,000 | 14,112.34 | 10,137.75 | 10,019.75 | 8,908.69 | 1.16% | 2,524.25 | 1,289.25 |
| pure-map | add-overwrite | 100,000 | 12,817.72 | 6,056.12 | 5,942.50 | 4,876.94 | 1.88% | 2,230.50 | 1,143.00 |
| pure-map | take-hit | 100,000 | 17,354.00 | 9,607.38 | 9,493.75 | — | 1.18% | 3,402.50 | 1,187.50 |
| pure-map | delete-mixed | 100,000 | 17,230.59 | 6,426.88 | 6,310.75 | — | 1.81% | 3,373.00 | 596.00 |
| mutable-map | get-hit | 1,000 | 5,119.41 | 2,551.59 | 2,483.78 | 1,835.53 | 2.66% | 95.00 | 0.00 |
| mutable-map | get-miss | 1,000 | 5,344.62 | 2,658.84 | 2,587.28 | 1,900.03 | 2.69% | 96.00 | 0.00 |
| mutable-map | add-insert | 1,000 | 8,465.94 | 4,097.12 | 4,025.56 | 3,338.31 | 1.75% | 200.00 | 40.00 |
| mutable-map | add-overwrite | 1,000 | 5,801.06 | 3,023.59 | 2,955.78 | 2,307.53 | 2.24% | 230.00 | 40.00 |
| mutable-map | remove-hit | 1,000 | 10,238.69 | 3,807.12 | 3,739.31 | 3,091.06 | 1.78% | 357.75 | 0.00 |
| mutable-map | remove-miss | 1,000 | 6,885.62 | 2,855.78 | 2,784.22 | 2,096.97 | 2.51% | 320.00 | 0.00 |
| mutable-map | get-hit | 10,000 | 6,234.53 | 3,080.94 | 2,993.09 | 2,151.56 | 2.85% | 95.00 | 0.00 |
| mutable-map | get-miss | 10,000 | 6,471.03 | 3,183.72 | 3,092.28 | 2,213.38 | 2.87% | 96.00 | 0.00 |
| mutable-map | add-insert | 10,000 | 10,114.62 | 5,153.06 | 5,061.62 | 4,182.72 | 1.77% | 230.00 | 63.00 |
| mutable-map | add-overwrite | 10,000 | 6,920.19 | 4,066.75 | 3,978.91 | 3,137.38 | 2.16% | 230.00 | 63.00 |
| mutable-map | remove-hit | 10,000 | 11,262.47 | 6,421.03 | 6,333.41 | 5,495.19 | 1.36% | 360.25 | 0.00 |
| mutable-map | remove-miss | 10,000 | 8,014.38 | 5,414.22 | 5,322.84 | 4,445.62 | 1.69% | 320.00 | 0.00 |
| mutable-map | get-hit | 100,000 | 7,701.16 | 3,876.91 | 3,765.66 | 2,712.34 | 2.87% | 123.00 | 0.00 |
| mutable-map | get-miss | 100,000 | 8,178.19 | 3,986.16 | 3,871.16 | 2,778.84 | 2.88% | 128.00 | 0.00 |
| mutable-map | add-insert | 100,000 | 12,818.78 | 5,497.94 | 5,382.94 | 4,290.62 | 2.09% | 324.00 | 40.00 |
| mutable-map | add-overwrite | 100,000 | 8,529.06 | 4,491.41 | 4,380.16 | 3,326.84 | 2.48% | 286.00 | 40.00 |
| mutable-map | remove-hit | 100,000 | 14,060.38 | 7,767.81 | 7,654.47 | 6,580.94 | 1.46% | 520.25 | 0.00 |
| mutable-map | remove-miss | 100,000 | 10,381.66 | 6,880.97 | 6,763.88 | 5,651.34 | 1.70% | 464.00 | 0.00 |

Pure-map `take-hit` returns the old entry; `delete-mixed` alternates present and absent keys. These are the existing persistent-map deletion workloads. Mutable `remove-hit/miss` update the same map in place. The selected persistent deletion workloads have no scalar measurement.

[Raw batch and per-operation comparison CSV](comparison.csv). The four per-version CSVs retain full raw counts and trial ranges.
