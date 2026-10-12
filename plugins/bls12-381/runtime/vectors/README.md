# BLS runtime vectors

`rfc9380_g1.json` and `rfc9380_g2.json` are the CFRG's published
[BLS12381 hash-to-curve vectors](https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/tree/main/poc/vectors)
for the RFC 9380 XMD:SHA-256 SSWU random-oracle suites. `rfc9380.rs`
encodes the published affine coordinates using IETF compressed flags;
field inputs retain real-before-imaginary order, while compressed G2 points
encode imaginary-before-real coordinates.

`ethereum.rs` uses the CC0-1.0
[Ethereum BLS tests v0.1.2 release](https://github.com/ethereum/bls12-381-tests/releases/tag/v0.1.2).
The tests cover its verification and canonical point-decoding cases.

The IC certificate test in `src/tests.rs` is copied from
`ic-verify-bls-signature` 0.6.0 `tests/tests.rs`, `verify_valid`, whose source
identifies the vectors as originating in agent-rs tests. That crate is
Apache-2.0 licensed. The expected result was fixed before this runtime existed.

`pop_py_ecc.json` was independently generated using `py-ecc==8.0.0`:

```python
from py_ecc.bls import G2ProofOfPossession as bls
assert bls.PopVerify(bls.SkToPk(42), bls.PopProve(42))
```

The zero/unit field-map expectations in `src/tests.rs` agree between the
independent OCaml RFC implementation and `py-ecc==8.0.0`. These exposed a
zero-input defect in zkcrypto `bls12_381` 0.8.0's G2 map (also present in
0.9.0): the alternate-root eta loop overwrites the valid solution at `u=0`
because both sides of every candidate check become zero. Our shared
`map_g2_field` helper uses the fixed SSWU-plus-isogeny image for that input;
the regular hash-to-field path also calls this helper before the common
cofactor-clearing step. No dependency arithmetic was copied or changed.

Reproduce the fixed, **pre-cofactor** compressed point:

```python
from py_ecc.optimized_bls12_381 import FQ2
from py_ecc.bls.hash_to_curve import map_to_curve_G2, clear_cofactor_G2
from py_ecc.bls.g2_primitives import G2_to_signature
p = map_to_curve_G2(FQ2.zero())
print(G2_to_signature(p).hex())
# 8869822666fe850cb93dfd4fa64ebd9ef77ba62b5c12055eadb6e7cc8972f64e01c4577d3d52456c26867647f53665190cdfcc9523305c43ef59a4e347cb3fc76688c60b05bafebd445a65901b5dd40644e21d35dcbe50a95955e4f8e24fbe6f
print(G2_to_signature(clear_cofactor_G2(p)).hex())
# 8a67d12118b5a35bb02d2e86b3ebfa7e23410db93de39fb06d7025fa95e96ffa428a7a27c3ae4dd4b40bd251ac658892018320896ec9eef9d5e619848dc29ce266f413d02dd31d9b9d44ec0c79cd61f18b075ddba6d7bd20b7ff27a4b324bfce
```
