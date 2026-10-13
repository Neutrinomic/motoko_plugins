Pinned source revision and original file digests are recorded in `UPSTREAM.json`.
All files are unchanged except:

- `src/hash/sha2small.c`: `br_sha256_init` assigns a null context vtable. This
  plugin uses only the direct `br_sha256_*` functions. Removing this unused
  function-pointer table reference avoids dynamic Wasm data relocation/startup.
- `src/rsa/rsa_i31_priv.c`: the bounded private-operation `tmp` workspace is
  cleared through volatile stores before successful return. Its workspace
  grows from eight to 37 factor-sized slots. Both unchanged `br_i31_modpow_opt`
  calls can then select their existing constant-time five-bit window at this
  fixed profile. The direct workspace is 7,700 bytes, versus 1,876 bytes for
  the screened two-bit configuration. This optimization
  applies to the ordinary direct API as well as the prepared-key comparison.
  The workspace is zero-initialized so the window lookup's otherwise unused
  even-word padding never reads indeterminate stack contents. The arithmetic
  primitive itself is unchanged.
- `src/rsa/rsa_i31_modulus.c`: the decoded factor workspace is likewise cleared
  before successful return. Earlier failure paths are unreachable for the
  adapter's prevalidated fixed1536-bit factors and configured3072-bit maximum.

The adapter in `../../src/rsa.c` specializes the upstream generic
`rsa_pss_sig_pad.c`, `rsa_pss_sig_unpad.c` and `mgf1.c` to SHA256, salt32 and
emBits3071, with direct hash calls. Their arithmetic and encoding rules are
RFC8017 EMSA-PSS. The generic vtable implementations are not compiled or shipped.
No changes are made to the i31 arithmetic algorithms.

The prepared adapter also orchestrates the unchanged i31 primitives with decoded
immutable factors and 1,716 words (6,864 bytes) of exponentiation scratch,
selecting the same five-bit window. It reuses the validated Montgomery public modulus and qInv,
and retains the final public-operation signature fault check.
