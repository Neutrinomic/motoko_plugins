# Independent BLS aggregate-fusion audit

This audit checks the new native aggregate bridge against explicit valid/invalid
expectations, with the pre-fusion Motoko wrapper as a second public-behavior oracle.
`FrozenWrapper.mo` is test-only historical source at the commit in `provenance.json`;
production uses only the current plugin.

`generate.py` creates 246 cases from retained independent py_ecc profiles,
published RFC 9380 pre-cofactor points, malformed encodings and combined errors.
The public suite adds 24 array-shape, limit and argument-evaluation cases. The native
suite checks all 246 cases through deliberately unaligned guarded descriptors and
payloads, plus 8 early bounds/opcode rejection cases. No expected signature is
produced by the implementation being tested.

Coverage includes canonical encoding, subgroup membership, identity rejection,
exact message distinctness around sorting thresholds, first/last invalid proofs,
repeated keys with different proofs, same-call-only proof reuse, error precedence,
input immutability, output bounds, and unchanged output on error. Published profiles
and invalid-message cases exercise both successful and false pairings. Existing
`aggregate-boundaries.mo`, `crypto-bls-round2.mo`, the retained long-message
`cache-cap.mo`, and `aggregate-functions.mo` are also run against the built candidate
in the source interpreter and validated memory64 Wasm. The last test preserves
ordinary typed callback use for all three aggregate APIs.

Run from the compiler checkout, after building `bls12-381` in the audited plugins
checkout:

```sh
nix develop --command python3 /path/to/plugins/tests/crypto-audit/round3/bls12-381/run.py \
  --motoko /path/to/motoko_sha --phase all
```

The runner retains commands, output, exit status and source/artifact hashes in
`evidence/`. `report.json` records the final source review and performance gate.
These checks are functional/source audits, not formal verification or empirical
side-channel certification.
