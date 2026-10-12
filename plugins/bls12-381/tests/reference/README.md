# Portable hash-to-curve reference tests

Run from the sibling compiler checkout:

```sh
cd ../motoko_sha
nix develop --command ../plugins/plugins/bls12-381/tests/reference/run.sh
```

An environment with `ocamlfind`, `ocamlopt`, and `num` installed can invoke
`run.sh` directly. Compilation happens in a temporary directory; it does not
leave generated files in the plugin source tree.

The portable compiler implementation uses the host's `num` library through
its local `Z` adapter; it does not require Zarith's native stubs.

`hash_vectors.ml` checks all five RFC 9380 random-oracle vectors for each of
BLS12-381 G1 and G2, including their exact affine coordinates and subgroup
membership. It also checks all twenty SHA-256 XMD vectors with 38-byte and
256-byte domain-separation tags, invalid field encodings, invalid XMD lengths,
and maps of zero, unit, and field-boundary inputs. Nonzero exceptional G1
inputs satisfying `11*u² = -1` exercise the SWU exceptional branch alongside
zero. XMD checks also cover domain lengths 0, 1, 255, 256, and 4096 and output
lengths 0, 1, 31, 33, and 8160 against independent SHA-256 expectations.
The map API clears the effective cofactor; its output
therefore differs from the intermediate `Q0` and `Q1` points in RFC vectors.

`group_vectors.ml` additionally checks the portable field/group implementation,
including arithmetic, subgroup validation, canonical decoding, and independent
compressed point multiplication vectors.

The JSON files in `vectors/` are unmodified upstream fixtures from
[the CFRG hash-to-curve reference repository](https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/tree/664b13592116cecc9e52fb192dcde0ade36f904e/poc/vectors)
at commit `664b13592116cecc9e52fb192dcde0ade36f904e`:

- `BLS12381G1_XMD:SHA-256_SSWU_RO_.json`: RFC 9380 Appendix J.9.1.
- `BLS12381G2_XMD:SHA-256_SSWU_RO_.json`: RFC 9380 Appendix J.10.1.
- `expand_message_xmd_SHA256_38.json`: RFC 9380 Appendix K.1.
- `expand_message_xmd_SHA256_256.json`: RFC 9380 Appendix K.2.

The assertions contain the expected values directly and need no JSON library,
network access, subprocess-based cryptography, or runtime plugin to execute.
