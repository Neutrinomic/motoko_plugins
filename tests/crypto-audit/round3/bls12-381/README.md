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

Final source and performance review approves production commit `fa74cad5`.
All 21 functional validation commands pass. `review-performance.py --integration
/path/to/integration` independently checks the 17-case paired PocketIC run:
102 exact-output observations, 1,433 frozen input files, 34 measured Wasm artifacts,
identical actors, compiler commands, compiler/RTS/runner hashes and Motoko dependencies.
It recomputes every published instruction/allocation median and memory snapshot;
the result is retained in `performance-review.json`.

Valid IC aggregates improve instructions by 30.75–33.59%, repeated Ethereum
aggregates by 20.35–43.36%, distinct Ethereum aggregates by 11.64–13.18%, and fast
Ethereum aggregates by 4.11–4.14%. Every successful aggregate cohort allocates less.
Single-signature verification is unchanged. These gains justify promotion with
explicit costs: small IC duplicate rejection increases from 1,896 to 7,891
instructions at size 2 and 8,175 to 10,886 at size 8; allocation increases by
216/504/4,096 bytes for duplicate sizes 2/8/127. Wasm grows by 11,042–23,669 bytes.
All measured reclamation counters are zero; occupied-heap snapshots are neither
peak nor live-memory measurements and do not demonstrate full reclamation.
