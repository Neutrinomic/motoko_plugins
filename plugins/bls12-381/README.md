# BLS12-381

This plugin supplies `mo:fast/BLS12381`: canonical group arithmetic, MSM,
RFC9380 maps and message hashing, pairing-product checks, and IC/Ethereum BLS
verification. Local signing, threshold protocols and KZG are outside this plugin.

G1 encodings are 48 bytes and G2 encodings are 96 bytes, using IETF compressed
flags and subgroup validation. G2 point encodings put imaginary x before real x.
Scalars are canonical 32-byte **big-endian** integers below the scalar order.
Field maps use canonical 48-byte big-endian Fp; Fp2 input is **real then imaginary**.
Group operations permit infinity. Signature keys and signatures must be nonidentity.

`verifyIC(key,message,signature)` uses the G1-signature/G2-key basic profile with
`BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_`. It verifies raw signed bytes; the
caller constructs protocol framing such as `ic-state-root` and verifies certificate
structure/delegations separately. `aggregateVerifyIC` enforces distinct messages
with exact byte comparisons and a bounded index sort for larger batches.

`verifyEthereum` uses G2 signatures/G1 keys and
`BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`. Proofs use
`BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`. Both aggregate entry points verify
every distinct byte-identical key/proof pair in each call before using its key.
A previously verified pair may be reused within that call; a different proof is
always checked. No result or native state is retained between calls. Repeated
messages up to 1024 bytes reuse their hash within the call. Longer messages
are hashed directly, bounding comparison work independently of message length. Aggregate
profiles execute in one native call: a bounded descriptor table borrows the original
Blobs, and validated keys and hash-to-curve points stay decoded until pairing. This
avoids packing and re-decoding intermediate points between group operations. All
external points still receive canonical, curve, subgroup and identity checks. There is
no unchecked assertion flag.
Callers construct Ethereum signing roots themselves. Raw group aggregation does
not prove key possession and should not be substituted for signature verification.

Group batches and pairing products contain at most 128 items. General aggregate
verification accepts 1..127 entries, reserving one pairing term for the signature;
fast aggregate verification accepts 1..128. Packed MSM takes matching point/scalar
counts. MSM is variable-time and accepts public scalars only. Two or three
terms use width-four Straus; four or more use adaptive signed Pippenger buckets; decoded-point scratch is bounded to
about 31 KiB at 128 G2 terms. Single-point multiplication continues to use the
upstream scalar-multiplication implementation. Pairing input concatenates 48-byte
G1 and 96-byte G2 for every term. Every term is decoded and subgroup-checked
before neutral terms are removed or equal G2 operands are combined. Empty
raw group sums/MSM produce infinity; empty pairing products are true; empty
signature batches are errors. Public hashing requires a nonempty explicit DST;
RFC9380 oversized DST normalization is supported. Errors are typed Motoko variants.

The runtime pins portable `bls12_381` 0.8.0, `sha2` 0.9.9 and `generic-array` 0.14.9.
These dependencies must not be described as independently audited. A shared
exceptional-zero G2 mapping helper corrects a defect in upstream 0.8.0 (also present
in 0.9.0); both direct mapping and full hashing take the corrected path. The helper
uses a fixed pre-cofactor curve point derived independently with py_ecc and checked
against the portable OCaml SWU/isogeny implementation. User points always use
subgroup-checked decoding. See runtime source and vector provenance for details.

All pointers are borrowed within one synchronous call. There is no retained native
state. Pairing precomputation uses bounded managed scratch via SDK host allocation;
MSM uses 33 stack bucket slots (at most 32 active magnitude buckets) plus
bounded managed decoded-input scratch. Two/three-term Straus uses at most
12 projective table entries and 768 signed digits on the stack.
Aggregate profiles use at most 6 KiB of stack for borrowed input descriptors, a
bounded vector of validated keys for Ethereum proofs, and the same bounded pairing
scratch. Other kernels use bounded stack storage. All compiler values and outputs use SDK
managed constructors. Interpreter semantics are independent portable OCaml using
the compiler's Num arithmetic, including full hashes and pairings.

Run the shared build/test suite as described in `docs/adding-a-plugin.md`.
Additional independent OCaml regressions from the compiler Nix environment:

```sh
../plugins/plugins/bls12-381/tests/reference/run.sh
../plugins/plugins/bls12-381/tests/reference/run-pairing.sh
```

Public Motoko tests are `packages/fast/tests/run/crypto-bls*.mo`; Ash coverage is
`packages/fast/tests/ash/BLS12381.mo`. Native runtime tests include official RFC9380
and Ethereum fixtures, an IC certificate signature, subgroup/identity/encoding
errors, PoP separation, allocation boundaries and unaligned immutable inputs.
