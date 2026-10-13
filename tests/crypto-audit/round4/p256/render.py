#!/usr/bin/env python3
"""Render independent round-four vectors through the public Motoko module."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def blob(value):
    return '"' + ''.join('\\' + value[i:i + 2] for i in range(0, len(value), 2)) + '"'


def main():
    vectors = json.loads((HERE / "vectors.json").read_text())
    keys = list(dict.fromkeys(row["public"] for row in vectors["verify"]))
    lines = ['import P256 "mo:fast/P256";', 'import Prim "mo:⛔";', 'module {',
             '  public func ok<T>(r : P256.Result<T>) : T { switch r { case (#ok x) x; case (#err _) Prim.trap("round4 P256 oracle") } };',
             '  public func run() {',
             '    let keys : [Blob] = [' + ', '.join(map(blob, keys)) + '];',
             '    let prepared = Prim.Array_tabulate<P256.PreparedPublicKey>(keys.size(), func(i) { ok(P256.preparePublicKey(keys[i])) });',
             '    let verify : [(Nat, Blob, Blob, Bool)] = [']
    for row in vectors["verify"]:
        lines.append('      (' + ', '.join([str(keys.index(row["public"])), blob(row["digest"]),
                                          blob(row["signature"]), str(row["expected"]).lower()]) + '),')
    lines += ['    ];', '    for ((key, digest, signature, expected) in verify.values()) {',
              '      assert P256.verifyPrehash(keys[key], digest, signature) == #ok(expected);',
              '      assert P256.verifyPrehashPrepared(prepared[key], digest, signature) == #ok(expected);',
              '    };', '    let sign : [(Blob, Blob, Blob, Blob)] = [']
    for row in vectors["sign"]:
        lines.append('      (' + ', '.join(blob(row[key]) for key in ['secret', 'digest', 'signature', 'public']) + '),')
    lines += ['    ];', '    for ((secret, digest, signature, publicKey) in sign.values()) {',
              '      assert P256.signPrehash(secret, digest) == #ok(signature);',
              '      assert P256.derivePublicKey(secret) == #ok(publicKey);',
              '    };', '    let derive : [(Blob, Blob, Blob)] = [']
    boundary_bits = {0, 1, 15, 16, 31, 32, 47, 48, 63, 64, 127, 128, 191, 192, 223, 224, 254, 255}
    for index, row in enumerate(vectors["derive"]):
        if index // 2 in boundary_bits:
            lines.append('      (' + ', '.join(blob(row[key]) for key in ['secret', 'public', 'uncompressed']) + '),')
    lines += ['    ];', '    for ((secret, compressed, uncompressed) in derive.values()) {',
              '      assert P256.publicKey(secret, true) == #ok(compressed);',
              '      assert P256.publicKey(secret, false) == #ok(uncompressed);',
              '    };', '  };', '}']
    (HERE / "Cases.mo").write_text('\n'.join(lines) + '\n')
    (HERE / "run").mkdir(exist_ok=True)
    (HERE / "run/independent.mo").write_text(
        '//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/p256 --sanity-checks\n'
        'import Cases "../Cases";\nCases.run();\n')


if __name__ == "__main__":
    main()
