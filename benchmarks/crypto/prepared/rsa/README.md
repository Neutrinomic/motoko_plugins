# Prepared RSA performance

RSA-3072 / e=65537 / PSS-SHA256 / MGF1-SHA256 / salt32, using the same independent
OpenSSL fixture and compiler for every mode. All 22 cases passed in three fresh
PocketIC canisters each. Counts below are medians; every instruction count was
identical across its three trials. The full [report](report.md) includes message
variants, actual batches, sampled heap/capacity and [machine-readable pins](report.json).

| Prehashed operation | Best direct instructions | Prepared instructions | Preparation instructions | Hot saving | First cheaper reuse* |
|---|---:|---:|---:|---:|---:|
| Sign | 447,476,438 | 443,550,622 | 6,138,602 | 0.88% | 2 |
| Verify | 9,822,608 | 8,421,716 | 3,642,309 | 14.26% | 3 |

*Preparation-inclusive instruction model: direct = N × D; prepared = P + N × H.
The crossover is the first integer N with a strict saving. These projections
include preparation once, whereas the measured prepared batches reuse a context
created before timing. Signing at N=2/10 and verification at N=2/10/100 were also
measured as actual batches. Signing N=100 is modeled only, because its roughly
44 billion instructions exceed the ordinary per-message budget. Signing gains
from preparation are modest; the exponentiation itself dominates.

| Prepared value | Inline payload | Bytes allocated by preparation | Hot operation allocation, direct / prepared |
|---|---:|---:|---:|
| Secret key | 1,840 B | 1,896 B | Sign: 440 / 440 B |
| Public key | 824 B | 880 B | Verify: 32 / 32 B |

Preparation allocations include managed wrappers, not just the context payload.
There is no hidden cache or retained native pointer. Secret contexts retain
sensitive managed bytes until reclamation, which does not promise erasure.
These objects are non-shared/non-stable and must be recreated after upgrades.
The report's occupied-heap snapshots are not peak-memory or retained-live-data
measurements; cumulative allocation, payload size and native stack are separate.

The direct API received the same private-exponentiation optimization as prepared
signing. Increasing bounded, initialized and wiped scratch lets the unchanged
BearSSL primitive use its existing constant-time five-bit window. The matched
[selection screen](window5-screen.json) retained this one targeted candidate:

| Path | Two-bit window | Five-bit window | Instruction reduction |
|---|---:|---:|---:|
| Direct sign | 520,752,934 | 447,476,438 | 14.07% |
| Prepared sign | 546,911,624 | 443,550,622 | 18.90% |

The actual Wasm [stack analysis](window5-stack.json) bounds the fixed native
call chain at 11,664 bytes for direct signing and 9,568 bytes for prepared
signing, inside the compiler's 4 MiB reserve. It rejects recursion, indirect
calls and unknown stack updates; caller Motoko frames and engine value-stack
space are outside that bound. The arithmetic primitive and mandatory public
signature fault check are unchanged.

The [independent audit](../../../../tests/crypto-audit/prepared/rsa/README.md)
checks native sanitizers, OCaml and compiled Wasm, full context layouts,
independent arithmetic/signature oracles and injected CRT faults. Public module,
nominal-type rejection and forced-GC Ash suites passed on the final artifact.

Reproduction uses [the shared protocol](../README.md), `generate.py`, the
22-entry `cases.json` manifest and immutable stage `prepared-rsa-window5-final`.
Its [build manifest](../results/prepared-rsa-window5-final/build.json),
[raw observations](../results/prepared-rsa-window5-final/results.json) and
[source map](../results/prepared-rsa-window5-final/source-map.json) retain exact
compiler, runtime, actor and fixture identities.
Historical window8/window9 and paired window2/window5 screens are retained as
separate evidence; they are not mixed into the final comparison.
