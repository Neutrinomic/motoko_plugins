# Independent integration audit

Approved for compiler `128a41c060d473e4307dbfcce88b4587312a29b6` and the five
integrated packages recorded in `build.json`. No unresolved finding. This audit
covers the six listed actors; it introduces no new benchmark measurements.

Independently read the original and integrated Wasm binaries and checked their
bytes at explicit offsets, without relying on the comparison script's verdict.
For each binary, exactly two equal-length version-string windows change: one in
passive data and one in the compiler custom section. Every byte outside those
windows is identical. A separate Wasm section parser verified all section
boundaries, lengths, changed-section identities, and complete code-section
identity. All **9,690 function bodies**, including initializers, are unchanged.
The exact offsets and hashes are recorded in [audit-proof.json](audit-proof.json).

Verified the original source/cases/Wasm against historical trial hashes and the
integrated binary against its build hash. Checked all nine package artifacts,
84 package source-hash entries, compiler/source/support pins, all 507 locked
native dependency files, and native CandidX source pins. Each package's own
sources and runtime bytes match its accepted measured candidate. The canonical
compiler is clean at the recorded revision; the new managed-mutation experiment
is outside this proof.

Independently applied each unfiltered WAT unified diff to its original full WAT
text and obtained the exact integrated WAT text. Both WAT hashes and every raw
diff hash match `proof.json`. The six complete proof records agree with the
independent byte/section checks. Historical performance results retain their
original compiler labels and binary hashes; no trial was relabeled. The equal
executable code and unchanged memory layout support carrying these particular
actors' comparisons into the integrated package report.

All copied validation logs match their original files and recorded hashes:
46 SDK fixtures, 54 plugin Motoko fixtures, 57 Rust tests, packaging checks,
compiler build, and the recorded archive verification passed. This review
performed no source edits, compiler/package builds, or duplicate benchmarks.
