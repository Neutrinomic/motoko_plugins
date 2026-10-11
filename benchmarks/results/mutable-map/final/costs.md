# Mutable map function costs

3-trial medians, normalized by the number of complete operations in each batch. Both implementations use the same compiler and inputs. Allocated bytes include temporary objects and retained results; they are not peak or live heap size. Core/plugin above 1 means fewer plugin instructions.

Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows measure cursor creation only; `consume` rows include creation and the entire map traversal; `seek16` rows include creation and 16 entries. Fold, transform, clone, clear, and construction rows measure the complete function call. Core adapters are listed below; see [methodology](README.md) for exact semantics and validation.

## Construction

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

## Operations on populated maps

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

## Scalar ordering on the same workloads

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
