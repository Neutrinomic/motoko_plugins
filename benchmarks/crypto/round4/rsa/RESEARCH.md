# RSA optimization round four

Baseline: plugins `0e1e96a`, compiler `9f6ebeedc`, actual ELF SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`,
original matching RTS. The previous winning five-bit window, fixed RSA-3072
profile, nominal prepared layouts and post-sign fault check remain unchanged.
No SDK opportunity has been identified: the dominant cost is native arithmetic.

Primary sources:

- [BearSSL integer design](https://bearssl.org/bigint.html).
- [BearSSL constant-time design](https://bearssl.org/constanttime.html).
- Pinned upstream `7bea48e5e850ab4cafbe68d3765cdaba13a86d6f`, vendored
  `src/inner.h:1443` Montgomery contract and `src/int/i31_montmul.c`.

The first approved screen declares only the Montgomery destination `restrict`.
This supplies alias information already required by the upstream contract.
`x` and `y` remain unrestricted: squaring deliberately passes the same input
pointer twice. The kernel's arithmetic and loop counts are unchanged.

Actual call-site proof:

| Caller | Destination separation |
|---|---|
| Direct public exponentiation | Alternating `left` and `right` arrays; `base` and modulus have separate arrays. |
| Prepared public exponentiation | Initial destination `base` differs from `left` and immutable context; later squares alternate `left`/`right`. |
| Prepared CRT recombination | Stack `coefficient` differs from stack `s1` and immutable qInv/p context. |
| Direct CRT recombination | Output slot 5, operands slots 3/4, modulus slot 2; each slot 52 words and accessed value 51 words. |
| Optimized exponentiation table | Output is the next whole 52-word slot; inputs are preceding slot and external value. |
| Optimized exponentiation squares/multiply | Output first scratch slot; operands external value or second scratch slot, modulus separate. |
| Generic upstream exponentiation oracle | Output scratch `t2`, inputs external value/`t1`; existing API requires distinct temporaries. |

In direct CRT, q/p exponentiation scratch begins at slots 3/4, beyond their
respective inputs and modulus slots. In prepared CRT, scratch is its own stack
array and p/q are read-only context fields. Adjacent subarrays within one larger
workspace do not overlap. The restriction covers only accessed destination
objects; it does not forbid the read-only inputs from sharing one struct.

The second approved screen, contingent on measured value, passes the public
50/100-limb length through an inline helper containing the same arithmetic body.
This aims to let LLVM simplify fixed bounds without inventing multiplication or
reduction algorithms. Preserve a generic fallback, and inspect emitted Wasm for
secret-dependent control/access plus code-size growth. No broad window sweep.

A new dedicated squaring or reduction algorithm would increase the proof and
maintenance burden and is not proposed this round. BearSSL i62 needs 64×64→128
products; native core Wasm has only 64-bit integer multiplication, so emulation
may erase its fewer-limb advantage. Read-only investigation precedes any such
backend proposal; no major rewrite is approved.

The pinned [i62 implementation](https://www.bearssl.org/gitweb/?p=BearSSL;a=blob_plain;f=src/int/i62_modpow2.c;hb=7bea48e5e850ab4cafbe68d3765cdaba13a86d6f)
packs pairs of i31 limbs. A fair five-bit-window private comparison would need
875 aligned 64-bit scratch words (7,000 bytes): the existing 6,864-byte temporary
would select only four bits. This and the wide-product emulation cost make a
blind backend substitution misleading.

[HACL* Bignum32](https://github.com/hacl-star/hacl-star/blob/main/dist/gcc-compatible/Hacl_Bignum32.c)
offers constant-time exponentiation and dedicated Karatsuba squaring using
32-bit limbs, but integrating it would change representation and reduction.
Its complete [RSA-PSS implementation](https://github.com/hacl-star/hacl-star/blob/main/dist/gcc-compatible/Hacl_RSAPSS.c)
uses full-modulus private exponentiation instead of this plugin's CRT path.
It is a future backend research option, not a justified narrow replacement.

Every retained candidate must match independent arithmetic/signature oracles,
malformed-key/PSS tests, CRT fault rejection and native sanitizers, portable
interpreter and actual Wasm. Full final comparison reports setup, direct/hot
instructions, cumulative allocation, exact payload, native stack and Wasm size.

Both screens are complete. Destination-only `restrict` gives a negligible
0.08% signing gain; fixed public limb specialization supplies the meaningful
gain. The selected implementation passes the independent arithmetic, alias,
sanitizer, fault, interpreter and compiled-Wasm gates. See the
[final report](README.md) for the measured 14-workload comparison.

The audit corrected a pre-existing build-capacity assumption: upstream
`inner.h` unconditionally defines 4096/2080-bit maxima, overriding the
command-line 3072/1536 values. Therefore direct `U` is 70 and its 37U-plus-header
temporary is 10,364 bytes, while actual operand slots are 52 words. Prepared
exponentiation has its explicit 6,864-byte temporary. Both selected paths use
window five. Earlier direct 8U/9U descriptions should read q/p windows 2/2 and
3/2; their measured outputs remain valid. Existing artifact-derived stack bounds
already account for the actual allocations. This round preserves source flags,
runtime bytes and historical evidence rather than adding a new capacity change.
