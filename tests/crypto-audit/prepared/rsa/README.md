# Prepared RSA independent audit

**Approved.** The final five-bit-window implementation passed the independent
matrix below, eight prepared and nine direct Ash methods with forced GC/sanity
checks, two package cases across source/IR/lowered interpreters and Wasm, and
six reviewed nominal-type rejection cases. All 62 implementation hashes and
both plugin artifacts matched at final approval; see [review.json](review.json).

The audit extends the completed [direct RSA review](../../round3/rsa/README.md)
without changing that review's fixtures or evidence. Every private key used here
is a public test fixture and must never protect real data.

`audit.py` generates independent expected prepared layouts and arithmetic outputs
with Python integers and `hashlib`. It reuses the pinned OpenSSL/Wycheproof corpus
read-only and adds a consistent composite CRT key with qInv=3, including 191
leading zero bytes. That key must prepare successfully under the documented
consistency-only validation and fail signing's mandatory public fault check.

The test driver includes the production C translation unit to inspect private
helpers without adding a testing API. It checks:

- 272 API cases on both direct and prepared paths, including all 108 pinned
  Wycheproof cases, malformed PSS, error precedence, and independent exact
  signatures. Every successful native factory is compared byte-for-byte against
  an independent layout oracle, including the complete zero padding.
- 1,223 public arithmetic inputs across 102 odd 3072-bit moduli against Python
  `pow`, the direct fixed-exponent helper, and unchanged upstream public RSA.
- 68 private arithmetic inputs interleaving two genuine independent keys and
  both factor orders, against Python `pow`, the baseline 8-slot private wrapper,
  the current 37-slot wrapper, and the prepared kernel. Boundaries include zero,
  one, p, q, n-1, n, n+1 and the maximum 384-byte integer.
- 20 shaped context faults in dP, dQ, Montgomery qInv and both inverse words.
  Each must return `invalidSecretKey`, wipe the output, preserve the input and
  stay inside output guards. Context length headers remain valid. These native
  fault injections do not imply that Motoko code can forge nominal handles.
- Portable OCaml and compiled Wasm semantics for the full corpus, plus 12
  interleaved signing/verification rounds and mismatched public keys.
- Seven ordinary PEM/DER import forms and rejection of all 16 previously
  identified RSA-PSS restricted-key forms, without creating output files.

Native execution uses ASan and UBSan. Raw contexts are eight-byte aligned;
factories and operations have guard bytes and full context/input immutability
checks. A preserved baseline source snapshot is generated from `f43a81e`; its
historical uninitialized padding is retained only for differential comparison.
The production 37-slot wrapper initializes and clears its entire workspace.
Both private paths now select the unchanged primitive's five-bit window:
direct scratch provides 34/33 factor slots and prepared scratch provides 33.
At 52 words per slot, the 33-slot table requirement is exactly 1,716 words.
The fixed exponent length determines all table-scan and partial-window bounds.

The earlier two-bit-window candidate passed the full audit; its independent
evidence and exact executed test sources remain in `window2/`. Those source
copies document the historical run; use the main runner for reproduction.
The final five-bit candidate passed a separate full native, portable and Wasm
run. Its implementation hashes and final gate status are in `review.json`.

The separate owner tests cover actual canister execution with forced GC and
sanity checks, factory/operation aliases, evaluation order, retained handles in
records and arrays across awaits, and observed reclamation. The SDK/type tests
reject forging, Blob conversion, public/private handle mixing, shared messages,
stable state and Candid serialization. Executed evidence and source hashes are
recorded in the final report; generating a fixture alone is not a test pass.

The reviewed hot-path contract is a factory-created, immutable nominal handle
of the correct kind. The payload contains inline arithmetic data, not native
pointers or a portable key serialization. Preparation validates key invariants
once; secret exponentiation retains the unchanged constant-time i31 primitive,
fixed exponent lengths and final signature self-check. The interpreter is a
variable-time correctness reference. Sanitizers and differential tests do not
constitute a proof of constant-time machine code or comprehensive cryptanalysis.

Run with explicit toolchain paths and the matching prepared-capable SDK:

```sh
python3 tests/crypto-audit/prepared/rsa/audit.py --generate
python3 tests/crypto-audit/prepared/rsa/audit.py --native --motoko --imports \
  --cc /path/to/cc --moc /path/to/moc --wasmtime /path/to/wasmtime \
  --openssl /path/to/openssl --plugin "$PWD/dist/rsa"
```

Generated binaries, contexts, test source and transient logs stay under `_out`.
Retained final evidence belongs in `final/`; `review.json` records the audit
decision after testing the final source and artifact hashes.
