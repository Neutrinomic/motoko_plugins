#!/usr/bin/env python3
"""BLAKE3 MAC generation and full-tag verification over an official vector."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
sys.path.insert(0, str(BENCH))
from common import actor, blob

vectors = {
    int(parts[0]): parts[1:]
    for line in (BENCH / 'fixtures/blake3-official-vectors.txt').read_text().splitlines()
    if (parts := line.split())
}
tag = bytes.fromhex(vectors[1024][1][:64])
key = b'whats the Elvish word for friend'
assert len(key) == len(tag) == 32
setup = f'''transient let input : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024, func(i) {{Prim.natToNat8(i % 251)}}));
transient let key : Blob = {blob(key)};'''

# This local composition is deliberately not a new plugin API. Lengths are
# public; every byte of a correctly sized tag participates before the result.
verify = f'''
  transient let expected : Blob = {blob(tag)};
  func verifyMac(key : Blob, message : Blob, tag : Blob) : Bool {{
    if (tag.size() != 32) return false;
    let digest = switch (H.keyedHash(key, message)) {{
      case (#ok(value)) value;
      case (#err(_)) return false;
    }};
    var difference : Nat8 = 0;
    var i = 0;
    while (i < 32) {{
      difference := difference | (digest[i] ^ tag[i]);
      i += 1;
    }};
    difference == 0
  }};
  func changed(bytes : Blob, index : Nat) : Blob {{
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func(i) {{
      bytes[i] ^ (if (i == index) 1 else 0)
    }}))
  }};
'''
checks = '''
    assert verifyMac(key, input, expected);
    var i = 0;
    while (i < 32) {
      assert not verifyMac(key, input, changed(expected, i));
      i += 1;
    };
    assert not verifyMac(key, input, Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(31, func(i) { expected[i] })));
    assert not verifyMac(key, input, Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(33, func(i) { if (i < 32) expected[i] else 0 })));
    assert not verifyMac(changed(key, 0), input, expected);
    assert not verifyMac(key, changed(input, 0), expected);
'''

cases = []


def add(name, source, expected, notes):
    target = HERE / 'cases' / name / 'plugin/main.mo'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source)
    cases.append(dict(
        name=name, family='blake3-mac', implementation='plugin',
        comparison='shared-secret-mac', plugins=['blake3'],
        source=target.relative_to(BENCH).as_posix(), expected_hex=expected.hex(),
        notes=notes,
    ))


add('blake3-mac-generate-1024', actor(
    'import H "mo:fast/BLAKE3";', setup, '',
    'result := switch(H.keyedHash(key,input)){case(#ok(x))x;case(#err(_))Prim.trap("keyed")};',
), tag, 'Same workload and timed operation as cases/blake3-keyed-1024/native/main.mo. Expected tag is the first 32 bytes of the official 1024-byte keyed vector.')

for suffix, tag_expr, valid in [
    ('valid', 'expected', True),
    ('mismatch-first', 'changed(expected, 0)', False),
    ('mismatch-last', 'changed(expected, 31)', False),
]:
    add('blake3-mac-verify-1024-' + suffix, actor(
        'import H "mo:fast/BLAKE3";',
        setup + verify + '\n  transient var suppliedTag : Blob = "";',
        checks + '\n    suppliedTag := ' + tag_expr + ';',
        'result := verifyMac(key, input, suppliedTag);',
        'if (result) "\\01" else "\\00"', 'Bool', 'false',
    ), bytes([int(valid)]), 'Recompute keyedHash and compare all 32 tag bytes with XOR/OR; no mismatch-dependent early exit. Input/tag setup and correctness assertions run outside measurement.')

(HERE / 'cases.json').write_text(json.dumps(dict(cases=cases), indent=2) + '\n')
