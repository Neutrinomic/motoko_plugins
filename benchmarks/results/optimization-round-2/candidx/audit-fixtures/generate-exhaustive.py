"""Independent canonical-byte oracle for every subset across bitmap boundaries."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--plugin', type=Path, required=True)
parser.add_argument('--out', type=Path, default=ROOT / 'run' / 'candidx-bitmap-exhaustive.mo')
args = parser.parse_args()
PLUGIN = args.plugin.resolve()
selected = [0, 31, 32, 63, 64, 95, 127, 128]
types = ['Nat', 'Bool', 'Nat8', 'Text']
opcodes = [-3, -2, -5, -15]

def leb(n):
    result = bytearray()
    while n >= 128:
        result.append((n & 127) | 128)
        n >>= 7
    result.append(n)
    return result

def payload(i):
    if i % 4 == 0:
        return f'#_{i}_({128+i})', leb(128+i)
    if i % 4 == 1:
        return f'#_{i}_(true)', b'\x01'
    if i % 4 == 2:
        return f'#_{i}_({i})', bytes([i])
    return f'#_{i}_("x{i}")', leb(len(f'x{i}')) + f'x{i}'.encode()

lines = [f'//MOC-FLAG --plugin {PLUGIN}', 'import Prim "mo:⛔";',
         'type Choice = { ' + '; '.join(f'#_{i}_ : {types[i % 4]}' for i in range(129)) + ' };']
for mask in range(256):
    ids = [i for j, i in enumerate(selected) if mask >> j & 1]
    order = list(reversed(ids))
    if len(ids) > 1:
        order += ids + [ids[-1], ids[0]]
    header = bytearray(b'DIDL')
    if not ids:
        header += bytes([1, 0x6d, 0x6f, 1, 0, 0])
    else:
        header += bytes([2, 0x6d, 1, 0x6b]) + leb(len(ids))
        for i in ids:
            header += leb(i) + bytes([opcodes[i % 4] & 127])
        header += bytes([1, 0]) + leb(len(order))
        for i in order:
            header += leb(ids.index(i)) + payload(i)[1]
    expected = ''.join('\\' + format(x, '02x') for x in header)
    values = ', '.join(payload(i)[0] for i in order)
    lines.append(f'assert Prim.to_candid_canonical([{values}] : [Choice]) == #ok("{expected}");')
lines += [
    '// Shared group occupies word 1 in Big and word 0 in Small.',
    'type Big = { ' + '; '.join(f'#_{i}_ : Nat' for i in [*range(64), *range(128, 192)]) + ' };',
    'type Small = { ' + '; '.join(f'#_{i}_ : Nat' for i in range(128, 192)) + ' };',
    'assert Prim.to_candid_canonical([#_128_(0), #_191_(1)] : [Big]) == Prim.to_candid_canonical([#_128_(0), #_191_(1)] : [Small]);',
    '// Equal labels with different primitive opcodes must not share a helper.',
    'assert Prim.to_candid_canonical([#_0_(0), #_1_(1)] : [{#_0_ : Nat; #_1_ : Nat}]) == #ok("DIDL\\02\\6d\\01\\6b\\02\\00\\7d\\01\\7d\\01\\00\\02\\00\\00\\01\\01");',
    'assert Prim.to_candid_canonical([#_0_(false), #_1_(true)] : [{#_0_ : Bool; #_1_ : Bool}]) == #ok("DIDL\\02\\6d\\01\\6b\\02\\00\\7e\\01\\7e\\01\\00\\02\\00\\00\\01\\01");',
]
output = args.out
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text('\n'.join(lines) + '\n')
print(f'{output}: 256 subsets with independent byte expectations')
