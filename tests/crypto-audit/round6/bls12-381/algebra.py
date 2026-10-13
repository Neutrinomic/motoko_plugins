#!/usr/bin/env python3
"""Independent integer/polynomial checks for the BLS round-six formulas.

Uses only Python's integer arithmetic, not the Rust arithmetic being tested.
Pass the candidate vendored bls12_381 directory as the sole argument.
"""
import json
from pathlib import Path
import re
import sys

P = int("1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab", 16)
R = pow(2, 384, P)
X = -0xD201000000010000
vendor = Path(sys.argv[1])


def fp2_mul(a, b):
    return ((a[0] * b[0] - a[1] * b[1]) % P,
            (a[0] * b[1] + a[1] * b[0]) % P)


def fp2_pow(a, n):
    out = (1, 0)
    while n:
        if n & 1:
            out = fp2_mul(out, a)
        a = fp2_mul(a, a)
        n >>= 1
    return out


# Polynomial represented by (power of signed x, power of p) -> integer.
def add(*polys):
    out = {}
    for poly in polys:
        for power, coefficient in poly.items():
            out[power] = out.get(power, 0) + coefficient
    return {power: coefficient for power, coefficient in out.items() if coefficient}


def scale(poly, coefficient):
    return {power: value * coefficient for power, value in poly.items() if value * coefficient}


def shift(poly, x=0, p=0):
    return {(i+x, j+p): coefficient for (i, j), coefficient in poly.items()}


# Exponents after the common easy part, using r as the common base.
# Multiplication adds exponents; conjugation negates them in this subgroup.
r = {(0, 0): 1}
t2 = r
t1 = scale(t2, -2)
t3 = shift(t2, x=1)
t4 = scale(t3, 2)
t5 = add(t1, t3)
t1 = shift(t5, x=1)
t0 = shift(t1, x=1)
t6 = shift(t0, x=1)
t6 = add(t6, t4)
t4 = shift(t6, x=1)
t5 = scale(t5, -1)
t4 = add(t4, t5, t2)
t5 = scale(t2, -1)
t1 = shift(add(t1, t2), p=3)
t6 = shift(add(t6, t5), p=1)
t3 = shift(add(t3, t0), p=2)
old = add(t3, t1, t6, t4)

y0 = scale(r, 2)
y1 = add(shift(r, x=1), scale(r, -1))
y2 = shift(y1, x=1)
y1 = add(scale(y1, -1), y2)
y2 = shift(y1, x=1)
y1 = add(shift(y1, p=1), y2)
r = add(r, y0)
y0 = shift(y1, x=1)
y2 = shift(y0, x=1)
y0 = shift(y1, p=2)
y1 = add(scale(y1, -1), y2, y0)
new = add(r, y1)
assert old == new, (old, new)
expected = 3 + (X - 1)**2 * (P + X) * (P**2 + X**2 - 1)
assert sum(coefficient * X**i * P**j for (i, j), coefficient in new.items()) == expected

source = (vendor / "src/fp12.rs").read_text()
constant_count = 0
for j in (1, 2, 4, 5):
    match = re.search(rf"const C{j}: Fp = Fp::from_raw_unchecked\(\[(.*?)\]\);", source, re.S)
    assert match, f"missing C{j}"
    limbs = [int(s.replace("_", ""), 16) for s in re.findall(r"0x[0-9a-f_]+", match[1])]
    assert len(limbs) == 6
    actual = sum(limb << (64 * i) for i, limb in enumerate(limbs))
    power = fp2_pow((1, 1), j * (P * P - 1) // 6)
    assert power[1] == 0
    assert 0 <= actual < P
    assert actual == power[0] * R % P, f"incorrect C{j}"
    constant_count += 1
assert fp2_pow((1, 1), 3 * (P * P - 1) // 6) == (P - 1, 0)
assert sum(1 << bit for bit in (63, 62, 60, 57, 48, 16)) == -X

print(json.dumps({
    "hard_part_exact_polynomial_equality": True,
    "hard_part_signed_x": str(X),
    "fp2_independently_computed_montgomery_constants": constant_count,
    "third_coefficient_is_minus_one": True,
    "fixed_exponent_bits_verified": True,
    "basis_note": "[1,v,v²,w,vw,v²w] = [w^0,w^2,w^4,w^1,w^3,w^5]",
}, indent=2))
