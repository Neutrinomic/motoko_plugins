Three-trial medians per complete operation. Cursor consume includes creation and traversal; creation retains the cursor for later validation. Allocated bytes include temporary garbage and retained results, not peak or live heap. All Core counts are unchanged between builds.

| Workload | Size | Core instructions | Before instructions | After instructions | Core allocated B | Before allocated B | After allocated B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| get-hit | 1 | 542.67 | 465.67 | 463.67 | 0.00 | 0.00 | 0.00 |
| get-miss | 1 | 619.67 | 495.67 | 488.67 | 0.00 | 0.00 | 0.00 |
| get-hit | 16 | 970.92 | 808.86 | 794.67 | 0.00 | 0.00 | 0.00 |
| get-miss | 16 | 1,153.17 | 932.61 | 909.67 | 0.00 | 0.00 | 0.00 |

[CSV](comparison.csv) includes scalar paths, raw batch totals, allocation and reclamation changes.
