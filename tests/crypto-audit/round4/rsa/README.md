# RSA round-four independent audit

**Approved.** The selected public-length specialization and destination-only
`restrict` passed the complete independent audit below; see
[review.json](review.json) and [executed evidence](final/round4-report.json).
Baseline plugins revision: `0e1e96a`. Earlier RSA audits and fixtures are
read-only. All keys are public test keys.

The selected change supplies alias information and specializes the
existing Montgomery loop for public 50/100-limb sizes. The prior five-bit
exponentiation window, prepared layouts and signature fault check remain fixed.

## Aliasing review

The destination's accessed words must be disjoint from all three inputs.
Read-only inputs may alias each other; `x == y` is used for squaring.
Sharing a larger enclosing array does not make disjoint element ranges invalid.
The rule concerns accesses to modified objects during that call; an outer
restricted pointer may be passed into a nested helper. See the C committee
draft [N1570, section 6.7.3.1, examples 2–4](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).

| Call site | Destination/input separation |
|---|---|
| Direct public operation | Distinct `left`, `right`, `base` and modulus arrays; squares alternate left/right. |
| Prepared public conversion | `base` destination, `left` input and immutable `r2`/modulus context fields. |
| Prepared public squares | Alternating stack arrays; immutable modulus context. |
| Prepared CRT recombination | Stack coefficient destination, separate `s1` and immutable qInv/p fields. |
| Direct CRT recombination | Output slot 5, operands slots 3/4, modulus slot 2; 52-word slots, 51 accessed words. |
| Optimized exponentiation table | Output next 52-word slot; inputs preceding slot and external value. |
| Optimized exponentiation square/multiply | First scratch slot output; external value and optional second scratch slot inputs. |
| Generic exponentiation | Distinct output `t2`, value and `t1`; input `t1` may be used twice. |

For direct private operations, q-exponentiation scratch begins at slot 3 beyond
q/value slots 0/1; p-exponentiation scratch begins at slot 4 beyond modulus/value
slots 2/3. Prepared private scratch is a separate stack array. Neither caller
passes the encompassing struct or buffer through another access path inside the
Montgomery call. The unchanged `br_i31_sub` and zeroing helpers receive pointers
derived from the destination, satisfying its restricted association.

## Independent tests

`audit.py` imports the prepared audit runner without modifying it and redirects
all generated files and logs into this directory's ignored `_out` directory.
Its original 272 API cases, 1,223 public arithmetic cases, 68 private cases and
20 shaped fault injections remain the broad regression gate. Both generic public
and original-eight-slot private oracles are remapped to unchanged upstream
Montgomery and exponentiation sources, whose digests must match `UPSTREAM.json`.

New raw cases compare Python integer arithmetic, pinned upstream Montgomery and
the candidate. Nineteen announced bit widths cover small generic lengths and
49/50/51/99/100/101 limbs, including both endpoints of specialized length ranges.
There are 1,824 cases with four destination positions in one enclosing array,
including exact adjacent ranges and same-input squaring. Guards and input bytes
must remain unchanged. Native corpus instrumentation also checks every actual
candidate call's destination/input range separation and counts calls by size.
Native execution uses `-O3` with ASan and UBSan so compiler alias optimization is
active. These checks supplement source review; sanitizers alone do not prove
correct use of `restrict` or constant-time machine code.

Run only with a scheduled test slot and frozen candidate artifact:

```sh
python3 tests/crypto-audit/round4/rsa/audit.py --native --motoko --imports \
  --cc /path/to/cc --moc /path/to/moc --wasmtime /path/to/wasmtime \
  --openssl /path/to/openssl --plugin "$PWD/dist/rsa"
```

## Final execution and artifact review

All native sanitizer, raw arithmetic, portable interpreter, compiled Wasm and
import checks passed. This includes 211 complete context layouts, 20 shaped
fault rejections with wiped output, seven ordinary imports and 16 rejected
restricted imports. All 831,481 instrumented Montgomery calls satisfied the
destination/input separation checks; 683,280 deliberately aliased the two
read-only operands for squaring. The original whole-exponentiation oracles use
their unchanged Montgomery primitive, independently of the candidate.

The actual runtime's [reviewed kernel](final/montgomery.wat) has 14 conditional
branches, all determined by public lengths or loop counters; operand values
never determine an address or branch. Its native stack frame remains zero.
An independently regenerated [stack bound](final/stack-independent.json) agrees
with the owner's result: 11,664 bytes for direct signing and 9,568 for prepared
signing, unchanged from baseline. These sums exclude Motoko caller frames and
the engine value stack. Runtime size grows from 30,264 to 31,212 bytes.

All 62 implementation source hashes and both artifacts matched after execution.
The four selected-screen benchmark rows use those same pins; measured allocation
remains 440 bytes per signature and 32 bytes per verification. All 14 final
paired benchmark rows (84 observations) match the audited source/artifact pins:
four selected-screen rows plus ten preparation, message and reuse controls.
Preparation costs, allocation and payload sizes remain unchanged. The two
comparison reports and their digests are linked from `review.json`.

Build-log review also identified pre-existing ineffective command-line capacity
macros: upstream `inner.h` overrides them with 4096/2080-bit maximums. Thus the
direct wrapper's allocation unit is 70 words (`tmp[2591]`, 10,364 bytes), while
actual 1536-bit factors still use 52-word scratch slots and the prepared
exponentiation workspace has 1,716 words (6,864 bytes). Both current paths use
the five-bit window. Historical direct 8U/9U configurations actually selected
q/p windows 2/2 and 3/2 respectively; earlier prose describing 9U as 2/2 was
incorrect. Their measured costs and frozen artifacts remain valid and unchanged.
Both native audit and production builds use these same
effective defaults. All retained compiler warnings are these macro
redefinitions; the artifact-derived stack figures above remain authoritative.
Removing the ineffective flags can be a separate cleanup without changing the
header, actual capacity or arithmetic.

Prior [prepared-key type and GC evidence](../../prepared/rsa/review.json) applies
to unchanged SDK/module/registration sources and unchanged managed layouts.
This round executes the changed runtime's semantic corpus; it does not claim a
new GC suite for the arithmetic-only delta.
