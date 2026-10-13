# Prepared P256 verification

The selected representation is a width-eight affine public-key comb. It makes
repeated verification 69.68% cheaper in the RFC6979 sample: 12,541,922 →
3,802,871 IC instructions. Both calls allocate 32 bytes for their typed result.
The same prepared-capable plugin, compiler and RTS supply each direct control.
Direct verification also uses fixed odd multiples of G, so rebuilding the
shared generator table is not credited as a prepared-key benefit.

The final selected build passed all 111 trials: seven independent fixtures,
37 cases, each measured in three fresh PocketIC canisters. Every instruction
count was identical across its three trials. These are actual RFC sample batch
measurements; cold batches include one preparation followed by all checks.

| Checks with one key | Direct instructions | Prepared instructions, key already prepared | Cold instructions, including preparation | Cold allocated bytes |
| --- | ---: | ---: | ---: | ---: |
| 1 | 12,541,922 | 3,802,871 | 23,491,346 | 16,408 |
| 2 | 25,083,596 | 7,605,420 | 27,293,895 | 16,440 |
| 10 | 125,416,988 | 38,025,812 | 57,714,287 | 16,696 |
| 100 | 1,254,167,648 | 380,255,222 | 399,943,697 | 19,576 |

Including preparation, ten checks save 53.98% and 100 checks save 68.11%.
Direct and already-prepared batches both allocate 32 bytes per check.
The three-call break-even below is modeled from the separately measured
single-operation counters, not an additional measured batch. All seven final
fixtures have that same modeled break-even. See the
[final counters and memory samples](final-comparison.md) and
[strict final source/artifact comparison](final-comparison.json).

| Internal candidate | Preparation instructions | Verification instructions | Preparation allocation | Public-key payload |
| --- | ---: | ---: | ---: | ---: |
| Width 4 | 7,651,728 | 6,632,315 | 1,016 B | 960 B |
| Width 6 | 10,534,255 | 4,810,638 | 4,088 B | 4,032 B |
| **Width 8, selected** | **19,688,675** | **3,802,871** | **16,376 B** | **16,320 B** |

Width eight saves another 20.95% per repeated call over width six. Its modeled
preparation-plus-verification cost beats direct verification from the third
call and beats width six from the tenth call. The API offers one prepared type
and one factory; applications can use the direct API for one-off checks.
The production generator emits only the selected format. Frozen screen inputs
preserve the earlier candidates for reproduction.

Each of the 27 screen cases ran in three fresh PocketIC canisters; all 81 exact
output checks passed and each instruction count was identical across trials.
Actual repeated-call batches of 2, 10 and 100 also passed. The selected prepared
canister is 373,581 bytes, 13,188 bytes larger than the width-six equivalent.
See [all screen counters and memory samples](width-comparison.md) and the
[strict source/artifact comparison](width-comparison.json).

Preparation allocation includes managed-object and result overhead. Payload
size is the private initialized byte representation, not a measured process
heap peak. The benchmark records occupied heap and Wasm capacity before the
operation, after its message, and after four extra GC increments. These samples
are not proof of completed collection or retained live memory. The public API
and independent audit separately exercise handle aliases across observed
collection and discard/reprepare cycles. The table contains no pointers or
native allocation; the immutable managed Blob belongs to the caller. The
independent emitted-Wasm audit bounds temporary native stack use at 88,000 bytes
for preparation and 1,344 bytes for prepared verification. This stack is reused
by calls and is separate from the retained managed-key payload.

`generate.py` produces the final direct, preparation, prepared and cold-call
fixtures. Cold cases time preparation and verification together, including
actual batches of 1, 2, 10 and 100 for the RFC sample. Other fixtures cover digest
zero/order, an extreme secret-derived public key, high/low-S signatures, wrong
digests and wrong keys. Expected answers use the earlier independent Python
RFC6979/OpenSSL vectors and an additional Python integer-curve verification
check; runtime output is never used as an expected answer.

The shared [prepared benchmark protocol](../README.md) freezes all sources,
plugin binaries, compiler/RTS and runner dependencies. Screen stages are
`prepared-p256-width4-screen`, `prepared-p256-width6-screen`, and
`prepared-p256-width8-screen`; the final stage is
`prepared-p256-width8-final-fixed`. They measure deterministic IC counters;
no host wall-time or host-isolation performance claim is made.

The earlier `prepared-p256-width8-final` actor build found a duplicate local
binding in the generated cold fixtures. Scoping the factory statement fixed
those ten fixtures; no plugin or SDK source changed. The original failed build
is preserved, and no counters were collected from it. The corrected stage
compiled all 37 actors before running the 111 successful trials. Compressed
actor-build and counter logs accompany this report.
