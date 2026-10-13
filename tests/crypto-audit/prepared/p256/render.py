#!/usr/bin/env python3
"""Render the independent oracle corpus into public Motoko API tests."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
corpus = json.loads((HERE / "vectors.json").read_text())

def blob(value):
    return '"' + ''.join('\\' + value[i:i + 2] for i in range(0, len(value), 2)) + '"'

lines = [
    '// Generated from independent Python integer arithmetic by render.py.',
    'import P256 "mo:fast/P256";',
    'import Prim "mo:⛔";',
    'module {',
    '  public type Key = { compressed : Blob; uncompressed : Blob };',
    '  public type Vector = { key : Nat; digest : Blob; signature : Blob; expected : Bool };',
    '  public let keys : [Key] = [',
]
for key in corpus['keys']:
    lines.append('    { compressed = ' + blob(key['compressed']) + '; uncompressed = ' + blob(key['uncompressed']) + ' },')
lines.extend(['  ];', '  public let vectors : [Vector] = ['])
for case in corpus['verify']:
    lines.append('    // ' + case['label'])
    lines.append('    { key = ' + str(case['key']) + '; digest = ' + blob(case['digest']) + '; signature = ' + blob(case['signature']) + '; expected = ' + str(case['expected']).lower() + ' },')
lines.extend(['  ];', '  public let invalidKeys : [Blob] = ['])
for key in corpus['invalid_keys']:
    lines.append('    ' + blob(key) + ',')
lines.extend(['  ];', '  public let invalidSignatures : [Blob] = ['])
invalid_signatures = ['', '00' * 63, '00' * 65, '00' * 64]
order = 'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551'
for component in range(2):
    for value in ['00' * 32, order, 'ff' * 32]:
        signature = corpus['verify'][0]['signature']
        invalid_signatures.append(signature[:component * 64] + value + signature[(component + 1) * 64:])
for signature in invalid_signatures:
    lines.append('    ' + blob(signature) + ',')
lines.extend([
    '  ];',
    '  public func ok<T>(r : P256.Result<T>) : T {',
    '    switch r { case (#ok x) x; case (#err _) Prim.trap("prepared P256 audit: unexpected error") }',
    '  };',
    '  public func copy(b : Blob) : Blob {',
    '    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { b[i] }))',
    '  };',
    '  public func run() {',
    '    let prepared = Prim.Array_tabulate<P256.PreparedPublicKey>(keys.size(), func(i) {',
    '      ok(P256.preparePublicKey(copy(keys[i].compressed)))',
    '    });',
    '    let uncompressed = Prim.Array_tabulate<P256.PreparedPublicKey>(keys.size(), func(i) {',
    '      ok(P256.preparePublicKey(copy(keys[i].uncompressed)))',
    '    });',
    '    for (v in vectors.values()) {',
    '      assert P256.verifyPrehashPrepared(prepared[v.key], v.digest, v.signature) == #ok(v.expected);',
    '      assert P256.verifyPrehashPrepared(uncompressed[v.key], v.digest, v.signature) == #ok(v.expected);',
    '      assert P256.verifyPrehash(keys[v.key].compressed, v.digest, v.signature) == #ok(v.expected);',
    '    };',
    '    for (key in invalidKeys.values()) {',
    '      switch (P256.preparePublicKey(key)) {',
    '        case (#err(#invalidPublicKey)) {};',
    '        case _ Prim.trap("prepared P256 audit: malformed key accepted");',
    '      }',
    '    };',
    '    let first = vectors[0];',
    '    let p = prepared[first.key];',
    '    assert P256.verifyPrehashPrepared(p, "", "") == #err(#invalidDigest);',
    '    assert P256.verifyPrehashPrepared(p, first.digest, "") == #err(#invalidSignature);',
    '    for (signature in invalidSignatures.values()) {',
    '      assert P256.verifyPrehashPrepared(p, first.digest, signature) == #err(#invalidSignature);',
    '      assert P256.verifyPrehashPrepared(p, "", signature) == #err(#invalidDigest);',
    '    };',
    '    func identity<T>(x : T) : T { x };',
    '    let returned = identity({ values = [p]; read = func() : P256.PreparedPublicKey { p } });',
    '    assert P256.verifyPrehashPrepared(returned.values[0], first.digest, first.signature) == #ok(first.expected);',
    '    assert P256.verifyPrehashPrepared(returned.read(), first.digest, first.signature) == #ok(first.expected);',
    '    let verify = P256.verifyPrehashPrepared;',
    '    var sequence = 0;',
    '    func keyArg() : P256.PreparedPublicKey { assert sequence == 0; sequence := 1; p };',
    '    func digestArg() : Blob { assert sequence == 1; sequence := 2; first.digest };',
    '    func signatureArg() : Blob { assert sequence == 2; sequence := 3; first.signature };',
    '    assert verify(keyArg(), digestArg(), signatureArg()) == #ok(first.expected);',
    '    assert sequence == 3;',
    '  };',
    '}',
])
(HERE / 'Cases.mo').write_text('\n'.join(lines) + '\n')
(HERE / 'run').mkdir(exist_ok=True)
(HERE / 'run/independent.mo').write_text(
    '//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/p256 --sanity-checks\n'
    'import Cases "../Cases";\nCases.run();\n'
)
