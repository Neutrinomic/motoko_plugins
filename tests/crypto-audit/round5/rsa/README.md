# RSA round-five independent audit

No production defect found. This round adds caller/input regressions for the
existing RSA-3072/e=65537, PSS-SHA256/MGF1-SHA256, salt32 profile; it changes no
implementation or compiler code. All keys are published test fixtures.

The review followed the public module, compiler reference and bridge, native
adapter, prepared contexts, vendored CRT workspace clearing, and import CLI.
It also read the retained round-three, prepared, and round-four reviews before
selecting gaps. The prior arithmetic/Wycheproof corpora and fault-injection
fixtures remain unchanged.

New coverage:

- Four deterministic signing vectors use Python full-exponent modular `pow`
  and an independent [RFC 8017 section 9.1](https://www.rfc-editor.org/rfc/rfc8017.html#section-9.1)
  encoder. OpenSSL accepts all four. Cases use the secret Blob as a message,
  the same Blob as message/salt or digest/salt, and an 8,193-byte binary message.
- Twenty-two independently signed malformed PSS encodings exercise both sides
  of MGF block boundaries, every delimiter bit, salt/hash endpoints, and the
  forbidden high bit. The high-bit representative is explicitly below `n`,
  so rejection cannot be explained by modular wrap. OpenSSL rejects all 22.
- `driver.c` runs production C at `-O3` with ASan/UBSan. It checks direct/prepared
  parity, read-only input overlap, offsets 1 and 7 for raw byte inputs/outputs,
  factory source alignment, untouched inputs/contexts and output guards.
  Twenty-four NULL-input calls check that invalid lengths reject before reads.
  Prepared storage stays eight-byte aligned and uses the correct factory-created
  layout; arbitrary forged contexts and overlapping output/input storage are
  outside the compiler bridge's contract.
- The maintained `crypto-rsa-boundaries.mo` package test runs the new vectors
  through public APIs. It also checks short/long digest and salt errors, error
  precedence, integer-range errors with aliased public key/signature, and the
  distinction between message and prehash operations.
- `imports.py` executes the actual import CLI for 99 deterministic cases:
  nine valid container/factor-order controls and 90 rejections/path checks.
  It covers malformed ASN.1, unsupported exponents/dimensions, inconsistent CRT
  components, fully consistent composite factors, RSA-PSS restrictions including
  absent/default parameters, unsupported algorithms, and existing-output
  sentinels. Rejected inputs create no output; accepted files match the expected
  components and mode 0600. OpenSSL normalization of readable input is allowed
  by the documented importer contract.

All new checks passed. The package test passed source, IR and lowered
interpretation, Wasm validation, and Wasm execution with sanity checks. The
reused distribution's 57 RSA source pins and both artifact hashes match the
worktree. The frozen SDK ELF hash also matches its build manifest.
[report.json](report.json) records commands, versions and relevant hashes.

Run the durable native/oracle/import entry point inside a compiler environment
with a C compiler supporting ASan/UBSan and OpenSSL available (or set `CC` and
`OPENSSL`):

```sh
bash tests/crypto-audit/round5/rsa/run-native.sh
```

It writes only ignored `_build/crypto-audit-round5-rsa` outputs. Run the public
case from the matching SDK checkout using an absolute path containing `run/`:

```sh
test-runner -b -j2 /path/to/plugins/packages/fast/tests/run/crypto-rsa-boundaries.mo
```

The generator validates its maintained Motoko fixture during native runs;
`python3 tests/crypto-audit/round5/rsa/audit.py --generate` intentionally refreshes
that fixture. No new Ash/GC or benchmark claims are made: this round changes only
tests, and the reviewed managed layouts and production artifacts are unchanged.
Private-key validation still checks consistency rather than proving primality;
import still delegates primality checking to OpenSSL. Native scratch clearing
and signature fault checks remain in place, without promising erasure of
caller-owned managed key material.
