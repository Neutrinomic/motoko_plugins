# Prepared ML-DSA measurements

Prepared ML-DSA verification uses **42–50% fewer instructions** on these four
fixtures; signing uses **16–47% fewer**. Preparation pays for itself at the
second use in the single-call model for every fixture. Actual factory-plus-two-
call batches confirm that threshold for the small-message fixture.

All **135 calls** (45 cases × three fresh canisters) passed exact official NIST
answers in PocketIC with its normal instruction limits. Medians equal minima
and maxima for every instruction/allocation row. Direct and prepared calls use
the same final compiler, plugin and fixture; direct seeded signing already
reuses the matrix expanded during key generation.

| Operation · ACVP case | Direct instructions | Prepare once | Prepared call | Hot speedup |
|---|---:|---:|---:|---:|
| sign · 11 | 8,757,856 | 5,005,869 | 4,652,024 | 1.88× |
| sign · 4 | 13,193,656 | 5,016,889 | 9,076,804 | 1.45× |
| sign · 6 | 25,979,729 | 4,994,195 | 21,885,571 | 1.19× |
| sign-randomized · 362 | 18,343,541 | 5,017,319 | 14,226,247 | 1.29× |
| verify · 11 | 4,471,060 | 2,525,559 | 2,581,202 | 1.73× |
| verify · 362 | 3,874,229 | 2,525,407 | 1,984,523 | 1.95× |
| verify · 4 | 3,810,844 | 2,525,559 | 1,920,986 | 1.98× |
| verify · 6 | 3,905,985 | 2,525,559 | 2,016,127 | 1.94× |

The fixtures span 1–8,192-byte messages, contexts up to 255 bytes, both
deterministic and caller-randomized signing, and different rejection-sampling
costs. Signing cost varies with inputs; these are measured examples, not a
universal signing bound. Direct `publicKey` costs **5,107,151 instructions** and
allocates **1,368 bytes**, measured separately rather than subtracted from
signing.

## Actual reuse, including preparation

These case-4 rows measure the complete batch. Cold cost includes one factory
call and all N operations; no empty-loop subtraction is used.

| Operation | Uses | Direct batch instructions | Prepare + batch instructions |
|---|---:|---:|---:|
| Sign | 1 | 13,193,656 | 14,093,525 |
| Sign | 2 | 26,387,356 | 23,170,260 |
| Sign | 10 | 131,935,788 | 95,783,340 |
| Sign | 100 | 1,319,355,648 | 912,680,490 |
| Verify | 1 | 3,810,844 | 4,446,416 |
| Verify | 2 | 7,621,820 | 6,367,372 |
| Verify | 10 | 38,108,108 | 21,734,220 |
| Verify | 100 | 381,078,848 | 194,611,260 |

## Allocation and retained state

| Operation | Allocated bytes per measured call | Private prepared payload |
|---|---:|---:|
| Prepare public key | 20,632 | 20,576 |
| Prepare secret key | 28,856 | 28,800 |
| Verify, direct or prepared | 32 | — |
| Sign, direct or prepared | 2,480 | — |

Preparation explicitly trades retained heap for reusable expanded key and matrix
tables. It does not reduce the signature output allocation. Failed factories
also allocate their fixed output buffer, which becomes collectible garbage.
Managed secret caches are not securely erased by GC.

The separate [matched memory experiment](memory/README.md) preserves its original
**failed absolute quiet-window qualification**: each forced GC call allocates
17,504 bytes of bookkeeping scratch in every mode. A separately reviewed,
post-hoc analysis compares matching trial/stage/GC indices instead:

| Prepared key | Observed paired heap overhead per key | Paired residual after dropping |
|---|---:|---:|
| Public | 20,600 B | 0 B |
| Secret | 28,824 B | 0 B |

These differences repeat at all 24 indices across three trials of 32 separately
prepared objects and equal payload plus a 24-byte Blob header. All retained-key
and dropped-root correctness checks pass. Extra reclamation accounts for the
disappearing increment. This is observed paired heap overhead, **not an exact
live-heap or collection-completion guarantee**; the original absolute-window
qualification remains false. Independent GC tests additionally retain correct
prepared keys through actual reclamation of more than 4 MiB.

## Evidence

The [complete instruction and allocation report](../results/prepared-mldsa-final/summary.md)
and [raw trials](../results/prepared-mldsa-final/results.json) include all modes,
models, batches, sampled occupied heap, Wasm capacity, exact oracles and pins.
Those routine snapshots are not proof of collection completion or retained live
bytes. The [memory protocol](memory/README.md) explains the stronger matched
retain/drop experiment and its limitations.

Final production source: `8d67a9fee0e59c482bb867ee8a7b2c2f758f2f69`.
Compiler executable: `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
Runtime: `07ae75432d55ddcbb4741f0d0aa40bb0d086f365d1c68c0648bde3dd20850c3f`.
The [independent audit](../../../../tests/crypto-audit/prepared/ml-dsa/README.md)
covers official parity, nominal type boundaries, GC retention and strict native
stack analysis. The final maximum additional native stack is **138,624 bytes**;
direct signing uses **137,984 bytes**. No native allocation, hidden key cache or
retained native pointer is introduced.
