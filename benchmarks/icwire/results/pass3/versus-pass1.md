| Workload / phase | Before instr | After instr | Change | Before alloc B | After alloc B |
| --- | ---: | ---: | ---: | ---: | ---: |
| scalar-nat64 / icwire_encode | 2,347 | 679 | -71.07% | 312 | 72 |
| scalar-nat64 / icwire_decode | 1,211 | 1,033 | -14.70% | 200 | 216 |
| tiny-record / icwire_encode | 5,934 | 1,654 | -72.13% | 536 | 120 |
| tiny-record / icwire_decode | 5,030 | 4,411 | -12.31% | 480 | 496 |
| blob-0 / icwire_encode | 1,780 | 798 | -55.17% | 264 | 64 |
| blob-0 / icwire_decode | 1,394 | 1,361 | -2.37% | 224 | 240 |
| blob-32 / icwire_encode | 2,488 | 830 | -66.64% | 360 | 96 |
| blob-32 / icwire_decode | 1,426 | 1,393 | -2.31% | 256 | 272 |
| blob-1024 / icwire_encode | 4,472 | 1,822 | -59.26% | 2,344 | 1,088 |
| blob-1024 / icwire_decode | 2,418 | 2,385 | -1.36% | 1,248 | 1,264 |
| blob-65536 / icwire_encode | 613,496 | 386,334 | -37.03% | 131,368 | 65,600 |
| blob-65536 / icwire_decode | 386,930 | 386,897 | -0.01% | 65,760 | 65,776 |
| takt-event-0 / icwire_encode | 11,983 | 3,726 | -68.91% | 1,208 | 200 |
| takt-event-0 / icwire_decode | 10,269 | 8,687 | -15.41% | 592 | 608 |
| takt-event-32 / icwire_encode | 12,166 | 3,758 | -69.11% | 1,240 | 232 |
| takt-event-32 / icwire_decode | 10,301 | 8,719 | -15.36% | 624 | 640 |
| takt-event-1024 / icwire_encode | 14,923 | 4,750 | -68.17% | 3,424 | 1,224 |
| takt-event-1024 / icwire_decode | 11,293 | 9,711 | -14.01% | 1,616 | 1,632 |
| takt-event-65536 / icwire_encode | 623,947 | 389,262 | -37.61% | 132,448 | 65,736 |
| takt-event-65536 / icwire_decode | 395,805 | 394,223 | -0.40% | 66,128 | 66,144 |
| takt-child-32 / icwire_encode | 10,583 | 3,288 | -68.93% | 1,128 | 248 |
| takt-child-32 / icwire_decode | 10,035 | 8,984 | -10.47% | 712 | 728 |
| takt-child-1024 / icwire_encode | 13,340 | 4,280 | -67.92% | 3,328 | 1,240 |
| takt-child-1024 / icwire_decode | 11,027 | 9,976 | -9.53% | 1,704 | 1,720 |
| rechain-actions-1 / icwire_encode | 14,368 | 5,740 | -60.05% | 1,248 | 296 |
| rechain-actions-1 / icwire_decode | 19,727 | 13,173 | -33.22% | 1,000 | 872 |
| rechain-actions-32 / icwire_encode | 148,304 | 68,024 | -54.13% | 13,448 | 3,184 |
| rechain-actions-32 / icwire_decode | 316,612 | 248,212 | -21.60% | 8,960 | 7,680 |
| rechain-actions-1024 / icwire_encode | 5,980,057 | 2,989,752 | -50.00% | 412,328 | 98,392 |
| rechain-actions-1024 / icwire_decode | 8,057,656 | 6,038,600 | -25.06% | 266,880 | 229,888 |
| reactor-frames-1 / icwire_encode | 16,652 | 5,954 | -64.24% | 1,928 | 408 |
| reactor-frames-1 / icwire_decode | 22,420 | 15,515 | -30.80% | 1,184 | 1,056 |
| reactor-frames-64 / icwire_encode | 735,846 | 294,812 | -59.94% | 53,048 | 13,528 |
| reactor-frames-64 / icwire_decode | 976,303 | 654,521 | -32.96% | 29,480 | 27,192 |
| reactor-frames-1024 / icwire_encode | 11,266,070 | 5,426,108 | -51.84% | 840,536 | 215,320 |
| reactor-frames-1024 / icwire_decode | 13,186,463 | 10,591,809 | -19.68% | 463,544 | 426,552 |
| nat64-array-0 / icwire_encode | 1,710 | 742 | -56.61% | 264 | 64 |
| nat64-array-0 / icwire_decode | 1,305 | 1,438 | +10.19% | 224 | 240 |
| nat64-array-1 / icwire_encode | 2,560 | 777 | -69.65% | 312 | 72 |
| nat64-array-1 / icwire_decode | 1,698 | 1,494 | -12.01% | 232 | 248 |
| nat64-array-4096 / icwire_encode | 1,813,325 | 224,102 | -87.64% | 164,400 | 32,832 |
| nat64-array-4096 / icwire_decode | 1,771,033 | 362,149 | -79.55% | 32,992 | 33,008 |
| nested-options-1 / icwire_encode | 3,535 | 1,058 | -70.07% | 384 | 88 |
| nested-options-1 / icwire_decode | 2,972 | 2,742 | -7.74% | 456 | 472 |
| nested-options-1024 / icwire_encode | 6,391,621 | 3,898,987 | -39.00% | 332,592 | 133,440 |
| nested-options-1024 / icwire_decode | 8,089,347 | 7,654,680 | -5.37% | 194,968 | 194,984 |
Whole actor Wasm: 639,162 → 697,872 B.
Repeated control changes (retained heap/allocation placement can affect raw costs):
rechain-actions-1024/candid_encode: 2,748,618 → 2,908,618 instructions, 86,888 → 86,888 allocated B
reactor-frames-64/candid_encode: 457,505 → 297,505 instructions, 13,800 → 13,800 allocated B
reactor-frames-64/candidx_encode: 1,084,491 → 924,491 instructions, 16,584 → 16,584 allocated B
reactor-frames-64/candid_decode: 1,015,917 → 855,917 instructions, 29,264 → 29,264 allocated B
reactor-frames-64/candidx_decode: 1,094,909 → 934,909 instructions, 29,264 → 29,264 allocated B
reactor-frames-1024/candid_encode: 5,299,257 → 5,459,257 instructions, 214,344 → 214,344 allocated B
nested-options-1024/candidx_decode: 8,264,682 → 8,257,447 instructions, 195,392 → 194,672 allocated B
