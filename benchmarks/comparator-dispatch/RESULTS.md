# Automatic comparator dispatch results

Ordinary Map/Set calls using `Nat64.compare` now approach the explicit Nat64 helper path. At 100,000 entries, successful lookup saves **26–40% of the previous plugin instruction cost** and **63–72% of Core 2.5.0's cost**. The ratios are 1.34–1.66× and 2.74–3.59× respectively. No extra cumulative allocation was measured in any of the 84 matched before/after cases.

These are PocketIC instruction measurements, not elapsed-time estimates. The [methodology and commands](README.md) and [complete evidence index](../results/comparator-dispatch/README.md) describe the retained programs, sources, manifests and raw measurements.

## Ordinary lookup at 100,000 entries

Instructions and cumulative allocated bytes are per lookup, averaged over 32 successful lookups. All plugin paths in this table allocate zero bytes. Explicit Nat64 is a measured scalar reference path, not a theoretical lower bound.

| Container | Core instructions | Before | Automatic | Explicit Nat64 | Before / automatic | Core / automatic | Core / automatic allocated bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Mutable Map | 7,242.72 | 3,556.09 | 2,648.03 | 2,590.03 | 1.34× | 2.74× | 117 / 0 |
| Pure Map | 3,034.47 | 1,466.53 | 962.28 | 904.28 | 1.52× | 3.15× | 0 / 0 |
| Mutable Set | 6,945.38 | 3,346.47 | 2,325.91 | 2,267.91 | 1.44× | 2.99× | 117 / 0 |
| Pure Set | 2,754.91 | 1,272.53 | 768.28 | 710.28 | 1.66× | 3.59× | 40 / 0 |

## Costs and limits

- At every measured nonempty size (1k, 10k, 100k), ordinary successful lookup costs **58 instructions more** than its explicit Nat64 helper. This is the total API-path difference, including dispatch; the experiment does not isolate the classifier alone.
- An alias stored in a record matches the direct comparator result exactly. A generic forwarding helper retains the optimization, with its own small call overhead. Custom, reversed and effectful comparators preserve callback behavior.
- Empty-tree calls cost **32–35 additional instructions** after the change; singleton calls improve by **40–49 instructions**. These fixed costs matter most when there is little tree work.
- In the main custom/reversed/effectful cases, the compiler emits no `plugin_comparator_kind` helper. These unknown-only paths cost **9 additional instructions per lookup**, with unchanged allocation. The separate mixed-identity probe below measures canisters that do contain the classifier.
- Allocation means cumulative `totalAllocatedBytes`, including temporary garbage, rather than retained or peak heap. All 84 matched cases have identical before/after allocation. Zero-allocation claims above apply to the 100k lookup rows; some other rows allocate, as shown in the full tables.
- This matrix measures shuffled Nat64 keys (including both halves of the unsigned range), Nat map values, and these four operations. It does not establish the same ratios for other key types, tree shapes or callback workloads.

## Mixed comparator identities

Each of these 10k canisters can select either a standard comparator or a captured callback through a runtime configuration method. Both identities are materialized, and emitted Wasm contains `plugin_comparator_kind`. Comparator selection occurs outside the measured loop. The retained [Wasm inspection](../results/comparator-dispatch/classifier-inspection.json) checks artifact hashes before counting helper definitions and static call sites.

| Container | Standard selected: instructions / lookup | Callback selected: instructions / lookup | Allocated bytes / lookup | Complete canister bytes |
|---|---:|---:|---:|---:|
| Mutable Map | 2,068.75 | 3,254.28 | 0 | 275,501 |
| Pure Map | 831.03 | 1,548.31 | 0 | 264,102 |
| Mutable Set | 1,762.00 | 3,021.97 | 0 | 273,799 |
| Pure Set | 637.03 | 1,354.31 | 0 | 260,248 |

The callback-selected path is 8 instructions per 32-lookups batch (0.25 per lookup) above the main captured-callback case. The standard-selected path is 728 instructions per batch (22.75 per lookup) below the main direct case. The mixed program hoists the selected function value outside the loop and has a different complete call path: neither difference is an isolated classifier cost.

## Emitted Wasm size

Across all 84 matched programs, the complete canister grows by **0.059–3.395%**. The largest increase is **9,389 bytes**, in mutable Map deletion. For ordinary direct-API programs only, the range is **0.270–3.395%**. These files include the RTS, Ash harness, setup and validation, so the values are not standalone plugin payload sizes.

| Ordinary 10k lookup | Before bytes | After bytes | Increase |
|---|---:|---:|---:|
| Mutable Map | 265,867 | 271,837 | 2.25% |
| Pure Map | 258,334 | 260,463 | 0.82% |
| Mutable Set | 264,679 | 270,109 | 2.05% |
| Pure Set | 255,474 | 256,618 | 0.45% |

## Reproducibility and compiler identity

**864 independent samples** were recorded: baseline 84 cases × 3 trials, candidate 196 × 3, and mixed 8 × 3. All three trials have identical instruction counts, cumulative allocations, and emitted Wasm hashes for each case. Four independent cases run concurrently within a trial; each trial finishes before the next starts. Each case uses a fresh canister and separate PocketIC instance. Inputs/setup and full-result validation are outside the measured closure.

The comparison verifier checks byte-identical common generated programs, public wrapper modules, metrics harness, Core sources, RTS, Ash sources, PocketIC and didc binaries. Compiler/native artifacts intentionally differ. Core and explicit-helper references are measured with the candidate compiler.

Exact reruns require the recorded unpublished local Ash sources, including `mocArgs` support. Their hashes are retained, but the CLI source modifications are not archived here; the repository alone cannot reconstruct that exact checkout.

The candidate binary is SHA-256 `6392a9fe6dca57a707bca5670bb4fdf67dd4cafcd03ba9228dd44d158a887546`. All 292 compiler-source hashes recorded in each of the four native build manifests match compiler commit `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`; see the [source verification record](../results/comparator-dispatch/compiler-source-verification.json). Its `--version` banner still reports `source 2.0.0-13-gfc7612098` because the build retained cached `source_id` text. The exact binary and source hashes identify the measured candidate; the banner alone does not. The recorded dirty flags are retained honestly. Source-hash verification is not an independent reproducible compiler rebuild.

The preserved baseline compiler is SHA-256 `800ab820f06e127259f62ce5fdc68d39249a420547d717fa869182c8d60262ec`, from commit `fc7612098196031d1b1c42345f3279b5928c5071`; baseline native sources come from plugins commit `f5ae694f61a6121d4a5355ee0941edc98e6e8ffd`. Candidate captures identify plugins commit `c602651ebfdc112952882dae99df5dd1e0072296`. The common public wrappers were frozen before both phases; native build manifests preserve their earlier build-time revision and actual source hashes.

## Full operation and comparator tables

The following tables are generated directly by the strict archive verifier. A dash means that reference was not part of that case. `direct` denotes the ordinary API; custom/reversed/effectful rows use fallback callbacks. Build rows report the entire build, while other rows report per-operation averages.

Cells show IC instructions / cumulative allocated bytes per operation, followed by complete canister Wasm bytes. Point rows average 32 probes; empty/singleton rows use one. Build measures the whole shuffled build. Setup and full-content validation are excluded. Wasm includes the RTS, harness and validation.

Candidate: 196 cases × 3 independent trials; identical instruction/allocation counts: True; identical emitted Wasm: True.

Baseline: 84 cases × 3 independent trials.

### mutable-map

| Size | Operation / comparator | Core 2.5.0 | Before | Automatic / fallback | Explicit Nat64 |
|---:|---|---:|---:|---:|---:|
| 0 | insert-new / direct | — | 3,340.00 / 408.00; 264,018 | 3,375.00 / 408.00; 269,121 | 3,314.00 / 408.00; 263,633 |
| 0 | lookup-miss / direct | — | 819.00 / 0.00; 265,717 | 851.00 / 0.00; 271,687 | 793.00 / 0.00; 265,309 |
| 1 | insert-new / direct | — | 3,932.00 / 256.00; 264,022 | 3,892.00 / 256.00; 269,125 | 3,831.00 / 256.00; 263,637 |
| 1 | lookup-miss / direct | — | 3,465.00 / 216.00; 265,721 | 3,422.00 / 216.00; 271,691 | 3,364.00 / 216.00; 265,313 |
| 1,000 | build / direct | 9,397,063.00 / 338,152.00; 277,867 | 5,046,719.00 / 198,520.00; 263,226 | 4,530,885.00 / 198,520.00; 268,331 | 4,469,885.00 / 198,520.00; 262,846 |
| 1,000 | delete-present / direct | 10,335.53 / 370.00; 313,095 | 3,757.25 / 0.00; 276,566 | 3,218.28 / 0.00; 285,955 | 3,158.28 / 0.00; 276,158 |
| 1,000 | insert-new / direct | 9,667.31 / 368.00; 278,667 | 4,933.72 / 159.50; 264,029 | 4,297.31 / 159.50; 269,132 | 4,236.31 / 159.50; 263,644 |
| 1,000 | lookup-hit / direct | 5,248.91 / 119.00; 281,428 | 2,640.78 / 27.00; 265,865 | 2,144.28 / 27.00; 271,835 | 2,086.28 / 27.00; 265,457 |
| 10,000 | build / direct | 111,476,363.00 / 3,811,416.00; 277,869 | 58,605,760.00 / 1,978,424.00; 263,228 | 51,352,910.00 / 1,978,424.00; 268,333 | 50,742,910.00 / 1,978,424.00; 262,848 |
| 10,000 | delete-present / direct | 11,219.53 / 383.50; 313,097 | 3,932.31 / 0.00; 276,568 | 3,192.78 / 0.00; 285,957 | 3,132.78 / 0.00; 276,160 |
| 10,000 | insert-new / direct | 11,026.69 / 368.00; 278,670 | 5,597.78 / 171.00; 264,032 | 4,743.41 / 171.00; 269,135 | 4,682.41 / 171.00; 263,647 |
| 10,000 | lookup-hit / direct | 5,712.09 / 89.00; 281,430 | 2,767.53 / 0.00; 265,867 | 2,091.50 / 0.00; 271,837 | 2,033.50 / 0.00; 265,459 |
| 10,000 | lookup-hit / alias | — | 2,767.53 / 0.00; 265,867 | 2,091.50 / 0.00; 271,837 | — |
| 10,000 | lookup-hit / custom | — | 3,245.03 / 0.00; 266,042 | 3,254.03 / 0.00; 266,224 | — |
| 10,000 | lookup-hit / effectful | — | 4,068.72 / 0.00; 266,114 | 4,077.72 / 0.00; 266,296 | — |
| 10,000 | lookup-hit / generic | — | 2,778.53 / 0.00; 265,952 | 2,102.50 / 0.00; 271,923 | — |
| 10,000 | lookup-hit / reversed | — | 2,830.28 / 0.00; 265,908 | 2,839.28 / 0.00; 266,090 | — |
| 100,000 | build / direct | 1,290,404,865.00 / 43,932,552.00; 277,869 | 670,832,153.00 / 19,771,912.00; 263,228 | 577,011,796.00 / 19,771,912.00; 268,333 | 570,911,796.00 / 19,771,912.00; 262,848 |
| 100,000 | delete-present / direct | 13,967.62 / 542.25; 313,097 | 5,409.91 / 0.00; 276,568 | 4,429.91 / 0.00; 285,957 | 4,369.91 / 0.00; 276,160 |
| 100,000 | insert-new / direct | 12,612.94 / 432.00; 278,670 | 6,775.72 / 171.00; 264,032 | 5,689.88 / 171.00; 269,135 | 5,628.88 / 171.00; 263,647 |
| 100,000 | lookup-hit / direct | 7,242.72 / 117.00; 281,430 | 3,556.09 / 0.00; 265,867 | 2,648.03 / 0.00; 271,837 | 2,590.03 / 0.00; 265,459 |

### mutable-set

| Size | Operation / comparator | Core 2.5.0 | Before | Automatic / fallback | Explicit Nat64 |
|---:|---|---:|---:|---:|---:|
| 0 | insert-new / direct | — | 3,089.00 / 368.00; 263,539 | 3,123.00 / 368.00; 268,478 | 3,057.00 / 368.00; 262,854 |
| 0 | lookup-miss / direct | — | 658.00 / 0.00; 264,529 | 690.00 / 0.00; 269,959 | 632.00 / 0.00; 263,822 |
| 1 | insert-new / direct | — | 1,401.00 / 0.00; 263,543 | 1,354.00 / 0.00; 268,482 | 1,268.00 / 0.00; 262,858 |
| 1 | lookup-miss / direct | — | 1,004.00 / 0.00; 264,533 | 955.00 / 0.00; 269,963 | 897.00 / 0.00; 263,826 |
| 1,000 | build / direct | 7,868,336.00 / 135,336.00; 278,339 | 3,680,285.00 / 34,520.00; 262,874 | 3,051,530.00 / 34,520.00; 267,815 | 2,975,530.00 / 34,520.00; 262,194 |
| 1,000 | delete-present / direct | 9,930.38 / 265.00; 311,841 | 3,791.12 / 0.00; 276,329 | 3,180.53 / 0.00; 285,542 | 3,120.53 / 0.00; 275,498 |
| 1,000 | insert-new / direct | 8,138.78 / 158.00; 279,012 | 3,656.81 / 11.50; 263,550 | 2,853.94 / 11.50; 268,489 | 2,777.94 / 11.50; 262,865 |
| 1,000 | lookup-hit / direct | 4,653.69 / 92.00; 280,891 | 2,121.31 / 0.00; 264,677 | 1,560.03 / 0.00; 270,107 | 1,502.03 / 0.00; 263,970 |
| 10,000 | build / direct | 95,730,840.00 / 1,568,792.00; 278,341 | 45,268,613.00 / 338,424.00; 262,876 | 36,424,865.00 / 338,424.00; 267,817 | 35,664,865.00 / 338,424.00; 262,196 |
| 10,000 | delete-present / direct | 10,791.53 / 271.75; 311,843 | 3,961.12 / 0.00; 276,331 | 3,140.78 / 0.00; 285,544 | 3,080.78 / 0.00; 275,500 |
| 10,000 | insert-new / direct | 9,525.56 / 158.00; 279,015 | 4,369.62 / 23.00; 263,553 | 3,286.91 / 23.00; 268,492 | 3,210.91 / 23.00; 262,868 |
| 10,000 | lookup-hit / direct | 5,410.94 / 89.00; 280,893 | 2,535.22 / 0.00; 264,679 | 1,784.75 / 0.00; 270,109 | 1,726.75 / 0.00; 263,972 |
| 10,000 | lookup-hit / alias | — | 2,535.22 / 0.00; 264,679 | 1,784.75 / 0.00; 270,109 | — |
| 10,000 | lookup-hit / custom | — | 3,012.72 / 0.00; 264,855 | 3,021.72 / 0.00; 265,027 | — |
| 10,000 | lookup-hit / effectful | — | 3,836.41 / 0.00; 264,927 | 3,845.41 / 0.00; 265,099 | — |
| 10,000 | lookup-hit / generic | — | 2,545.22 / 0.00; 264,744 | 1,794.75 / 0.00; 270,203 | — |
| 10,000 | lookup-hit / reversed | — | 2,595.16 / 0.00; 264,721 | 2,604.16 / 0.00; 264,893 | — |
| 100,000 | build / direct | 1,125,373,564.00 / 18,624,968.00; 278,341 | 540,826,716.00 / 3,371,912.00; 262,876 | 426,381,283.00 / 3,371,912.00; 267,817 | 418,781,283.00 / 3,371,912.00; 262,196 |
| 100,000 | delete-present / direct | 13,422.72 / 392.75; 311,843 | 5,461.91 / 0.00; 276,331 | 4,361.53 / 0.00; 285,544 | 4,301.53 / 0.00; 275,500 |
| 100,000 | insert-new / direct | 11,050.12 / 190.00; 279,015 | 5,591.50 / 23.00; 263,553 | 4,220.50 / 23.00; 268,492 | 4,144.50 / 23.00; 262,868 |
| 100,000 | lookup-hit / direct | 6,945.38 / 117.00; 280,893 | 3,346.47 / 0.00; 264,679 | 2,325.91 / 0.00; 270,109 | 2,267.91 / 0.00; 263,972 |

### pure-map

| Size | Operation / comparator | Core 2.5.0 | Before | Automatic / fallback | Explicit Nat64 |
|---:|---|---:|---:|---:|---:|
| 0 | insert-new / direct | — | 949.00 / 72.00; 256,706 | 982.00 / 72.00; 258,175 | 923.00 / 72.00; 256,037 |
| 0 | lookup-miss / direct | — | 765.00 / 0.00; 258,184 | 797.00 / 0.00; 260,313 | 739.00 / 0.00; 257,510 |
| 1 | insert-new / direct | — | 3,760.00 / 360.00; 256,710 | 3,718.00 / 360.00; 258,179 | 3,659.00 / 360.00; 256,041 |
| 1 | lookup-miss / direct | — | 3,208.00 / 216.00; 258,188 | 3,165.00 / 216.00; 260,317 | 3,107.00 / 216.00; 257,514 |
| 1,000 | build / direct | 9,448,166.00 / 1,661,176.00; 261,327 | 6,780,154.00 / 903,200.00; 255,871 | 6,238,706.00 / 903,200.00; 257,354 | 6,179,706.00 / 903,200.00; 255,207 |
| 1,000 | delete-present / direct | 10,137.38 / 2,057.75; 273,184 | 4,700.75 / 634.50; 258,630 | 4,319.00 / 634.50; 261,183 | 4,261.00 / 634.50; 257,963 |
| 1,000 | insert-new / direct | 11,219.34 / 1,943.25; 262,160 | 8,222.78 / 1,059.75; 256,718 | 7,469.19 / 1,059.75; 258,187 | 7,410.19 / 1,059.75; 256,049 |
| 1,000 | lookup-hit / direct | 2,104.53 / 27.00; 264,439 | 1,517.53 / 27.00; 258,332 | 1,127.97 / 27.00; 260,461 | 1,069.97 / 27.00; 257,658 |
| 10,000 | build / direct | 116,772,053.00 / 20,562,632.00; 261,329 | 86,099,821.00 / 11,421,896.00; 255,873 | 78,552,396.00 / 11,421,896.00; 257,356 | 77,962,396.00 / 11,421,896.00; 255,209 |
| 10,000 | delete-present / direct | 13,688.62 / 2,794.00; 273,187 | 6,198.81 / 884.25; 258,633 | 5,799.03 / 884.25; 261,186 | 5,741.03 / 884.25; 257,966 |
| 10,000 | insert-new / direct | 13,122.12 / 2,292.25; 262,164 | 10,049.19 / 1,296.00; 256,722 | 9,072.91 / 1,296.00; 258,191 | 9,013.91 / 1,296.00; 256,053 |
| 10,000 | lookup-hit / direct | 2,449.75 / 0.00; 264,441 | 1,250.31 / 0.00; 258,334 | 853.78 / 0.00; 260,463 | 795.78 / 0.00; 257,660 |
| 10,000 | lookup-hit / alias | — | 1,250.31 / 0.00; 258,334 | 853.78 / 0.00; 260,463 | — |
| 10,000 | lookup-hit / custom | — | 1,539.06 / 0.00; 258,510 | 1,548.06 / 0.00; 258,669 | — |
| 10,000 | lookup-hit / effectful | — | 2,037.16 / 0.00; 258,582 | 2,046.16 / 0.00; 258,741 | — |
| 10,000 | lookup-hit / generic | — | 1,261.31 / 0.00; 258,411 | 864.78 / 0.00; 260,543 | — |
| 10,000 | lookup-hit / reversed | — | 1,397.78 / 0.00; 258,376 | 1,406.78 / 0.00; 258,535 | — |
| 100,000 | build / direct | 1,391,664,023.00 / 245,172,128.00; 261,329 | 1,041,090,673.00 / 137,997,752.00; 255,873 | 945,127,031.00 / 137,997,752.00; 257,356 | 939,227,031.00 / 137,997,752.00; 255,209 |
| 100,000 | delete-present / direct | 16,611.88 / 3,367.00; 273,187 | 8,200.91 / 1,190.25; 258,633 | 7,696.66 / 1,190.25; 261,186 | 7,638.66 / 1,190.25; 257,966 |
| 100,000 | insert-new / direct | 16,532.78 / 2,850.75; 262,164 | 12,237.84 / 1,584.00; 256,722 | 10,989.75 / 1,584.00; 258,191 | 10,930.75 / 1,584.00; 256,053 |
| 100,000 | lookup-hit / direct | 3,034.47 / 0.00; 264,441 | 1,466.53 / 0.00; 258,334 | 962.28 / 0.00; 260,463 | 904.28 / 0.00; 257,660 |

### pure-set

| Size | Operation / comparator | Core 2.5.0 | Before | Automatic / fallback | Explicit Nat64 |
|---:|---|---:|---:|---:|---:|
| 0 | insert-new / direct | — | 819.00 / 64.00; 254,416 | 851.00 / 64.00; 255,104 | 793.00 / 64.00; 253,756 |
| 0 | lookup-miss / direct | — | 611.00 / 0.00; 255,324 | 643.00 / 0.00; 256,468 | 585.00 / 0.00; 254,659 |
| 1 | insert-new / direct | — | 1,308.00 / 128.00; 254,420 | 1,265.00 / 128.00; 255,108 | 1,207.00 / 128.00; 253,760 |
| 1 | lookup-miss / direct | — | 752.00 / 0.00; 255,328 | 709.00 / 0.00; 256,472 | 651.00 / 0.00; 254,663 |
| 1,000 | build / direct | 7,582,917.00 / 1,359,600.00; 259,332 | 5,261,601.00 / 694,400.00; 253,722 | 4,719,153.00 / 694,400.00; 254,410 | 4,661,153.00 / 694,400.00; 253,067 |
| 1,000 | delete-present / direct | 9,812.94 / 1,922.00; 270,143 | 4,553.03 / 564.00; 255,942 | 4,171.28 / 564.00; 257,241 | 4,113.28 / 564.00; 255,276 |
| 1,000 | insert-new / direct | 9,330.41 / 1,632.00; 260,038 | 6,695.41 / 846.00; 254,428 | 5,940.81 / 846.00; 255,116 | 5,882.81 / 846.00; 253,768 |
| 1,000 | lookup-hit / direct | 1,648.97 / 40.00; 261,718 | 1,033.03 / 0.00; 255,472 | 643.47 / 0.00; 256,616 | 585.47 / 0.00; 254,807 |
| 10,000 | build / direct | 97,352,815.00 / 17,275,120.00; 259,334 | 70,247,229.00 / 9,068,352.00; 253,724 | 62,689,804.00 / 9,068,352.00; 254,412 | 62,109,804.00 / 9,068,352.00; 253,069 |
| 10,000 | delete-present / direct | 13,247.59 / 2,602.00; 270,146 | 5,995.62 / 786.00; 255,945 | 5,595.84 / 786.00; 257,244 | 5,537.84 / 786.00; 255,279 |
| 10,000 | insert-new / direct | 11,164.91 / 1,959.50; 260,042 | 8,455.91 / 1,056.00; 254,432 | 7,478.62 / 1,056.00; 255,120 | 7,420.62 / 1,056.00; 253,772 |
| 10,000 | lookup-hit / direct | 2,211.31 / 40.00; 261,720 | 1,056.31 / 0.00; 255,474 | 659.78 / 0.00; 256,618 | 601.78 / 0.00; 254,809 |
| 10,000 | lookup-hit / alias | — | 1,056.31 / 0.00; 255,474 | 659.78 / 0.00; 256,618 | — |
| 10,000 | lookup-hit / custom | — | 1,345.06 / 0.00; 255,651 | 1,354.06 / 0.00; 255,801 | — |
| 10,000 | lookup-hit / effectful | — | 1,843.16 / 0.00; 255,723 | 1,852.16 / 0.00; 255,873 | — |
| 10,000 | lookup-hit / generic | — | 1,066.31 / 0.00; 255,540 | 669.78 / 0.00; 256,682 | — |
| 10,000 | lookup-hit / reversed | — | 1,203.78 / 0.00; 255,517 | 1,212.78 / 0.00; 255,667 | — |
| 100,000 | build / direct | 1,189,725,653.00 / 209,554,560.00; 259,334 | 875,946,319.00 / 111,820,224.00; 253,724 | 779,882,677.00 / 111,820,224.00; 254,412 | 774,082,677.00 / 111,820,224.00; 253,069 |
| 100,000 | delete-present / direct | 16,071.47 / 3,130.75; 270,146 | 7,942.91 / 1,058.00; 255,945 | 7,438.66 / 1,058.00; 257,244 | 7,380.66 / 1,058.00; 255,279 |
| 100,000 | insert-new / direct | 14,445.94 / 2,474.50; 260,042 | 10,565.97 / 1,312.00; 254,432 | 9,316.88 / 1,312.00; 255,120 | 9,258.88 / 1,312.00; 253,772 |
| 100,000 | lookup-hit / direct | 2,754.91 / 40.00; 261,720 | 1,272.53 / 0.00; 255,474 | 768.28 / 0.00; 256,618 | 710.28 / 0.00; 254,809 |
