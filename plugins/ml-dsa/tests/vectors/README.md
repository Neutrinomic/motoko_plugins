# ML-DSA-44 independent known answers

`acvp-ml-dsa-44.json` is an exact field projection of the official NIST ACVP
repository at commit `975de31eb83d87039ec88934fdc47d8c312b892d`:

- [Key generation, FIPS204](https://github.com/usnistgov/ACVP-Server/blob/975de31eb83d87039ec88934fdc47d8c312b892d/gen-val/json-files/ML-DSA-keyGen-FIPS204/internalProjection.json): all 25 ML-DSA-44 cases.
- [Signing, FIPS204-tr1](https://github.com/usnistgov/ACVP-Server/blob/975de31eb83d87039ec88934fdc47d8c312b892d/gen-val/json-files/ML-DSA-sigGen-FIPS204-tr1/internalProjection.json): all 30 ML-DSA-44 seed-format, pure external-interface cases (15 deterministic and 15 randomized).
- [Verification, FIPS204](https://github.com/usnistgov/ACVP-Server/blob/975de31eb83d87039ec88934fdc47d8c312b892d/gen-val/json-files/ML-DSA-sigVer-FIPS204/internalProjection.json): all 15 ML-DSA-44 pure external-interface cases, including modified messages, commitments, z values and hints.

The signing corpus's `tr1` revision adds seed/expanded key format registration;
it uses the final FIPS 204 cryptographic algorithm, not draft Dilithium.
Prehash and internal/external-mu interfaces are excluded because the public
plugin exposes the pure external message/context interface only. Expanded
secret keys are excluded because public signing accepts a 32-byte seed.

Run `python3 plugins/ml-dsa/tests/vectors/extract-acvp.py` to retrieve the pinned
sources and regenerate the JSON, selected Motoko fixture and case index. The
JSON records each complete upstream source's SHA-256. No plugin output is used
to generate expected values. Deterministic signing rows add an all-zero
32-byte `rnd`, as specified by FIPS 204. Every seed here is public test data.

The native Rust suite uses all 70 answers. The generated `../Vectors.mo` exposes
3 key-generation, 6 signing and all 15 verification cases to public Motoko tests;
`selected-motoko-cases.json` records their exact IDs. The signing selection spans
one-byte and 8192-byte messages, empty and 255-byte contexts, and both randomness
modes. These are correctness vectors, not a representative timing distribution.
