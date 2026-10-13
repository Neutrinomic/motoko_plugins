# Predicate allocation followup

Approved source and execution of the final predicate bridge. The compiler emits
no empty Blob allocation for boolean operations. All arguments are still
evaluated eagerly in order and error precedence is unchanged. The runtime
skips `copy_nonoverlapping` entirely at zero output capacity before accepting a
null output pointer; Rust requires nonnull pointers even for zero-length copies.

Validation: the previous eight independent fixtures pass on the new artifact,
and the additional effect/error/alias fixture passes all five runner phases.
All nine public-module Ash methods also pass. The GC method was extended to
retain predicate result variants alongside the existing input/output Blobs,
and requires more than 16 MiB of actual reclamation. No runtime findings remain.

The new test initially mixed two distinct intrinsic controls in one array;
that is unsupported by the existing intrinsic API. The corrected test uses
homogeneous inferred alias arrays. Initial logs are preserved, and the final
evidence explicitly records the corrected targeted rerun rather than claiming
a single clean sweep. The main audit's earlier artifact and evidence are intact.

`prepare_predicate.py` in the parent directory generates the extra runner
fixture and derives the nine-method Ash actor from the existing module suite.
Logs and generated inputs are gzip-compressed; retained-files.json distinguishes
compressed and uncompressed hashes. Fresh paired performance measurements are
owned by the implementation/integration agents.
