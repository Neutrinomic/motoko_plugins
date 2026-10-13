# Independent prepared BLS audit

This directory tests the protected local key factories and all five prepared
verification APIs. Production baseline: `f43a81e`; earlier aggregate-fusion audit
evidence remains in `tests/crypto-audit/round3/bls12-381`.

`generate-extra.py` uses independent py_ecc 8.0.0 to create additional test-only
negative-key, maximum-count and long-message vectors. `generate.py` combines
these with retained py_ecc profile vectors, published RFC9380 pre-cofactor points
that must fail subgroup validation, and explicitly specified errors. It creates
128 factory cases, 32 single-verification cases and 68 aggregate cases. Expected
signatures are never produced by the implementation under test; the direct API
is an additional parity oracle.

Native tests guard deliberately unaligned payloads, descriptors and outputs,
require immutable inputs and unchanged outputs on errors, compare factories
under different fill bytes to detect uninitialized output, and compare borrowed
tables to the unchanged upstream Miller loop. Shape/count/evaluation-order and
ordinary callback checks run through the public Motoko module. Negative type
tests reject Blob forgery, profile mixing, unproved keys in PoP-only consumers,
and Candid import/export.

The Ash suite retains prepared arrays and a capturing closure across suspension
and forced collection, interleaves fresh and old keys, and asserts actual
reclamation occurred. It uses immutable managed values owned by the caller;
there is no retained native pointer or plugin cache.

Run `run.py` from the selected compiler's Nix environment after building a
matching frozen plugin. Pass `--motoko /path/to/compiler`, a new `--run NAME`,
and optionally `--phase native|public|ash`. Existing evidence is never overwritten.
For Ash, also supply `--ash-source` and `--ash-provenance` pointing to the private
Ash snapshot whose compiler resolver selects the audited SDK; global tools and
HOME are untouched.

Final audit **passes** for production `347d1c3` and SDK `9f6ebeedc` on the exact
artifacts in `report.json`: five independent native tests, both public backends,
nine type rejection tests, and seven Ash methods. Source and artifact hashes
remained unchanged throughout execution. Three initial test-harness annotation
or syntax errors and their logs remain preserved; no production fixes were needed.

The GC actor retains nine prepared keys through arrays and a capturing closure,
interleaves nine fresh keys per round, and executes 186 successful prepared
verifications after thirteen suspension boundaries. With 72 MiB of discarded
pressure it asserts actual reclamation exceeds 4 MiB; the exact delta was not
logged. Ash's displayed 529 instructions/0 B for this method measure its final
empty metrics callback, not the asynchronous GC workload. Per-operation costs
and retained memory belong in the separate benchmark report.

`hooks-review/source-review.json` independently checks upstream provenance and
the narrow vendored coefficient hooks. This is source and functional review,
not a formal proof or external security certification.

The independent [performance review](performance-review.json) also **passes**.
`review-performance.py` rehashes 696 frozen inputs and all 24 canister Wasms,
matches the plugin artifacts and public module to the executed correctness audit,
and independently recomputes all 72 observations, eight comparison groups and
32 arithmetic reuse models. Direct and prepared controls use the same improved
runtime, including the shared generator table. Hot verification saves 4.27–69.74%
of instructions on these fixtures; preparation is measured separately.

Most workloads first become cheaper on their second modeled use. Eight references
to one prepared Ethereum key first become cheaper at one use, by only 26,600
instructions; eight separately prepared equal values need eight uses. The latter
executes eight factories and retains 1,152 payload bytes instead of 144, with the
same cryptographic inputs and hot verification cost. Much of the Ethereum
aggregate gain reuses factory-validated PoPs; each call still verifies its signature.
Prepared actors add 2,072–17,566 Wasm bytes compared with their direct controls.

The benchmark reported zero reclaimed bytes at every snapshot. Its allocation
and occupied-heap samples do not establish retained live or peak memory; the
separate Ash test above establishes collection correctness. The owner corrected
an obsolete fixture-count sentence and clarified factory caching in `2f544d2`;
the immutable measured stage and all actor bytes remain unchanged. No production
or performance-evidence findings remain.
