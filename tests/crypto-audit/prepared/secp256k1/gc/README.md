# Prepared secp256k1 GC audit

The canister retains all three opaque prepared types for keys 1, 3, and 6
through distinct transient actor, nested array/record, and suspended-frame
closure roots. It checks independently generated ECDSA/BIP340 signatures,
interleaves keys, rejects malformed auxiliary inputs, and reuses each cache
after failures and confirmed collection. Key 6 exercises odd-Y normalization.

From the candidate checkout, generate fixtures against the frozen plugin:

```sh
cd /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/secp256k1
python3 tests/crypto-audit/prepared/secp256k1/gc/generate.py --plugin /absolute/path/to/frozen/dist/secp256k1
python3 tests/crypto-audit/prepared/secp256k1/gc/verify-ash-provenance.py
```

Generation and the final GC actor passed; see [execution evidence](../evidence/ash-evidence.json).
The provenance check hashes the shared Ash copy without
compiling or launching PocketIC. After candidate freeze and an approved
heavy-test slot, invoke that copy with this unique absolute config path:

```sh
bun /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/ash-local/src/index.ts test /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/secp256k1/tests/crypto-audit/prepared/secp256k1/gc/PreparedSecp256k1GC.ash.json --verbose
```

Only the copied `src/binaries.ts` changes compiler selection, returning
`/srv/shared/code/motoko_experiments/prepared-crypto/sdk/bin/moc`, whose SDK
wrapper invokes `src/moc`. The original Ash checkout, global compiler/default
paths, `HOME`, `CODEX_HOME`, and `PATH` are unchanged. Ash retains its usual
`didc` and PocketIC resolution. Artifacts live in this config directory's
`.ash/`; the server-state key is the SHA1 of the absolute config path.

The copy's manifest is
[`ash-source-provenance.json`](/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/ash-source-provenance.json).
Before execution, `verify-ash-provenance.py` checks every copied-file hash,
the complete copied source inventory, the sole resolver modification, and the
explicit SDK selection. Pin its reported manifest SHA256 in execution evidence
alongside the frozen plugin/compiler hashes and test log. A source revision
alone does not identify this Ash copy because its source checkout had local edits.

Both pressure phases require more than 16 MiB reclaimed. The second follows
clearing all intentional handle roots and precedes rotated-key reprepare.
These assertions establish GC activity and successful retained-handle reuse;
they do not observe relocation or reclamation of every individual handle, or
prove erasure of prepared secret material. Ash metrics cover only the final
synchronous verification; they are not plugin benchmark results. The final run
passed with nine prepared objects (3,264 payload bytes, excluding managed headers
and the surrounding records/input vectors).
