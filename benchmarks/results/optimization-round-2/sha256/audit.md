# Independent SHA-256 audit, round 2

**Approved: retain the existing implementation. No unresolved findings.**
Production source and tests match plugins baseline
`0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152` exactly. Neither rejected pilot remains
in production. This round establishes **no new performance gain**.

The auditor independently checked the source, package artifacts, measured actor,
raw results, rejected patches, and report. The reviewed runtime source hash is
`3075fbac11f627825828d84ab9ec993dcc015bd0abd41da6e0c2408aacb33f78`.
Baseline and rebuilt final runtime Wasm are byte-identical:
`0d8a6c3e6a1fdc20d7878da83b1d8c066e31a06049c305db80c149dabad0bf9c`.
Both complete benchmark actors have hash
`e5061f236634e6d39054d77221af5a0d5be1e96b5e51901859b8dfbf6836faec`.
The rebuilt native compiler extension has different path metadata; this is not
a claim that the complete packages are byte-identical.

## Correctness and memory review

- The generic kernel reads complete 64-byte blocks and uses a zero-initialized
  128-byte tail. The remainder is below 64, and the 55/56 transition correctly
  selects one or two padding blocks. The 32/64-byte specializations retain their
  constant padding. SHA words, bit length, and digest words use big-endian order.
- Nonempty paths write exactly eight unaligned 32-bit words; the empty path
  writes four unaligned 64-bit words. All 32 output bytes are initialized without
  first creating a reference to the uninitialized Blob payload. No word-aligned
  input or output is assumed, and the input is never modified.
- The compiler generator allocates the fresh result before obtaining input and
  output payload addresses and returns a managed Blob. The leaf runtime has no
  allocation, external function import, callback, suspension, retained pointer,
  or GC safepoint. Existing forwarding/allocation barriers remain in use.
- The fixed-size helper's inline const assertion already checks its permitted
  lengths at compilation. Independently compiling a scratch instantiation with
  length 31 fails with E0080; no runtime check or abstraction was added.

A separate host probe generated **536 Python hashlib oracle vectors**: two
binary patterns at every length 0 through 257, plus 511/512/513, 1023/1024/1025,
65535/65536/65537, and 1048576. It made **8,576 exported ABI calls**, crossing input
and output offsets 0/1/3/7. Every digest, input-preservation assertion, and output
sentinel passed. The three existing Rust tests passed in the same independent
run. This used `rustc 1.91.1 --edition=2024 --test -O`; it is correctness evidence,
not an IC performance measurement. Scratch probe source and logs are under
`_build/opt2-sha256/audit/` in the audit worktree.

## Measurement and evidence review

All 18 benchmark inputs were independently regenerated and checked against
Python hashlib. The **216 baseline/final records** cover 18 sizes, two
implementations, three trials, and two builds. All paired instruction and
allocation counts match exactly; every output hash matches its expected digest,
and all phases report zero reclaimed bytes. At 1 MiB both plugin builds use
78,124,848 instructions and 56 allocated bytes, against Mops sha2's 323,721,060
instructions and 1,008 bytes. Allocation counters describe cumulative managed
allocation, not live or peak memory; later message-end GC is outside timing.

Both rejected patches were independently applied to baseline copies and
reproduced their recorded source hashes. Their runtime/actor hashes and all
28 one-trial pilot records were checked. Paired loads increase 1 MiB instructions
by 3.838%; the counted selector increases them by 0.357%, with the reported
boundary regressions. Neither improves allocation or Wasm size. Rejecting both
avoids additional complexity for slower code.

The compiler executable pin, all source/archive hashes, and all 100 frozen
sha2/core dependency hashes were reconciled. The archived runner checks actual
digest bytes outside measurement, and actor setup is outside the timed call.
The report's validator passes without modifying either CSV. Reviewed the seven
passing Motoko fixtures, including interpreters, Wasm, composition, argument
rejection, and GC stress; the full fixtures and PocketIC matrix were not
redundantly rerun during this audit. See the [round report](README.md) for the
complete results and reproduction commands.
