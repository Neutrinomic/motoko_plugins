| Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core/callback | Core/scalar |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| bulk-sorted | 256 | 2,110,975.00 | 226,621.00 | — | 9.32× | — |
| scan | 256 | 375,240.00 | 274,203.00 | — | 1.37× | — |
| range | 256 | 226,693.00 | 25,332.00 | — | 8.95× | — |
| filter-all | 256 | 2,106,897.00 | 84,443.00 | — | 24.95× | — |
| filter-half | 256 | 967,906.00 | 170,839.00 | — | 5.67× | — |
| union-small | 256 | 112,880.00 | 87,695.00 | — | 1.29× | — |
| intersection-small | 256 | 57,509.00 | 87,555.00 | — | 0.66× | — |
| difference-small | 256 | 108,042.00 | 95,261.00 | — | 1.13× | — |
| bulk-sorted | 4,096 | 50,348,835.00 | 3,621,677.00 | — | 13.90× | — |
| scan | 4,096 | 6,003,538.00 | 4,336,399.00 | — | 1.38× | — |
| range | 4,096 | 3,184,016.00 | 29,305.00 | — | 108.65× | — |
| filter-all | 4,096 | 50,298,725.00 | 1,331,531.00 | — | 37.78× | — |
| filter-half | 4,096 | 23,744,662.00 | 2,768,468.00 | — | 8.58× | — |
| union-small | 4,096 | 2,566,561.00 | 1,195,925.00 | — | 2.15× | — |
| intersection-small | 4,096 | 1,592,655.00 | 1,404,364.00 | — | 1.13× | — |
| difference-small | 4,096 | 2,548,958.00 | 1,502,129.00 | — | 1.70× | — |

Raw batch totals, allocation/op, reclamation/op, and trial ranges are in benchmarks/results/pure-map/bulk/summary.csv
