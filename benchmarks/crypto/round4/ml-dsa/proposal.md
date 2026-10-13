# ML-DSA round-four candidates

Baseline `0e1e96a`, runtime `07ae7543`, fixed SDK `9f6ebeedc` / executable
`24d8d0b9`, unchanged RTS. No API, dependency, representation or SDK changes.

1. **Rate-block matrix sampling:** `hashing.rs::rej_ntt_poly` reads 168-byte
   SHAKE128 blocks and consumes ordered three-byte candidates. Existing RustCrypto
   already buffers permutations internally: this removes cursor checks and short
   copies, not Keccak permutations. Matrix expansion goes from at least 4,096
   tiny reader calls to about 80 block reads. The final block may have unused
   bytes; accepted coefficients and stream order remain identical. Benefits are
   expected in direct calls and preparation; hot prepared calls bypass ExpandA.
2. **Prepared vector decoding:** replace nested array construction with one
   checked vector slice and initialized output filled using LE chunks. Investigate
   the existing 24,576 bytes of generated copies per 4,096-byte vector. Preserve
   signed coefficients, unaligned-safe decoding, private layout and Drop behavior.

Measure candidate 1 before candidate 2. Screen official ACVP cases 4 and 6, with
matched direct/factory/hot controls, then validate final cases 4, 6, 11 and
randomized 362 on three fresh canisters. Record stack, Wasm size, allocation and
all exact oracles. No absolute-heap plateau rerun: layout remains unchanged.

Primary references: [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final),
[pinned fips204 source](https://github.com/integritychain/fips204/tree/8d456d989dce681233ef963d3c3306da8f76d7c7),
[reference block sampling](https://github.com/pq-crystals/dilithium/blob/master/ref/poly.c).
