# Independent round4 BLS audit

Correctness **passes** for production `5e72dab` and runtime
`ebc5fa2fd9fc6ed3698bd523f5101d4883ef51c0e7bf4783f4b2da64d691972c`.
The compiler remains `24d8d0b` with the original RTS. Exact source, artifact,
command and log hashes are retained in [report.json](report.json) and
[executed evidence](evidence/final/report.json).

The audit reviews three narrow changes: fixed field exponent chains, six
Frobenius maps replaced with conjugation, and streaming coefficients for the
two-term pairing check. `check-chain.py` symbolically evaluates the actual
addition chain to exactly `(p-3)/4`, without exponent reduction or a duplicate
field implementation. Derived square-root and inverse exponents match exactly.
The owner's test-only original square-root and final-exponentiation formulas
were independently compared with baseline `0e1e96a`, allowing only argument
renaming, comments and whitespace.

Streaming retains the original Miller driver and curve formulas, including
identity substitution and masking, coefficient order, the final doubling and
negative-parameter conjugation. The generator table is immutable; dynamic
terms use two local curve states. Prepared IC and general aggregate pairing
paths remain unchanged. The owner tests compare raw Miller results before final
exponentiation for all identity masks, generator/dynamic terms, cancellation
and subgroup/hash-derived points. The 1,024-byte driver-state bound describes
that struct, not total Wasm stack or peak memory.

All **18 independent commands passed** against frozen inputs: symbolic exponent
checking, five guarded native tests, and four public suites in both the Motoko
interpreter and validated memory64 Wasm. These reuse the retained independent
fixtures: 128 factories, 32 singles, 68 prepared aggregates, and 270 direct
public cases. Coverage includes malformed/canonical/subgroup/identity errors,
invalid proofs, distinct-message rules, combined-error precedence, limits,
exactly-once argument evaluation, ordinary callbacks, immutable inputs,
unaligned guarded buffers and unchanged output on errors.

The earlier nominal-type/Candid rejection and actual GC pressure evidence is
explicitly reused, not reported as rerun. No public type, compiler, payload
layout or ownership contract changed. That earlier pressure test retained
nine prepared keys through arrays and a closure and observed more than 4 MiB
reclaimed. This round executes the current crypto artifacts but does not add
a new heap-lifetime claim.

Run the retained checks after building the selected artifact, from the approved
compiler's Nix environment:

```sh
python3 tests/crypto-audit/round4/bls12-381/run.py \
  --motoko /path/to/frozen-sdk --run NEW_RUN
```

The runner pins the compiler and original RTS, caps native jobs/test threads
at two, writes a fresh evidence directory, and rejects source/artifact changes
during execution. It never overwrites previous test evidence. Performance
review is pending the complete paired benchmark cohort.
