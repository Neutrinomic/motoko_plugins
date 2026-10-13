# Independent RSA audit

This directory tests the fixed RSA-3072/e=65537, SHA-256/MGF1-SHA256,
32-byte-salt PSS profile. The implementation owner does not generate this
audit's expected signatures. [Final review](review.json): approved, with no
unresolved findings in the audited implementation.

The final candidate passed **270 public cases** on each of native C with
ASan/UBSan, portable OCaml interpretation, and compiled Motoko with sanity
checks. Its fixed public-exponent optimization additionally passed **1,223
raw arithmetic cases across 102 moduli**, matching both Python integer `pow`
and unchanged upstream BearSSL. See [public results](final/report.json) and
[arithmetic results](final/public-differential.json). The owner's separate
[nine Ash tests](final/ash.log) also passed with forced GC and sanity checks;
their sources and results were reviewed, including actual reclamation followed
by signing again with retained, dynamically allocated inputs.

`audit.py` combines the pinned [Wycheproof corpus](https://github.com/C2SP/wycheproof),
independent Python integer/RFC 8017 encoding, and OpenSSL interoperability.
The corpus revision and digest are in `vectors/provenance.json`.

**All private keys in `vectors/` are published test keys. Never use them to
protect data or authorize real operations.** OpenSSL generates the independent
test key once; subsequent runs retain it and reproduce the same deterministic
oracle signatures. OpenSSL's separately generated PSS signatures use random
salt and are saved in `cases.json`.

Coverage includes:

- Every public primitive through native C, portable OCaml interpretation and
  compiled Motoko, with matching error precedence.
- All 108 applicable Wycheproof cases, exact deterministic signatures for
  empty/short/1 KiB messages and SHA-256 padding boundaries, prehash equivalence
  and OpenSSL verification in both directions.
- Seven common OpenSSL PEM/DER key containers, exact component conversion,
  matching derived modulus and private-output file permissions.
- Sixteen RSA-PSS-restricted key containers rejected before writing files.
  The original converter silently discarded those policies; the narrow
  `rsaEncryption` OID check fixes that without adding configurable policies.
  [Before](baseline/restricted-import.json) and [after](final/restricted-import.json).
- Mutated/zero/out-of-range CRT components, swapped factor order, inconsistent
  exponents, invalid key/signature widths, signature integers at the modulus
  boundary, wrong message and mismatched public key.
- PSS top-bit, padding, delimiter, trailer, MGF and salt-length failures.
- A deliberately composite but algebraically consistent key: raw validation
  correctly makes no primality claim, while signing's final public-operation
  check rejects and clears a faulty signature.
- Native address/undefined-behavior sanitizers, unchanged borrowed input
  buffers and guarded output boundaries. The owner's separate Ash suite
  covers managed values retained across observed GC.

Run in a matching toolchain environment:

```sh
python3 tests/crypto-audit/round3/rsa/audit.py --prepare --openssl /path/to/openssl
python3 tests/crypto-audit/round3/rsa/audit.py --native --cc /path/to/cc
python3 tests/crypto-audit/round3/rsa/audit.py --motoko \
  --moc /path/to/moc --wasmtime /path/to/wasmtime --plugin /path/to/dist/rsa
python3 tests/crypto-audit/round3/rsa/public_differential.py --cc /path/to/cc
python3 tests/crypto-audit/round3/rsa/restricted_keys.py \
  --openssl /path/to/openssl --require-rejection
```

Generated Motoko/C fixtures and logs go under ignored `_out/`. Retained results
under `final/` identify the actual tested source and artifact hashes. `baseline/`
preserves the earlier 216-case run and the exact original importer for reproducing
the restriction-loss finding; that importer is only an audit fixture.

The source review follows [RFC 8017 sections 5.2 and 9.1](https://www.rfc-editor.org/rfc/rfc8017.html)
and the upstream [BearSSL constant-time RSA design](https://www.bearssl.org/constanttime.html#rsa).
This is engineering validation, not a formal cryptographic proof or an external
security certification.
