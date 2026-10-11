# JSON audit evidence

The independent audit checked the typed visitors, parser, allocation behavior,
and managed results. The optimized implementation passed all checks below.
This is targeted regression evidence, not a proof of correctness.

| Check | Coverage |
| --- | --- |
| Exact scalar values | 604 Python-derived encode/decode cases: every integer width, bignum boundaries through 13,600 bits, finite Float/Float32 samples, signed zero |
| Binary and Unicode values | 161 cases using Python base64, CRC32/base32, and JSON: principal lengths 0–29, noncanonical principal rejection, Blob sizes through 4 KiB, Unicode scalar/control boundaries |
| JSON syntax | 9,263 cases against Python's JSON parser, with duplicate keys, non-JSON constants, and invalid surrogate scalars rejected; includes 2,000 wide-object cases with mixed escape spellings and nested frames |
| GC and early failure | [Permanent fixture](../run-drun/json-error-gc.mo): errors after 1,024 constructed records, heap churn, forced GC, and retained numeric, Blob, Principal, option, tuple, variant, and error values |

The 765 scalar/binary/Unicode cases passed the source interpreter, IR
interpreter, lowered IR interpreter, and generated Wasm. Syntax and allocation
probes run against a copied production Rust runtime with its native allocation
counter. Generated inputs, copied sources, and binaries stay under `_build`.

## Findings fixed

- **Nested scans copied object keys repeatedly.** A 262 KiB input containing
  64 nested arrays around one large object key allocated 35,147,632 scratch
  bytes; adding one Unicode escape raised this to 69,226,417 bytes. Borrowed,
  validated key ranges reduced these to **264,825** and **264,831** bytes.
  These are cumulative native allocation requests, excluding input creation,
  Motoko allocation headers, and returned values. They matter because Wasm
  scratch allocations remain until a later GC. The probes enforce a 1 MiB
  ceiling for both cases.
- **Array quota diagnostics differed across execution paths.** Encoding
  1,000,000 null elements reported `/999999` in interpreters and `""` in Wasm.
  The reference evaluator now mirrors the visitor's collection preflight.
- **Tagged options omitted `/some` from encoding error paths.** Both encoders
  now include that JSON object wrapper, matching decoding diagnostics.

The last two fixes have exact assertions in
[json-limits.mo](../run/json-limits.mo).

## Reproduce

Use Python 3.9 or newer and the pinned Motoko Nix environment. Build the JSON
plugin against that compiler first. From the compiler checkout, for sibling
directories named `motoko_sha` and `plugins`:

```sh
nix develop -c ../plugins/scripts/build.sh --motoko "$PWD" --skip-motoko-build json
nix develop -c bash ../plugins/plugins/json/tests/audit/run.sh --motoko "$PWD"
```

`run.sh` accepts `--output PATH` and uses repository-relative discovery.
`generate.py` can run separately to recreate the deterministic corpora. The
generated `manifest.json` records case counts, seeds, and current source and
plugin hashes. The runner uses `test-runner -b` without accepting expectations.
Production sources are never modified by these probes.

The audited optimized artifacts had these SHA-256 hashes:

- Runtime Wasm: `b4463880a5a89bc77e1b563688024c1f54049781a56a80299bf04e517eee2496`
- Compiler plugin: `7299accf3d1a3fac7e92ec37e420991d590f87d25931267f6860078577ff3851`

The allocation baseline used plugin repository commit
`b95c4b4230b3ff73baafb155e0ef35a58f383b77`. The optimized checks used the
subsequent JSON changes with the same compiler pinned by `toolchains/motoko.json`.
Native compiler plugin hashes can differ between rebuilds; the generated
manifest identifies each local run.
