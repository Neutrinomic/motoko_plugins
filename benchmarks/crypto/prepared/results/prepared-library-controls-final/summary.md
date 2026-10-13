Measured medians [minimum–maximum] from three fresh canisters per case.

Allocation is cumulative bytes allocated during the measured operation. Payload is the prepared object's declared byte payload.

Standalone operation controls (no preparation comparison or speedup calculation):

| Control | Operation | Reuse | Instructions | Allocated bytes | Canister Wasm bytes |
|---|---|---:|---:|---:|---:|
| pure-p256-verify-rfc-sample | verifyPrehash | 1 | 323,983,718 [323,983,718–323,983,718] | 23,927,448 [23,927,448–23,927,448] | 661,914 |
| pure-secp256k1-verify-ecdsa-rfc6979-key1-sample | verify | 1 | 137,009,273 [137,009,273–137,009,273] | 10,903,256 [10,903,256–10,903,256] | 661,720 |

Sampled occupied heap and Wasm capacity below are queried before the run, after the run message, and after four further GC increments. They are neither peak memory nor retained live data. Message-end GC may occur before after_run; four increments need not finish collection. Prepared keys and results remain reachable as specified by each fixture.

| Workload | Mode/reuse | Before occupied bytes | After occupied bytes | After GC occupied bytes | After GC Wasm capacity bytes |
|---|---|---:|---:|---:|---:|
| pure-p256-verify-rfc-sample | control/1 | 5,361,216 [5,361,216–5,361,216] | 29,288,896 [29,288,896–29,288,896] | 29,358,912 [29,358,912–29,358,912] | 134,217,728 [134,217,728–134,217,728] |
| pure-secp256k1-verify-ecdsa-rfc6979-key1-sample | control/1 | 5,338,744 [5,338,744–5,338,744] | 16,242,232 [16,242,232–16,242,232] | 16,312,248 [16,312,248–16,312,248] | 134,217,728 [134,217,728–134,217,728] |

The JSON report retains all three memory phases, cumulative counters, exact source/artifact hashes, independent operation oracles and build/result provenance.
