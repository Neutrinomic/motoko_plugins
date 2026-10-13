Measured medians [minimum–maximum] from three fresh canisters per case.

Allocation is cumulative bytes allocated during the measured operation. Payload is the prepared object's declared byte payload.

Preparation is measured separately; prepared calls reuse a key created outside the timed interval.

| Workload | Mode | Instructions | Allocated bytes | Payload bytes | Canister Wasm bytes |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2 | direct | 949,824,696 [949,824,696–949,824,696] | 138,824 [138,824–138,824] | 0 | 851,462 |
| bls12-381-aggregate-ethereum-distinct-n2 | prepare | 572,812,094 [572,812,094–572,812,094] | 78,872 [78,872–78,872] | 288 | 855,207 |
| bls12-381-aggregate-ethereum-distinct-n2 | prepared | 377,014,114 [377,014,114–377,014,114] | 60,600 [60,600–60,600] | 288 | 855,504 |
| bls12-381-aggregate-ethereum-distinct-n8 | direct | 3,285,303,573 [3,285,303,573–3,285,303,573] | 494,840 [494,840–494,840] | 0 | 854,312 |
| bls12-381-aggregate-ethereum-distinct-n8 | prepare | 2,291,247,278 [2,291,247,278–2,291,247,278] | 315,416 [315,416–315,416] | 1,152 | 871,566 |
| bls12-381-aggregate-ethereum-distinct-n8 | prepared | 994,060,838 [994,060,838–994,060,838] | 181,552 [181,552–181,552] | 1,152 | 871,878 |
| bls12-381-aggregate-ethereum-repeated-n8 | direct | 565,078,557 [565,078,557–565,078,557] | 82,680 [82,680–82,680] | 0 | 851,197 |
| bls12-381-aggregate-ethereum-repeated-n8 | prepare | 286,406,258 [286,406,258–286,406,258] | 39,504 [39,504–39,504] | 144 | 852,891 |
| bls12-381-aggregate-ethereum-repeated-n8 | prepared | 278,645,699 [278,645,699–278,645,699] | 43,904 [43,904–43,904] | 144 | 853,269 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | direct | 565,078,557 [565,078,557–565,078,557] | 82,680 [82,680–82,680] | 0 | 851,197 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | prepare | 2,291,247,278 [2,291,247,278–2,291,247,278] | 315,416 [315,416–315,416] | 1,152 | 868,389 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | prepared | 278,645,699 [278,645,699–278,645,699] | 43,904 [43,904–43,904] | 1,152 | 868,698 |
| bls12-381-aggregate-ic-distinct-n2 | direct | 310,532,835 [310,532,835–310,532,835] | 40,552 [40,552–40,552] | 0 | 850,664 |
| bls12-381-aggregate-ic-distinct-n2 | prepare | 99,985,582 [99,985,582–99,985,582] | 39,512 [39,512–39,512] | 39,360 | 854,388 |
| bls12-381-aggregate-ic-distinct-n2 | prepared | 210,626,139 [210,626,139–210,626,139] | 544 [544–544] | 39,360 | 854,709 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | direct | 850,994,532 [850,994,532–850,994,532] | 118,064 [118,064–118,064] | 0 | 850,942 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | prepare | 572,812,094 [572,812,094–572,812,094] | 78,872 [78,872–78,872] | 288 | 854,687 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | prepared | 278,183,952 [278,183,952–278,183,952] | 39,840 [39,840–39,840] | 288 | 854,985 |
| bls12-381-verify-ethereum-official | direct | 286,405,944 [286,405,944–286,405,944] | 39,280 [39,280–39,280] | 0 | 848,194 |
| bls12-381-verify-ethereum-official | prepare | 12,239,690 [12,239,690–12,239,690] | 200 [200–200] | 144 | 850,316 |
| bls12-381-verify-ethereum-official | prepared | 274,167,416 [274,167,416–274,167,416] | 39,280 [39,280–39,280] | 144 | 850,687 |
| bls12-381-verify-ic-certificate | direct | 222,072,725 [222,072,725–222,072,725] | 19,672 [19,672–19,672] | 0 | 848,208 |
| bls12-381-verify-ic-certificate | prepare | 49,992,831 [49,992,831–49,992,831] | 19,736 [19,736–19,736] | 19,680 | 850,331 |
| bls12-381-verify-ic-certificate | prepared | 172,121,515 [172,121,515–172,121,515] | 64 [64–64] | 19,680 | 850,702 |

Instruction models below use only the measured reuse=1 medians: direct = N×D; prepared = P+N×H. They are arithmetic projections, not measured batch timings. Break-even is the first integer N with a strict saving.

| Workload | First cheaper reuse | N | Direct model | Prepared model |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2 | 2 | 1 | 949,824,696 | 949,826,208 |
| bls12-381-aggregate-ethereum-distinct-n2 | 2 | 2 | 1,899,649,392 | 1,326,840,322 |
| bls12-381-aggregate-ethereum-distinct-n2 | 2 | 10 | 9,498,246,960 | 4,342,953,234 |
| bls12-381-aggregate-ethereum-distinct-n2 | 2 | 100 | 94,982,469,600 | 38,274,223,494 |
| bls12-381-aggregate-ethereum-distinct-n8 | 2 | 1 | 3,285,303,573 | 3,285,308,116 |
| bls12-381-aggregate-ethereum-distinct-n8 | 2 | 2 | 6,570,607,146 | 4,279,368,954 |
| bls12-381-aggregate-ethereum-distinct-n8 | 2 | 10 | 32,853,035,730 | 12,231,855,658 |
| bls12-381-aggregate-ethereum-distinct-n8 | 2 | 100 | 328,530,357,300 | 101,697,331,078 |
| bls12-381-aggregate-ethereum-repeated-n8 | 1 | 1 | 565,078,557 | 565,051,957 |
| bls12-381-aggregate-ethereum-repeated-n8 | 1 | 2 | 1,130,157,114 | 843,697,656 |
| bls12-381-aggregate-ethereum-repeated-n8 | 1 | 10 | 5,650,785,570 | 3,072,863,248 |
| bls12-381-aggregate-ethereum-repeated-n8 | 1 | 100 | 56,507,855,700 | 28,150,976,158 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | 8 | 1 | 565,078,557 | 2,569,892,977 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | 8 | 2 | 1,130,157,114 | 2,848,538,676 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | 8 | 10 | 5,650,785,570 | 5,077,704,268 |
| bls12-381-aggregate-ethereum-repeated-n8-separate | 8 | 100 | 56,507,855,700 | 30,155,817,178 |
| bls12-381-aggregate-ic-distinct-n2 | 2 | 1 | 310,532,835 | 310,611,721 |
| bls12-381-aggregate-ic-distinct-n2 | 2 | 2 | 621,065,670 | 521,237,860 |
| bls12-381-aggregate-ic-distinct-n2 | 2 | 10 | 3,105,328,350 | 2,206,246,972 |
| bls12-381-aggregate-ic-distinct-n2 | 2 | 100 | 31,053,283,500 | 21,162,599,482 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | 2 | 1 | 850,994,532 | 850,996,046 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | 2 | 2 | 1,701,989,064 | 1,129,179,998 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | 2 | 10 | 8,509,945,320 | 3,354,651,614 |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | 2 | 100 | 85,099,453,200 | 28,391,207,294 |
| bls12-381-verify-ethereum-official | 2 | 1 | 286,405,944 | 286,407,106 |
| bls12-381-verify-ethereum-official | 2 | 2 | 572,811,888 | 560,574,522 |
| bls12-381-verify-ethereum-official | 2 | 10 | 2,864,059,440 | 2,753,913,850 |
| bls12-381-verify-ethereum-official | 2 | 100 | 28,640,594,400 | 27,428,981,290 |
| bls12-381-verify-ic-certificate | 2 | 1 | 222,072,725 | 222,114,346 |
| bls12-381-verify-ic-certificate | 2 | 2 | 444,145,450 | 394,235,861 |
| bls12-381-verify-ic-certificate | 2 | 10 | 2,220,727,250 | 1,771,207,981 |
| bls12-381-verify-ic-certificate | 2 | 100 | 22,207,272,500 | 17,262,144,331 |

Sampled occupied heap and Wasm capacity below are queried before the run, after the run message, and after four further GC increments. They are neither peak memory nor retained live data. Message-end GC may occur before after_run; four increments need not finish collection. Prepared keys and results remain reachable as specified by each fixture.

| Workload | Mode/reuse | Before occupied bytes | After occupied bytes | After GC occupied bytes | After GC Wasm capacity bytes |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2 | direct/1 | 5,321,632 [5,321,632–5,321,632] | 5,460,688 [5,460,688–5,460,688] | 5,530,704 [5,530,704–5,530,704] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-distinct-n2 | prepare/1 | 5,321,640 [5,321,640–5,321,640] | 5,400,744 [5,400,744–5,400,744] | 5,470,760 [5,470,760–5,470,760] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-distinct-n2 | prepared/1 | 5,400,624 [5,400,624–5,400,624] | 5,461,456 [5,461,456–5,461,456] | 5,531,472 [5,531,472–5,531,472] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-distinct-n8 | direct/1 | 5,323,408 [5,323,408–5,323,408] | 5,818,480 [5,818,480–5,818,480] | 5,888,496 [5,888,496–5,888,496] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-distinct-n8 | prepare/1 | 5,323,416 [5,323,416–5,323,416] | 5,639,064 [5,639,064–5,639,064] | 5,709,080 [5,709,080–5,709,080] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-distinct-n8 | prepared/1 | 5,638,944 [5,638,944–5,638,944] | 5,820,728 [5,820,728–5,820,728] | 5,890,744 [5,890,744–5,890,744] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8 | direct/1 | 5,321,504 [5,321,504–5,321,504] | 5,404,416 [5,404,416–5,404,416] | 5,474,432 [5,474,432–5,474,432] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8 | prepare/1 | 5,321,512 [5,321,512–5,321,512] | 5,361,248 [5,361,248–5,361,248] | 5,431,264 [5,431,264–5,431,264] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8 | prepared/1 | 5,361,128 [5,361,128–5,361,128] | 5,405,264 [5,405,264–5,405,264] | 5,475,280 [5,475,280–5,475,280] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8-separate | direct/1 | 5,321,504 [5,321,504–5,321,504] | 5,404,416 [5,404,416–5,404,416] | 5,474,432 [5,474,432–5,474,432] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8-separate | prepare/1 | 5,321,512 [5,321,512–5,321,512] | 5,637,160 [5,637,160–5,637,160] | 5,707,176 [5,707,176–5,707,176] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ethereum-repeated-n8-separate | prepared/1 | 5,637,040 [5,637,040–5,637,040] | 5,681,176 [5,681,176–5,681,176] | 5,751,192 [5,751,192–5,751,192] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ic-distinct-n2 | direct/1 | 5,321,376 [5,321,376–5,321,376] | 5,362,160 [5,362,160–5,362,160] | 5,432,176 [5,432,176–5,432,176] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ic-distinct-n2 | prepare/1 | 5,321,384 [5,321,384–5,321,384] | 5,361,128 [5,361,128–5,361,128] | 5,431,144 [5,431,144–5,431,144] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-aggregate-ic-distinct-n2 | prepared/1 | 5,361,008 [5,361,008–5,361,008] | 5,361,784 [5,361,784–5,361,784] | 5,431,800 [5,431,800–5,431,800] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | direct/1 | 5,321,520 [5,321,520–5,321,520] | 5,439,816 [5,439,816–5,439,816] | 5,509,832 [5,509,832–5,509,832] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | prepare/1 | 5,321,528 [5,321,528–5,321,528] | 5,400,632 [5,400,632–5,400,632] | 5,470,648 [5,470,648–5,470,648] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-fast-aggregate-ethereum-distinct-n2 | prepared/1 | 5,400,512 [5,400,512–5,400,512] | 5,440,584 [5,440,584–5,440,584] | 5,510,600 [5,510,600–5,510,600] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ethereum-official | direct/1 | 5,321,088 [5,321,088–5,321,088] | 5,360,600 [5,360,600–5,360,600] | 5,430,616 [5,430,616–5,430,616] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ethereum-official | prepare/1 | 5,321,112 [5,321,112–5,321,112] | 5,321,544 [5,321,544–5,321,544] | 5,391,560 [5,391,560–5,391,560] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ethereum-official | prepared/1 | 5,321,424 [5,321,424–5,321,424] | 5,360,936 [5,360,936–5,360,936] | 5,430,952 [5,430,952–5,430,952] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ic-certificate | direct/1 | 5,321,104 [5,321,104–5,321,104] | 5,341,008 [5,341,008–5,341,008] | 5,411,024 [5,411,024–5,411,024] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ic-certificate | prepare/1 | 5,321,128 [5,321,128–5,321,128] | 5,341,096 [5,341,096–5,341,096] | 5,411,112 [5,411,112–5,411,112] | 134,217,728 [134,217,728–134,217,728] |
| bls12-381-verify-ic-certificate | prepared/1 | 5,340,976 [5,340,976–5,340,976] | 5,341,272 [5,341,272–5,341,272] | 5,411,288 [5,411,288–5,411,288] | 134,217,728 [134,217,728–134,217,728] |

The JSON report retains all three memory phases, cumulative counters, exact source/artifact hashes, independent operation oracles and build/result provenance.
