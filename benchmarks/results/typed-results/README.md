# Typed plugin results: CandidX validation

CandidX now returns `{ #ok : Blob; #err : Text }`. Expected input and encoding
limit failures return through generated code and the Rust kernel as status
values. Error paths allocate the final variant only after leaving the borrowed
memory interval. The canonical profile and output bytes are unchanged.

The current native comparison uses the same actor, compiler, input values and
measurement boundaries for both implementations. Both include successful
Result unwrapping. Native means `CandidX.canonicalize(to_candid(value))`.
Three trials gave identical counts for every phase, with zero reclaimed bytes
during measurement. Input setup and message-end GC are outside the interval.

| Workload | Native instructions | Plugin instructions | Native/plugin |
|---|---:|---:|---:|
| candid-empty | 17,548 | 582 | 30.15× |
| candid-nat | 39,820 | 745 | 53.45× |
| candid-static-record | 404,924 | 1,797 | 225.33× |
| candid-blob-64k | 210,032 | 66,508 | 3.16× |
| candid-nat64-4096 | 560,441 | 144,167 | 3.89× |
| candid-sparse-128 | 11,590,346 | 800,267 | 14.48× |
| candid-sparse-1024 | 88,379,476 | 6,154,646 | 14.36× |
| candid-nested-option-arrays | 5,044,929 | 411,895 | 12.25× |
| candid-variants-64 | 22,489,701 | 140,344 | 160.25× |
| candid-variants-256 | 139,551,461 | 561,897 | 248.36× |
| candid-variants-1024 | 1,428,890,507 | 2,345,613 | 609.18× |

The `#ok` wrapper adds 32 allocated bytes per call. Explicit error propagation
has a cost: compared with the archived ABI 1 comparison, this run uses about
7–9% more instructions on the dynamic record/variant workloads and 26% more
on nested optional arrays. The 64 KiB Blob and 4,096-Nat64 array cases add less
than 0.3%. Fixed-width and inlined helpers skip redundant status checks; the
Rust kernel carries compact numeric errors. These are current measurements,
not updates to the archived ABI 1 results.

Both 500-random-record fuzz seeds passed: 1,130 typed record cases and 93
directed cases per seed, including independent canonicality checks,
schema-extension invariance, and original-value recovery through other
implementations. The same 61 frozen golden vectors still match. Runtime tests
cover nontrapping ABI errors, quota failures, and incomplete context cleanup.
Motoko tests cover `#err` recovery and success/error variants surviving forced
GC with retained inputs and encoded results. The existing conformance driver
also passed its 93 direct typed cases and 476 binary oracle controls per
implementation; the binary controls are not an inbound plugin API.

- [Raw PocketIC report](candidx-native-main.json), [CSV](candidx-summary.csv),
  [generated actor](candidx-main.mo), [manifest](candidx-cases.json).
- [Provenance and hashes](candidx-provenance.json), [plugin build metadata](candidx-build.json),
  [frozen runner](candidx-runner.mjs).
- [Conformance report](candidx-conformance.json).
- Fuzz reports: [0xcad1d](candidx-fuzz-cad1d.json), [0x5eedc0de](candidx-fuzz-5eedc0de.json).

Reproduce the comparison with `generate-comparison.py --suite main`, compile
using the packages described in the [benchmark guide](../../README.md), then
run with `--filter candid --trials 3`. The saved runner requires explicit
`--sdk-package` and `--canonicalizer` paths when invoked from this directory.
The [compiler adapter](../../../plugins/candidx/tests/candidx-moc.py) unwraps
Results only to preserve the legacy CandidX test-driver API. Native plugin
callers receive the Result directly.
