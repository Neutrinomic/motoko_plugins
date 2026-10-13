# Round five codec audit

Scope: public `Base58`, `Base58Check`, `Bech32`, and `Segwit` modules, their
compiler extensions, and Base58/Bech32 native runtimes. Baseline: `cf55e909`.
No production defect established and no production change made.

Existing coverage already includes all generic BIP173/BIP350 valid and invalid
vectors, all eight BIP350 address/program pairs, superseded version-1+ Bech32
addresses, network-generic Segwit semantics, witness length/version boundaries,
Base58 NUL/Unicode rejection, resource bounds, and Bitcoin Core vectors. These
fixtures were checked against the primary
[BIP173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki#test-vectors)
and [BIP350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki#test-vectors)
tables. The new tests address public coverage gaps rather than duplicating
those tables or the previous large native corpora.

`packages/fast/tests/lib/CodecPropertiesCases.mo` is shared by the compiler
run fixture `crypto-codec-properties.mo` and the three-method Ash suite
`CodecProperties`:

| Check | Added coverage |
| --- | --- |
| `conversionPadding` | 6,144 independent bit-index comparisons across all 64 width pairs, 12 sizes, four payload shapes and both padding modes; includes valid zero tails, forbidden excessive zero tails, nonzero tails, and partial blocks in both specialized directions. Also 112 invalid final-symbol checks and six invalid-width precedence checks. |
| `bech32Substitutions` | 3,078 single-character replacements across four published generic vectors: every other lowercase HRP letter and every other data/checksum alphabet symbol. All must return `invalidChecksum`. The pinned upstream decoder verifies rejection by both accepted checksum variants. |
| `base58BoundariesAndChecksum` | All 70 nonalphabet ASCII bytes at eight digit/scalar boundary offsets, as suffixes and embedded characters, including exact first-invalid offsets through Base58Check (1,680 checks). Thirteen leading-zero lengths in both directions. All 200 single-bit mutations of a fixed 25-byte genesis Base58Check value, including every checksum bit. |

The conversion oracle reads individual bits and forms output groups without
the production accumulator/mask/block algorithm. The corruption fixture's
checksum and absence of collisions for the selected payload mutations are
independently checked with Python `hashlib`; its known Base58 value is checked
using Python integer division. Bech32 mutation expectations also have an
independent read-only review of the error syndromes for both checksum constants.

## Reproduction and results

Public Motoko execution passed: the existing Base58, Base58Check and Bech32
fixtures passed in the initial nine-fixture lane run; the new fixture passed
cleanly after removing two test-source warnings. Its typecheck, source
interpreter, IR interpreter, lowered interpreter, compilation, Wasm validation,
and Wasm execution phases all passed, with no golden output required. The
initial and targeted rerun logs are retained locally under
`_build/round5-codecs/{focused,new}.log`; unrelated Bitcoin fixture diagnostics
in those combined logs are handled by the parent lane. Ash wrappers are supplied
for the central combined runner; Ash execution is reported by integration.

Run the codec fixtures from the fixed SDK checkout's Nix environment with
`PLUGIN_REPO` set to the plugin checkout, its baseline `dist` populated, and
`packages/fast/.mops/core@2.5.0` pointing to Core 2.5.0:

```sh
export PATH="$PWD/bin:$PATH"
export MOTOKO_ROOT="$PWD"
test-runner -b -j2 "$PLUGIN_REPO/packages/fast/tests/run/crypto-codec-properties.mo" "$PLUGIN_REPO/packages/fast/tests/run/crypto-base58.mo" "$PLUGIN_REPO/packages/fast/tests/run/crypto-base58check.mo" "$PLUGIN_REPO/packages/fast/tests/run/crypto-bech32.mo"
```

The independent fixed-vector verifier passed with 200 Base58Check corruptions
and 3,078 Bech32 substitutions. Fetch the pinned MIT-licensed upstream reference
outside the source tree, then run from the plugin repository root:

```sh
mkdir -p _build/round5-codecs
curl -fsSL https://raw.githubusercontent.com/sipa/bech32/7a7d7ab158db7078a333384e0e918c90dbc42917/ref/python/segwit_addr.py -o _build/round5-codecs/segwit_addr.py
python3 tests/crypto-audit/round5/bitcoin/codecs/verify-vectors.py --bech32-reference _build/round5-codecs/segwit_addr.py
```

The verifier enforces reference SHA-256
`2884ce04a36c8374c4249177cd90e91e545ac73b5c9260307bbeb74ae2e9de0f` before importing it.

Validation uses unchanged baseline `dist` copies with every source and artifact
hash checked, compiler revision `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`, compiler
SHA-256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`,
and Core 2.5.0. No rebuild is required for these test-only changes.

## Review and limits

Independent read-only review found no concrete kernel, generator, registration,
padding, bounds, error-mapping, or pointer-lifetime defect. Base58 runtime
SHA-256 `259241b764a8c3ae9939c23bbb35b4927de850c4ac345efa6796b30dff423460`
and Bech32 runtime SHA-256
`35dff7164f937b74f544bd177bf48a83852b2ab54ad7f2f5e8ea753ec594faad`
match the sources covered by the round-two independent native/ASan audits.
The new fixtures therefore concentrate on the public bridge and composition.

This pass does not add public allocations near the 16 MiB conversion quota or
prove arbitrary GC forwarding behavior. Existing native boundary tests and the
central Ash validation remain separate evidence. One resource observation is
that Bech32 flattens text before rejecting oversized strings; this is not an
established correctness defect and was not changed.
