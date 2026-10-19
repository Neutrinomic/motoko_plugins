| Workload / phase | Before instr | After instr | Change | Before alloc B | After alloc B |
| --- | ---: | ---: | ---: | ---: | ---: |
| scalar-nat64 / icwire_encode | 2,347 | 2,218 | -5.50% | 312 | 328 |
| scalar-nat64 / icwire_decode | 1,211 | 1,059 | -12.55% | 200 | 216 |
| tiny-record / icwire_encode | 5,934 | 5,515 | -7.06% | 536 | 520 |
| tiny-record / icwire_decode | 5,030 | 4,817 | -4.23% | 480 | 496 |
| blob-0 / icwire_encode | 1,780 | 1,786 | +0.34% | 264 | 280 |
| blob-0 / icwire_decode | 1,394 | 1,411 | +1.22% | 224 | 240 |
| blob-32 / icwire_encode | 2,488 | 2,496 | +0.32% | 360 | 376 |
| blob-32 / icwire_decode | 1,426 | 1,443 | +1.19% | 256 | 272 |
| blob-1024 / icwire_encode | 4,472 | 4,480 | +0.18% | 2,344 | 2,360 |
| blob-1024 / icwire_decode | 2,418 | 2,435 | +0.70% | 1,248 | 1,264 |
| blob-65536 / icwire_encode | 613,496 | 613,504 | +0.00% | 131,368 | 131,384 |
| blob-65536 / icwire_decode | 386,930 | 386,947 | +0.00% | 65,760 | 65,776 |
| takt-event-0 / icwire_encode | 11,983 | 9,921 | -17.21% | 1,208 | 1,032 |
| takt-event-0 / icwire_decode | 10,269 | 9,663 | -5.90% | 592 | 608 |
| takt-event-32 / icwire_encode | 12,166 | 10,104 | -16.95% | 1,240 | 1,064 |
| takt-event-32 / icwire_decode | 10,301 | 9,695 | -5.88% | 624 | 640 |
| takt-event-1024 / icwire_encode | 14,923 | 12,863 | -13.80% | 3,424 | 3,248 |
| takt-event-1024 / icwire_decode | 11,293 | 10,687 | -5.37% | 1,616 | 1,632 |
| takt-event-65536 / icwire_encode | 623,947 | 621,887 | -0.33% | 132,448 | 132,272 |
| takt-event-65536 / icwire_decode | 395,805 | 395,199 | -0.15% | 66,128 | 66,144 |
| takt-child-32 / icwire_encode | 10,583 | 9,825 | -7.16% | 1,128 | 1,080 |
| takt-child-32 / icwire_decode | 10,035 | 9,770 | -2.64% | 712 | 728 |
| takt-child-1024 / icwire_encode | 13,340 | 12,584 | -5.67% | 3,328 | 3,280 |
| takt-child-1024 / icwire_decode | 11,027 | 10,762 | -2.40% | 1,704 | 1,720 |
| rechain-actions-1 / icwire_encode | 14,368 | 12,755 | -11.23% | 1,248 | 1,128 |
| rechain-actions-1 / icwire_decode | 19,727 | 14,184 | -28.10% | 1,000 | 872 |
| rechain-actions-32 / icwire_encode | 148,304 | 125,501 | -15.38% | 13,448 | 11,792 |
| rechain-actions-32 / icwire_decode | 316,612 | 262,271 | -17.16% | 8,960 | 7,680 |
| rechain-actions-1024 / icwire_encode | 5,980,057 | 5,266,880 | -11.93% | 412,328 | 361,072 |
| rechain-actions-1024 / icwire_decode | 8,057,656 | 6,478,475 | -19.60% | 266,880 | 229,888 |
| reactor-frames-1 / icwire_encode | 16,652 | 14,742 | -11.47% | 1,928 | 1,776 |
| reactor-frames-1 / icwire_decode | 22,420 | 16,670 | -25.65% | 1,184 | 1,056 |
| reactor-frames-64 / icwire_encode | 735,846 | 662,938 | -9.91% | 53,048 | 46,760 |
| reactor-frames-64 / icwire_decode | 976,303 | 870,625 | -10.82% | 29,480 | 27,192 |
| reactor-frames-1024 / icwire_encode | 11,266,070 | 9,922,594 | -11.92% | 840,536 | 740,168 |
| reactor-frames-1024 / icwire_decode | 13,186,463 | 11,487,193 | -12.89% | 463,544 | 426,552 |
| nat64-array-0 / icwire_encode | 1,710 | 1,719 | +0.53% | 264 | 280 |
| nat64-array-0 / icwire_decode | 1,305 | 1,309 | +0.31% | 224 | 240 |
| nat64-array-1 / icwire_encode | 2,560 | 2,434 | -4.92% | 312 | 328 |
| nat64-array-1 / icwire_decode | 1,698 | 1,546 | -8.95% | 232 | 248 |
| nat64-array-4096 / icwire_encode | 1,813,325 | 1,252,208 | -30.94% | 164,400 | 164,416 |
| nat64-array-4096 / icwire_decode | 1,771,033 | 1,132,061 | -36.08% | 32,992 | 33,008 |
| nested-options-1 / icwire_encode | 3,535 | 3,414 | -3.42% | 384 | 400 |
| nested-options-1 / icwire_decode | 2,972 | 2,820 | -5.11% | 456 | 472 |
| nested-options-1024 / icwire_encode | 6,391,621 | 5,822,312 | -8.91% | 332,592 | 299,840 |
| nested-options-1024 / icwire_decode | 8,089,347 | 7,791,495 | -3.68% | 194,968 | 194,984 |
Whole actor Wasm: 639,162 → 641,924 B.
Repeated control changes (retained heap/allocation placement can affect raw costs):
rechain-actions-1024/candid_encode: 2,748,618 → 2,908,618 instructions, 86,888 → 86,888 allocated B
reactor-frames-1024/candid_encode: 5,299,257 → 5,459,257 instructions, 214,344 → 214,344 allocated B
