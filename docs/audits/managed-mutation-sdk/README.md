# Managed mutation SDK validation

Approved compiler commit: `abfba892fe4bd8fa2bc88e25dca0b895d35c1962`.
ABI remains **1**. The SDK adds typed array and record construction, reads, and
writes using Motoko's existing managed representation and GC barriers.

The [independent audit](audit.md) covers static rejection, evaluation order,
alias identity, subtyping, reentry, and mutation during incremental GC. Two
independent programs passed source, IR, lowered IR, and Wasm execution. A
fragmented-heap actor passed 16 mutation messages, observing Mark, Evacuate,
and Update phases and actual movement of retained arrays.

- [Artifact manifest](artifact-manifest.json): candidate sources and archived
  independent fixtures, outputs, and hashes. These files are preserved unchanged.
- [Committed manifest](committed-manifest.json) and
  [committed validation](committed-validation.log): the approved commit passed
  all 51 SDK fixtures and packaging validation after the commit.
- [Canonical validation](canonical-validation.log): the same suite and packaging
  checks passed again in the canonical checkout used for plugin builds.

The private and canonical compiler binaries are both Release builds of the
approved commit. Their executable code and data sections match; embedded ELF
library search paths differ by checkout location, so their complete binary
hashes differ. The private binary's SHA-256 is
`bc3c86eaa88a4112832377e798032a21f3a0111c5103b1a41b00dc8692660f6f`;
the canonical binary's is
`a5a68803ecc8d48509c77052889f05eb8b5e3e983ee55b2027e9689939d79498`.
New mutable-map measurements use the canonical binary. Earlier plugin
benchmarks retain their original compiler provenance.

Verify the archived successful execution stages with:

```sh
python3 docs/audits/managed-mutation-sdk/verify.py
```

The audit's read-only GC probes are test artifacts, not production SDK APIs.
This report establishes mutation correctness; it makes no map performance claim.
