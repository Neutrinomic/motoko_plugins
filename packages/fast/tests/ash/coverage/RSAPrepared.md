# RSA prepared-key test coverage

The eight Ash methods import `mo:fast/RSA` and load only the `rsa` plugin,
with `--force-gc --sanity-checks`. Prepared public and secret keys are distinct
nominal types. They are immutable managed values and cannot be serialized,
sent as actor arguments or saved in stable actor state. The GC test stores
handles in a **transient** actor field, local variables and typed alias arrays.

| Test | Coverage |
| --- | --- |
| `test_public_preparation_and_verification` | Exact independent OpenSSL signature, direct/prepared parity, message and digest mismatch, zero signature. |
| `test_secret_preparation_and_exact_prehash_signature` | Exact OpenSSL answer from prepared private context, verified through prepared and direct public paths. |
| `test_exact_message_signature_and_changed_salt` | Exact message signature, changed salt produces a different valid signature. |
| `test_factory_rejections` | Empty, short, long, zero and malformed public/secret keys; all five CRT components, factor top bits, successful recovery. |
| `test_hot_operation_errors` | Digest-before-salt/signature ordering; fixed lengths; signature integer equal to modulus rejected. |
| `test_aliases_and_evaluation_order` | Inferred factory alias, ordinary typed callback wrapper, typed handle arrays, left-to-right exactly-once evaluation. |
| `test_drop_contexts_collect_and_prepare_again` | Create and use both contexts in a completed async frame; clear their sole escaping transient field, observe later GC activity, then prepare fresh contexts and reproduce the exact signature without hidden native state. |
| `test_prepared_handles_survive_real_collection` | Factories consume dynamic raw-key copies that remain intact while both prepared contexts survive 13 asynchronous boundaries, later preparations and failed calls; exact signing after over 4 MiB confirmed reclamation. |

Fixture provenance is shared with [the direct RSA suite](RSA.md). Exact answers
come from Node.js/OpenSSL rather than the plugin. The ordinary
`tests/run/crypto-rsa-prepared.mo` covers every prepared operation and typed
aliases in interpreter and generated Wasm modes. `tests/fail/crypto-rsa-prepared-*`
reject raw-Blob forgery, public/secret confusion, exposing a handle as a Blob,
Candid serialization and shared/stable escape.

The GC test precedes dynamic public/private raw-key copies and preparation with
1 MiB of dead data. It checks both raw inputs remain equal to their fixtures
before and after collection, alongside the prepared handles. It allocates 72 MiB
of disposable pressure over nine continuations and adds four settling
continuations. It observes heap growth and requires `rts_reclaimed()` to
increase by more than 4 MiB. Both prepared contexts are used afterward; signing
must still return the exact independent signature. These are GC correctness
checks, not isolated performance measurements or a proof of every GC schedule.
They do not imply secret erasure: managed immutable contexts and original
private-key Blobs may remain in memory until reclaimed, and reclamation does
not promise zeroization. Transient contexts must be prepared again on upgrade.

The separate drop/reprepare method has its own transient field and requires no
test ordering. Its initial async frame returns only unit; the next continuation
clears the field and yields again before applying GC pressure. It observes
over 4 MiB of later reclamation and successfully signs/verifies with fresh
contexts. This does not prove reclamation of the particular discarded context
objects or erasure of their secret bytes.

Run after building the matching prepared-type SDK and plugin:

```sh
scripts/test-ash.sh --ash-source /srv/shared/code/ash RSAPrepared
```

Validated on 2026-10-13: all eight prepared Ash methods passed, with zero
failures or skips. Both lifecycle methods satisfied their observed-GC
assertions. The direct RSA suite also passed all nine methods. The two package
smoke tests passed through `test-runner`; all six negative diagnostics were
reviewed, then passed again without accepting expectations.

The selected SDK was `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`, compiler
SHA-256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
The tested artifacts were:

- `plugin.cmxs`: `9576e6c81e74a4e80537f4fe29ca26db643bf0e1dff26115b96e5ec9bb21228e`
- `runtime.wasm`: `6d1ccca08f869a499c27e9dc9bb3103f3d4377cd580db0b19d90f7d301b5ebba`

Local execution logs and per-run compiler/tool/test-source hashes are under
`_build/prepared-validation/logs/`; the exact phase inventory is in
`_build/prepared-validation/validation-summary.json`. The isolated Ash source
copy changed only compiler resolution to the selected SDK; global binaries
were unchanged.
