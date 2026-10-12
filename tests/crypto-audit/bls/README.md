# Independent BLS12-381 audit

This suite was authored separately from the plugin implementation. Expected
bytes come from retained RFC 9380 vectors, Ethereum BLS test release v0.1.2,
a real IC certificate, and Ethereum `py_ecc==8.0.0`. `provenance.json` records
source URLs and corpus hashes. `generate.py` never imports plugin code.

The 160-case core primitive corpus plus 46 MSM boundary fixtures run through the exported native byte ABI,
`mo:fast/BLS12381` with the actual Motoko interpreter, and compiled memory64
Wasm. A further 24 public Motoko assertions exercise IC distinct-message
aggregation and Ethereum PoP-protected aggregation, message/key alignment,
domain crossover, rogue keys, batch errors, primitive aliases, and one-time
argument evaluation. Native calls use null pointers for empty input, unaligned
guarded outputs, unchanged-output checks on errors, and input-immutability
checks.

Generate fixtures only when intentionally updating their independent inputs:

```sh
python3 -m venv /tmp/bls-audit-python
/tmp/bls-audit-python/bin/pip install py_ecc==8.0.0
/tmp/bls-audit-python/bin/python tests/crypto-audit/bls/generate.py
/tmp/bls-audit-python/bin/python tests/crypto-audit/bls/generate-msm.py
```

Build a private snapshot from the compiler environment, then use the emitted
artifact directory:

```sh
cd ../motoko_sha
nix develop --command python3 ../plugins/scripts/build-isolated.py \
  --offline --motoko . bls12-381
nix develop --command python3 ../plugins/tests/crypto-audit/bls/run.py \
  --motoko . --plugin ../plugins/_build/crypto-stage/BUILD/dist/bls12-381
```

The runner records exact commands, exit codes, source/artifact hashes, and
elapsed times in `logs/all-evidence.json`; `.log` files contain compiler and
execution output. Compiled Wasm files are reproducible and ignored by Git.

Coverage includes canonical point/scalar/field encodings, non-subgroup points,
infinity policy, all ten RFC random-oracle hashes, zero/unit field maps,
oversized and empty DSTs, maximum and oversized packed batches, pairing signs,
IC framing, Ethereum signature/PoP domain separation, and rejection of a rogue
key whose sum with an honest key equals the attacker's key. Profile APIs test
proofs on each call. The raw group aggregation operations provide no proof of
possession, as documented by the API.

The MSM extension checks both groups at sizes 3/4/5, 15/16/17, 63/64/65,
and 127/128. It mixes identity, repeated, inverse and independently derived
distinct points, and zero, one, r-1, bit254 and full-width canonical scalars.
First/last malformed points and scalars check error precedence and unchanged
output. Pippenger uses variable-time buckets and requires public scalars.

The audit independently confirms the upstream G2 zero-map correction and the
portable Num-based reference. Its constant pre-cofactor point is internal;
caller-provided points still undergo canonical on-curve and subgroup decoding.
The audit does not constitute formal verification or third-party security
certification. `findings.json` records resolved observations and practical
limits.
