# Public map function costs

Three-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, split, and construction rows measure the complete function call. Snapshot creation is per captured root/snapshot. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.fromArray` | fromArray-shuffled | 1,000 | 7,606,083.00 | 7,291,101.00 | 1,395,104.00 | 463,216.00 | 1.04× |
| `Map.fromArray` | fromArray-shuffled | 10,000 | 102,601,814.00 | 100,956,659.00 | 18,838,600.00 | 6,369,896.00 | 1.02× |
| `Map.fromArray` | fromArray-shuffled | 100,000 | 1,233,077,190.00 | 1,182,852,595.00 | 224,253,736.00 | 73,573,936.00 | 1.04× |
| `Map.fromIter` | fromIter-shuffled | 1,000 | 7,605,488.00 | 8,364,890.00 | 1,394,952.00 | 487,880.00 | 0.91× |
| `Map.fromIter` | fromIter-shuffled | 10,000 | 102,601,219.00 | 113,283,772.00 | 18,838,448.00 | 6,712,416.00 | 0.91× |
| `Map.fromIter` | fromIter-shuffled | 100,000 | 1,233,076,595.00 | 1,297,500,651.00 | 224,253,584.00 | 76,471,536.00 | 0.95× |
| `Map.fromIter` | fromIter-sorted | 1,000 | 10,203,874.00 | 1,727,096.00 | 1,831,072.00 | 96,688.00 | 5.91× |
| `Map.fromIter` | fromIter-sorted | 10,000 | 135,473,401.00 | 18,857,900.00 | 23,988,728.00 | 1,062,544.00 | 7.18× |
| `Map.fromIter` | fromIter-sorted | 100,000 | 1,694,931,186.00 | 179,953,531.00 | 297,345,304.00 | 10,097,624.00 | 9.42× |

## Operations on populated maps

| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.add` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 1,840.50 | 850.50 | 1.51× |
| `Map.add` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 2,034.50 | 1,107.00 | 1.35× |
| `Map.add` | add-insert | 100,000 | 14,112.34 | 10,148.97 | 2,524.25 | 1,289.25 | 1.39× |
| `Map.add` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 1,395.50 | 677.25 | 2.16× |
| `Map.add` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 1,816.75 | 913.50 | 2.10× |
| `Map.add` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 2,230.50 | 1,143.00 | 2.11× |
| `Map.alter` | alter-mixed | 1,000 | 11,258.12 | 5,561.62 | 1,647.00 | 822.75 | 2.02× |
| `Map.alter` | alter-mixed | 10,000 | 13,678.84 | 7,205.69 | 1,944.00 | 1,077.00 | 1.90× |
| `Map.alter` | alter-mixed | 100,000 | 16,945.25 | 8,522.34 | 2,422.75 | 1,281.75 | 1.99× |
| `Map.containsKey` | containsKey-mixed | 1,000 | 2,183.69 | 1,692.78 | 0.00 | 0.00 | 1.29× |
| `Map.containsKey` | containsKey-mixed | 10,000 | 2,831.84 | 2,252.47 | 0.00 | 0.00 | 1.26× |
| `Map.containsKey` | containsKey-mixed | 100,000 | 3,450.09 | 2,663.25 | 0.00 | 0.00 | 1.30× |
| `Map.delete` | delete-mixed | 1,000 | 10,437.75 | 4,015.50 | 1,987.75 | 357.50 | 2.60× |
| `Map.delete` | delete-mixed | 10,000 | 14,751.44 | 5,245.69 | 2,885.00 | 467.75 | 2.81× |
| `Map.delete` | delete-mixed | 100,000 | 17,230.59 | 6,426.88 | 3,373.00 | 596.00 | 2.68× |
| `Map.entries` | entries-consume | 1,000 | 1,608,622.00 | 1,237,767.00 | 256,176.00 | 40,440.00 | 1.30× |
| `Map.entries` | entries-consume | 10,000 | 16,219,373.00 | 12,350,986.00 | 2,560,176.00 | 400,472.00 | 1.31× |
| `Map.entries` | entries-consume | 100,000 | 161,456,649.00 | 123,429,973.00 | 25,600,176.00 | 4,000,504.00 | 1.31× |
| `Map.entries` | entries-create | 1,000 | 1,072.38 | 5,653.38 | 176.00 | 440.00 | 0.19× |
| `Map.entries` | entries-create | 10,000 | 1,072.38 | 6,989.38 | 176.00 | 472.00 | 0.15× |
| `Map.entries` | entries-create | 100,000 | 1,108.75 | 8,781.75 | 176.00 | 504.00 | 0.13× |
| `Map.entriesFrom` | entriesFrom-seek16 | 1,000 | 794,041.00 | 27,843.50 | 131,432.00 | 1,112.00 | 28.52× |
| `Map.entriesFrom` | entriesFrom-seek16 | 10,000 | 7,819,157.12 | 29,491.38 | 1,283,656.00 | 1,144.00 | 265.13× |
| `Map.entriesFrom` | entriesFrom-seek16 | 100,000 | 77,630,138.25 | 31,425.75 | 12,804,424.00 | 1,176.00 | 2470.27× |
| `Map.entriesInRange` | entriesInRange-seek16 | 1,000 | 798,511.00 | 29,070.88 | 131,584.00 | 1,080.00 | 27.47× |
| `Map.entriesInRange` | entriesInRange-seek16 | 10,000 | 7,823,627.12 | 31,363.75 | 1,283,808.00 | 1,112.00 | 249.45× |
| `Map.entriesInRange` | entriesInRange-seek16 | 100,000 | 77,634,608.25 | 33,690.50 | 12,804,576.00 | 1,144.00 | 2304.35× |
| `Map.filterMap` | filterMap | 1,000 | 4,885,562.00 | 860,708.00 | 829,640.00 | 68,904.00 | 5.68× |
| `Map.filterMap` | filterMap | 10,000 | 65,605,684.00 | 8,241,842.00 | 11,134,592.00 | 614,448.00 | 7.96× |
| `Map.filterMap` | filterMap | 100,000 | 825,830,263.00 | 86,873,288.00 | 140,072,896.00 | 7,070,760.00 | 9.51× |
| `Map.find` | find-first | 1,000 | 11,292.00 | 2,433.00 | 2,224.00 | 112.00 | 4.64× |
| `Map.find` | find-first | 10,000 | 21,897.00 | 2,939.00 | 4,528.00 | 112.00 | 7.45× |
| `Map.find` | find-first | 100,000 | 24,253.00 | 3,571.00 | 5,040.00 | 112.00 | 6.79× |
| `Map.find` | find-last | 1,000 | 1,616,489.00 | 453,355.00 | 256,176.00 | 112.00 | 3.57× |
| `Map.find` | find-last | 10,000 | 16,299,240.00 | 4,528,043.00 | 2,560,176.00 | 112.00 | 3.60× |
| `Map.find` | find-last | 100,000 | 162,256,516.00 | 45,205,867.00 | 25,600,176.00 | 112.00 | 3.59× |
| `Map.find` | find-middle | 1,000 | 817,769.00 | 228,597.00 | 129,968.00 | 112.00 | 3.58× |
| `Map.find` | find-middle | 10,000 | 8,159,271.00 | 2,269,285.00 | 1,281,200.00 | 112.00 | 3.60× |
| `Map.find` | find-middle | 100,000 | 81,141,704.00 | 22,607,741.00 | 12,802,224.00 | 112.00 | 3.59× |
| `Map.find` | find-missing | 1,000 | 1,616,602.00 | 453,304.00 | 256,176.00 | 72.00 | 3.57× |
| `Map.find` | find-missing | 10,000 | 16,299,353.00 | 4,527,992.00 | 2,560,176.00 | 72.00 | 3.60× |
| `Map.find` | find-missing | 100,000 | 162,256,629.00 | 45,205,816.00 | 25,600,176.00 | 72.00 | 3.59× |
| `Map.foldLeft` | foldLeft | 1,000 | 315,007.00 | 461,310.00 | 0.00 | 72.00 | 0.68× |
| `Map.foldLeft` | foldLeft | 10,000 | 3,204,063.00 | 4,607,998.00 | 0.00 | 72.00 | 0.70× |
| `Map.foldLeft` | foldLeft | 100,000 | 31,665,567.00 | 46,005,822.00 | 0.00 | 72.00 | 0.69× |
| `Map.foldRight` | foldRight | 1,000 | 315,007.00 | 461,310.00 | 0.00 | 72.00 | 0.68× |
| `Map.foldRight` | foldRight | 10,000 | 3,204,063.00 | 4,607,998.00 | 0.00 | 72.00 | 0.70× |
| `Map.foldRight` | foldRight | 100,000 | 31,665,567.00 | 46,005,822.00 | 0.00 | 72.00 | 0.69× |
| `Map.get` | get-hit | 1,000 | 2,041.19 | 1,648.41 | 0.00 | 0.00 | 1.24× |
| `Map.get` | get-hit | 10,000 | 2,736.97 | 2,189.88 | 0.00 | 0.00 | 1.25× |
| `Map.get` | get-hit | 100,000 | 3,324.09 | 2,600.75 | 0.00 | 0.00 | 1.28× |
| `Map.get` | get-miss | 1,000 | 2,237.69 | 1,763.66 | 0.00 | 0.00 | 1.27× |
| `Map.get` | get-miss | 10,000 | 2,942.59 | 2,317.53 | 0.00 | 0.00 | 1.27× |
| `Map.get` | get-miss | 100,000 | 3,518.72 | 2,735.62 | 0.00 | 0.00 | 1.29× |
| `Map.getEntry` | getEntry-hit | 1,000 | 2,213.19 | 1,786.41 | 40.00 | 40.00 | 1.24× |
| `Map.getEntry` | getEntry-hit | 10,000 | 2,908.97 | 2,327.88 | 40.00 | 40.00 | 1.25× |
| `Map.getEntry` | getEntry-hit | 100,000 | 3,496.09 | 2,738.75 | 40.00 | 40.00 | 1.28× |
| `Map.insert` | insert-mixed | 1,000 | 9,122.19 | 5,332.62 | 1,607.00 | 782.75 | 1.71× |
| `Map.insert` | insert-mixed | 10,000 | 11,000.25 | 6,976.69 | 1,904.00 | 1,037.00 | 1.58× |
| `Map.insert` | insert-mixed | 100,000 | 13,585.41 | 8,292.84 | 2,382.75 | 1,241.75 | 1.64× |
| `Map.map` | map | 1,000 | 629,222.00 | 618,972.00 | 88,112.00 | 72,072.00 | 1.02× |
| `Map.map` | map | 10,000 | 6,340,550.00 | 6,183,836.00 | 880,112.00 | 720,072.00 | 1.03× |
| `Map.map` | map | 100,000 | 63,111,408.00 | 61,842,446.00 | 8,800,112.00 | 7,200,072.00 | 1.02× |
| `Map.rank` | rank | 1,000 | 743,056.50 | 1,906.12 | 129,264.00 | 40.00 | 389.83× |
| `Map.rank` | rank | 10,000 | 7,449,898.00 | 2,962.38 | 1,281,776.00 | 40.00 | 2514.84× |
| `Map.rank` | rank | 100,000 | 74,044,883.88 | 3,350.88 | 12,802,192.00 | 40.00 | 22097.18× |
| `Map.replace` | replace-hit | 1,000 | 9,848.69 | 3,852.75 | 1,355.50 | 677.25 | 2.56× |
| `Map.replace` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 1,776.75 | 913.50 | 2.52× |
| `Map.replace` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 2,190.50 | 1,143.00 | 2.56× |
| `Map.replace` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 0.00 | 0.00 | 1.16× |
| `Map.replace` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 0.00 | 0.00 | 1.17× |
| `Map.replace` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 0.00 | 0.00 | 1.18× |
| `Map.replay` | replay-consume | 1,000 | 1,608,622.00 | 1,237,547.00 | 256,176.00 | 40,384.00 | 1.30× |
| `Map.replay` | replay-consume | 10,000 | 16,219,373.00 | 12,350,766.00 | 2,560,176.00 | 400,416.00 | 1.31× |
| `Map.replay` | replay-consume | 100,000 | 161,456,649.00 | 123,429,753.00 | 25,600,176.00 | 4,000,448.00 | 1.31× |
| `Map.replay` | replay-create | 1,000 | 1,072.38 | 5,433.38 | 176.00 | 384.00 | 0.20× |
| `Map.replay` | replay-create | 10,000 | 1,072.38 | 6,769.38 | 176.00 | 416.00 | 0.16× |
| `Map.replay` | replay-create | 100,000 | 1,108.75 | 8,561.75 | 176.00 | 448.00 | 0.13× |
| `Map.reverseEntries` | reverseEntries-consume | 1,000 | 1,608,628.00 | 1,238,586.00 | 256,176.00 | 40,440.00 | 1.30× |
| `Map.reverseEntries` | reverseEntries-consume | 10,000 | 16,219,379.00 | 12,352,421.00 | 2,560,176.00 | 400,472.00 | 1.31× |
| `Map.reverseEntries` | reverseEntries-consume | 100,000 | 161,456,655.00 | 123,431,394.00 | 25,600,176.00 | 4,000,504.00 | 1.31× |
| `Map.reverseEntries` | reverseEntries-create | 1,000 | 1,078.38 | 6,801.38 | 176.00 | 440.00 | 0.16× |
| `Map.reverseEntries` | reverseEntries-create | 10,000 | 1,078.38 | 9,417.38 | 176.00 | 472.00 | 0.11× |
| `Map.reverseEntries` | reverseEntries-create | 100,000 | 1,114.75 | 10,547.75 | 176.00 | 504.00 | 0.11× |
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
| `Map.take` | take-hit | 100,000 | 17,354.00 | 9,607.88 | 3,402.50 | 1,187.50 | 1.81× |
| `Map.update` | update-mixed | 1,000 | 11,186.12 | 5,514.62 | 1,607.00 | 782.75 | 2.03× |
| `Map.update` | update-mixed | 10,000 | 13,606.84 | 7,158.69 | 1,904.00 | 1,037.00 | 1.90× |
| `Map.update` | update-mixed | 100,000 | 16,873.25 | 8,475.34 | 2,382.75 | 1,241.75 | 1.99× |

## Scalar ordering on the same workloads

The callback path uses the same Motoko comparator as Core. The scalar path orders Nat64 keys directly; values remain generic Motoko references.

| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Map.addNat64` | add-insert | 1,000 | 9,952.34 | 6,580.50 | 5,824.16 | 1,840.50 | 850.50 | 850.50 |
| `Map.addNat64` | add-insert | 10,000 | 11,554.31 | 8,575.94 | 7,575.50 | 2,034.50 | 1,107.00 | 1,107.00 |
| `Map.addNat64` | add-insert | 100,000 | 14,112.34 | 10,148.97 | 8,919.91 | 2,524.25 | 1,289.25 | 1,289.25 |
| `Map.addNat64` | add-overwrite | 1,000 | 8,127.25 | 3,765.75 | 3,052.16 | 1,395.50 | 677.25 | 677.25 |
| `Map.addNat64` | add-overwrite | 10,000 | 10,491.78 | 4,985.44 | 4,031.53 | 1,816.75 | 913.50 | 913.50 |
| `Map.addNat64` | add-overwrite | 100,000 | 12,817.72 | 6,066.84 | 4,876.94 | 2,230.50 | 1,143.00 | 1,143.00 |
| `Map.getNat64` | get-hit | 1,000 | 2,041.19 | 1,648.41 | 935.81 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 10,000 | 2,736.97 | 2,189.88 | 1,234.97 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-hit | 100,000 | 3,324.09 | 2,600.75 | 1,421.56 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 1,000 | 2,237.69 | 1,763.66 | 1,008.31 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 10,000 | 2,942.59 | 2,317.53 | 1,318.09 | 0.00 | 0.00 | 0.00 |
| `Map.getNat64` | get-miss | 100,000 | 3,518.72 | 2,735.62 | 1,506.56 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-hit | 1,000 | 9,848.69 | 3,852.75 | 3,139.16 | 1,355.50 | 677.25 | 677.25 |
| `Map.replaceNat64` | replace-hit | 10,000 | 12,804.50 | 5,072.44 | 4,118.53 | 1,776.75 | 913.50 | 913.50 |
| `Map.replaceNat64` | replace-hit | 100,000 | 15,780.56 | 6,154.34 | 4,964.44 | 2,190.50 | 1,143.00 | 1,143.00 |
| `Map.replaceNat64` | replace-miss | 1,000 | 2,533.50 | 2,178.94 | 1,423.59 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 10,000 | 3,238.41 | 2,775.88 | 1,776.44 | 0.00 | 0.00 | 0.00 |
| `Map.replaceNat64` | replace-miss | 100,000 | 3,815.03 | 3,237.12 | 2,008.06 | 0.00 | 0.00 | 0.00 |

## Core baseline details

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

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).
