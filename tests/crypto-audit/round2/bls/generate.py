#!/usr/bin/env python3
"""Independent round2 BLS regressions; oracle: Ethereum py_ecc 8.0.0 only."""
from pathlib import Path
from hashlib import sha512
import json
from py_ecc import __version__
from py_ecc.bls.point_compression import compress_G1, compress_G2
from py_ecc.optimized_bls12_381 import G1, G2, multiply, curve_order

assert __version__ == '8.0.0'
HERE = Path(__file__).resolve().parent
R = curve_order
rows = []
def point(p, g):
    c = compress_G1(p) if g == 1 else compress_G2(p)
    return c.to_bytes(48, 'big') if g == 1 else b''.join(v.to_bytes(48, 'big') for v in c)
def scalar(n): return n.to_bytes(32, 'big')
def random(i, label): return int.from_bytes(sha512(label + i.to_bytes(4, 'big')).digest(), 'big') % R
def emit(name, op, a=b'', b=b'', c=b'', out=b'', status=0):
    rows.append(dict(name=name, op=op, a=a.hex(), b=b.hex(), c=c.hex(), expected=out.hex(), status=status))

# Known independent discrete logs let the oracle calculate a *single* expected
# multiplication, without copying Straus, Booth, or Pippenger from the plugin.
for g, base in [(1, G1), (2, G2)]:
    identity = point(multiply(base, 0), g)
    factors = [0, 1, R-1, 19, 19] + [random(i, b'round2-point') for i in range(5, 128)]
    points = [point(multiply(base, n), g) for n in factors]
    for n in [2, 3, 4, 5, 17, 65, 128]:
        for variant in range(3):
            scalars = [random(i + variant*128, b'round2-scalar') for i in range(n)]
            if variant == 0:
                scalars = [R-1, (1 << 254)-1, (1 << 254)+1, 0, 1][:n] + scalars[5:]
            if variant == 1:
                scalars = [((1 << ((i*29+7) % 254))-1) for i in range(n)]
            # Small Straus cases must exercise nonidentity operands too.
            fs = factors[3:3+n] if n < 4 else factors[:n]
            ps = points[3:3+n] if n < 4 else points[:n]
            expected = sum(f*s for f, s in zip(fs, scalars)) % R
            emit(f'fullwidth-g{g}-n{n}-v{variant}', 6+g, b''.join(ps), b''.join(map(scalar, scalars)), out=point(multiply(base, expected), g))
    for n in [2, 3]:
        for where in [0, n-1]:
            ps = points[3:3+n].copy(); ss = [scalar(R-1)]*n
            ps[where] = bytes(48*g)
            emit(f'straus-malformed-point-g{g}-n{n}-i{where}', 6+g, b''.join(ps), b''.join(ss), status=2)
            ps = points[3:3+n].copy(); ss[where] = scalar(R)
            emit(f'straus-malformed-scalar-g{g}-n{n}-i{where}', 6+g, b''.join(ps), b''.join(ss), status=3)
        ps = points[3:3+n].copy(); ps[-1] = bytes(48*g)
        ss = [scalar(R)] + [scalar(1)]*(n-1)
        emit(f'straus-error-order-g{g}-n{n}', 6+g, b''.join(ps), b''.join(ss), status=3)
    emit(f'canonical-identity-g{g}', g, identity, out=identity)
    for index in [0, 1, 48*g-1]:
        changed = bytearray(identity); changed[index] ^= 1
        emit(f'identity-mutation-g{g}-i{index}', g, bytes(changed), status=2)
    emit(f'empty-msm-nonempty-scalar-g{g}', 6+g, b'', scalar(1), status=1)
    emit(f'empty-aggregate-g{g}', 16+g, out=identity)

# Pairing results follow independent exponent bilinearity. Duplicate Q terms
# appear apart, with cancelling P, identities, and multiple groups.
g1 = {i: point(multiply(G1, i % R), 1) for i in [0, 1, -1, 2, -2, 5, -5, 9]}
g2 = {i: point(multiply(G2, i), 2) for i in [0, 1, 2, 7]}
def pairs(items): return b''.join(g1[p] + g2[q] for p, q in items)
for name, items in [
    ('nonadjacent-cancellation', [(1,1),(5,7),(-1,1),(-5,7)]),
    ('nonzero-repeated', [(1,2),(5,7),(1,2),(-5,7)]),
    ('cancel-then-resume', [(1,1),(-1,1),(2,1),(-2,1)]),
    ('mixed-neutral', [(0,7),(5,0),(1,2),(-1,2)]),
    ('cross-group-cancel', [(2,1),(-1,2)]),
    ('maximum-identical', [(1,7),(-1,7)]*64),
    ('maximum-three-groups', ([(1,1),(2,2),(5,7),(-1,1),(-2,2),(-5,7)]*21)+[(0,1),(9,0)]),
]:
    expected = sum(p*q for p,q in items) % R == 0
    emit('pairing-'+name, 13, pairs(items), out=bytes([expected]))
for neutral_group in [1,2]:
    for where in [0,1,3]:
        items = [g1[1]+g2[1], g1[-1]+g2[1], g1[0]+g2[0], g1[0]+g2[0]]
        items[where] = g1[0]+bytes(96) if neutral_group == 1 else bytes(48)+g2[0]
        emit(f'pairing-neutral-invalid-g{neutral_group}-i{where}', 13, b''.join(items), status=2)

(HERE/'vectors.tsv').write_text('\n'.join('\t'.join(str(v[k]) for k in ['name','op','a','b','c','status','expected']) for v in rows)+'\n')
def mo(h): return '"'+''.join('\\'+h[i:i+2] for i in range(0,len(h),2))+'"'
ops = {1:('validateG1',1),2:('validateG2',1),7:('g1Msm',2),8:('g2Msm',2),13:('pairingCheck',1),17:('g1Aggregate',1),18:('g2Aggregate',1)}
errors = {1:'invalidLength',2:'invalidPoint',3:'invalidScalar'}
lines = ['import B "mo:fast/BLS12381";', 'import P "mo:⛔";']
for v in rows:
    name, arity = ops[v['op']]
    args = ','.join(mo(v[k]) for k in ['a','b','c'][:arity])
    expected = '#err(#'+errors[v['status']]+')' if v['status'] else '#ok('+('true' if v['expected']=='01' else 'false')+')' if v['op']==13 else '#ok('+mo(v['expected'])+')'
    lines += ['// '+v['name'], f'assert B.{name}({args}) == {expected};']
lines += [f'P.debugPrint("independent round2 BLS regressions passed: {len(rows)}");']
(HERE/'regressions.mo').write_text('\n'.join(lines)+'\n')
(HERE/'vector-provenance.json').write_text(json.dumps(dict(oracle='Ethereum py_ecc '+__version__, cases=len(rows), source='https://github.com/ethereum/py_ecc/tree/v8.0.0', expected_msm='independent scalar linearity and py_ecc single multiplication', expected_pairing='bilinearity exponent sum modulo r', test_only_deterministic_secrets=True), indent=2)+'\n')
print(len(rows), 'independent regression vectors')
