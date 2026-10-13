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
