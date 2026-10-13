Measured medians [minimum–maximum] from three fresh canisters per case.

Allocation is cumulative bytes allocated during the measured operation. Payload is the prepared object's declared byte payload.

Preparation is measured separately; prepared calls reuse a key created outside the timed interval.

| Workload | Mode | Instructions | Allocated bytes | Payload bytes | Canister Wasm bytes |
|---|---|---:|---:|---:|---:|
| rsa3072-sign-message-openssl3072 | direct | 447,485,855 [447,485,855–447,485,855] | 440 [440–440] | 0 | 278,833 |
| rsa3072-sign-message-openssl3072 | prepare | 6,138,602 [6,138,602–6,138,602] | 1,896 [1,896–1,896] | 1,840 | 280,089 |
| rsa3072-sign-message-openssl3072 | prepared | 443,560,039 [443,560,039–443,560,039] | 440 [440–440] | 1,840 | 280,229 |
| rsa3072-sign-prehash-openssl3072 | direct | 447,476,438 [447,476,438–447,476,438] | 440 [440–440] | 0 | 278,818 |
| rsa3072-sign-prehash-openssl3072 | prepare | 6,138,602 [6,138,602–6,138,602] | 1,896 [1,896–1,896] | 1,840 | 280,074 |
| rsa3072-sign-prehash-openssl3072 | prepared | 443,550,622 [443,550,622–443,550,622] | 440 [440–440] | 1,840 | 280,214 |
| rsa3072-verify-message-openssl3072 | direct | 9,832,026 [9,832,026–9,832,026] | 32 [32–32] | 0 | 278,790 |
| rsa3072-verify-message-openssl3072 | prepare | 3,642,309 [3,642,309–3,642,309] | 880 [880–880] | 824 | 280,044 |
| rsa3072-verify-message-openssl3072 | prepared | 8,431,134 [8,431,134–8,431,134] | 32 [32–32] | 824 | 280,186 |
| rsa3072-verify-prehash-openssl3072 | direct | 9,822,608 [9,822,608–9,822,608] | 32 [32–32] | 0 | 278,775 |
| rsa3072-verify-prehash-openssl3072 | prepare | 3,642,309 [3,642,309–3,642,309] | 880 [880–880] | 824 | 280,029 |
| rsa3072-verify-prehash-openssl3072 | prepared | 8,421,716 [8,421,716–8,421,716] | 32 [32–32] | 824 | 280,171 |

Instruction models below use only the measured reuse=1 medians: direct = N×D; prepared = P+N×H. They are arithmetic projections, not measured batch timings. Break-even is the first integer N with a strict saving.

| Workload | First cheaper reuse | N | Direct model | Prepared model |
|---|---:|---:|---:|---:|
| rsa3072-sign-message-openssl3072 | 2 | 1 | 447,485,855 | 449,698,641 |
| rsa3072-sign-message-openssl3072 | 2 | 2 | 894,971,710 | 893,258,680 |
| rsa3072-sign-message-openssl3072 | 2 | 10 | 4,474,858,550 | 4,441,738,992 |
| rsa3072-sign-message-openssl3072 | 2 | 100 | 44,748,585,500 | 44,362,142,502 |
| rsa3072-sign-prehash-openssl3072 | 2 | 1 | 447,476,438 | 449,689,224 |
| rsa3072-sign-prehash-openssl3072 | 2 | 2 | 894,952,876 | 893,239,846 |
| rsa3072-sign-prehash-openssl3072 | 2 | 10 | 4,474,764,380 | 4,441,644,822 |
| rsa3072-sign-prehash-openssl3072 | 2 | 100 | 44,747,643,800 | 44,361,200,802 |
| rsa3072-verify-message-openssl3072 | 3 | 1 | 9,832,026 | 12,073,443 |
| rsa3072-verify-message-openssl3072 | 3 | 2 | 19,664,052 | 20,504,577 |
| rsa3072-verify-message-openssl3072 | 3 | 10 | 98,320,260 | 87,953,649 |
| rsa3072-verify-message-openssl3072 | 3 | 100 | 983,202,600 | 846,755,709 |
| rsa3072-verify-prehash-openssl3072 | 3 | 1 | 9,822,608 | 12,064,025 |
| rsa3072-verify-prehash-openssl3072 | 3 | 2 | 19,645,216 | 20,485,741 |
| rsa3072-verify-prehash-openssl3072 | 3 | 10 | 98,226,080 | 87,859,469 |
| rsa3072-verify-prehash-openssl3072 | 3 | 100 | 982,260,800 | 845,813,909 |

Actual batch observations (whole batch, without dividing by reuse). Cold rows include one preparation plus N calls in the timed interval; direct/prepared rows exclude preparation. These observations do not feed the model or break-even:

| Workload | Mode | Reuse | Batch instructions | Batch allocated bytes |
|---|---|---:|---:|---:|
| rsa3072-sign-prehash-openssl3072 | direct | 2 | 894,952,920 [894,952,920–894,952,920] | 880 [880–880] |
| rsa3072-sign-prehash-openssl3072 | direct | 10 | 4,474,763,608 [4,474,763,608–4,474,763,608] | 4,400 [4,400–4,400] |
| rsa3072-sign-prehash-openssl3072 | prepared | 2 | 887,101,288 [887,101,288–887,101,288] | 880 [880–880] |
| rsa3072-sign-prehash-openssl3072 | prepared | 10 | 4,435,505,448 [4,435,505,448–4,435,505,448] | 4,400 [4,400–4,400] |
| rsa3072-verify-prehash-openssl3072 | direct | 2 | 19,645,310 [19,645,310–19,645,310] | 64 [64–64] |
| rsa3072-verify-prehash-openssl3072 | direct | 10 | 98,225,558 [98,225,558–98,225,558] | 320 [320–320] |
| rsa3072-verify-prehash-openssl3072 | direct | 100 | 982,253,348 [982,253,348–982,253,348] | 3,200 [3,200–3,200] |
| rsa3072-verify-prehash-openssl3072 | prepared | 2 | 16,843,526 [16,843,526–16,843,526] | 64 [64–64] |
| rsa3072-verify-prehash-openssl3072 | prepared | 10 | 84,216,638 [84,216,638–84,216,638] | 320 [320–320] |
| rsa3072-verify-prehash-openssl3072 | prepared | 100 | 842,164,148 [842,164,148–842,164,148] | 3,200 [3,200–3,200] |

Sampled occupied heap and Wasm capacity below are queried before the run, after the run message, and after four further GC increments. They are neither peak memory nor retained live data. Message-end GC may occur before after_run; four increments need not finish collection. Prepared keys and results remain reachable as specified by each fixture.

| Workload | Mode/reuse | Before occupied bytes | After occupied bytes | After GC occupied bytes | After GC Wasm capacity bytes |
|---|---|---:|---:|---:|---:|
| rsa3072-sign-message-openssl3072 | direct/1 | 5,321,808 [5,321,808–5,321,808] | 5,322,480 [5,322,480–5,322,480] | 5,392,496 [5,392,496–5,392,496] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-message-openssl3072 | prepare/1 | 5,321,832 [5,321,832–5,321,832] | 5,323,960 [5,323,960–5,323,960] | 5,393,976 [5,393,976–5,393,976] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-message-openssl3072 | prepared/1 | 5,323,760 [5,323,760–5,323,760] | 5,324,432 [5,324,432–5,324,432] | 5,394,448 [5,394,448–5,394,448] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | direct/1 | 5,321,792 [5,321,792–5,321,792] | 5,322,464 [5,322,464–5,322,464] | 5,392,480 [5,392,480–5,392,480] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | prepare/1 | 5,321,816 [5,321,816–5,321,816] | 5,323,944 [5,323,944–5,323,944] | 5,393,960 [5,393,960–5,393,960] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | prepared/1 | 5,323,744 [5,323,744–5,323,744] | 5,324,416 [5,324,416–5,324,416] | 5,394,432 [5,394,432–5,394,432] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | direct/2 | 5,321,792 [5,321,792–5,321,792] | 5,322,904 [5,322,904–5,322,904] | 5,392,920 [5,392,920–5,392,920] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | direct/10 | 5,321,792 [5,321,792–5,321,792] | 5,326,424 [5,326,424–5,326,424] | 5,396,440 [5,396,440–5,396,440] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | prepared/2 | 5,323,744 [5,323,744–5,323,744] | 5,324,856 [5,324,856–5,324,856] | 5,394,872 [5,394,872–5,394,872] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-sign-prehash-openssl3072 | prepared/10 | 5,323,744 [5,323,744–5,323,744] | 5,328,376 [5,328,376–5,328,376] | 5,398,392 [5,398,392–5,398,392] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-message-openssl3072 | direct/1 | 5,321,664 [5,321,664–5,321,664] | 5,321,928 [5,321,928–5,321,928] | 5,391,944 [5,391,944–5,391,944] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-message-openssl3072 | prepare/1 | 5,321,688 [5,321,688–5,321,688] | 5,322,800 [5,322,800–5,322,800] | 5,392,816 [5,392,816–5,392,816] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-message-openssl3072 | prepared/1 | 5,322,600 [5,322,600–5,322,600] | 5,322,864 [5,322,864–5,322,864] | 5,392,880 [5,392,880–5,392,880] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | direct/1 | 5,321,648 [5,321,648–5,321,648] | 5,321,912 [5,321,912–5,321,912] | 5,391,928 [5,391,928–5,391,928] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | prepare/1 | 5,321,672 [5,321,672–5,321,672] | 5,322,784 [5,322,784–5,322,784] | 5,392,800 [5,392,800–5,392,800] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | prepared/1 | 5,322,584 [5,322,584–5,322,584] | 5,322,848 [5,322,848–5,322,848] | 5,392,864 [5,392,864–5,392,864] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | direct/2 | 5,321,648 [5,321,648–5,321,648] | 5,321,944 [5,321,944–5,321,944] | 5,391,960 [5,391,960–5,391,960] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | direct/10 | 5,321,648 [5,321,648–5,321,648] | 5,322,200 [5,322,200–5,322,200] | 5,392,216 [5,392,216–5,392,216] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | direct/100 | 5,321,648 [5,321,648–5,321,648] | 5,325,080 [5,325,080–5,325,080] | 5,395,096 [5,395,096–5,395,096] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | prepared/2 | 5,322,584 [5,322,584–5,322,584] | 5,322,880 [5,322,880–5,322,880] | 5,392,896 [5,392,896–5,392,896] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | prepared/10 | 5,322,584 [5,322,584–5,322,584] | 5,323,136 [5,323,136–5,323,136] | 5,393,152 [5,393,152–5,393,152] | 134,217,728 [134,217,728–134,217,728] |
| rsa3072-verify-prehash-openssl3072 | prepared/100 | 5,322,584 [5,322,584–5,322,584] | 5,326,016 [5,326,016–5,326,016] | 5,396,032 [5,396,032–5,396,032] | 134,217,728 [134,217,728–134,217,728] |

The JSON report retains all three memory phases, cumulative counters, exact source/artifact hashes, independent operation oracles and build/result provenance.
