#!/usr/bin/env python3
"""Reproduce P-256 projective-verification boundaries using Python integers.

No plugin, RustCrypto, external package, random source, or secret key is used.
The fixture public key is Q = r^-1 R, with digest zero and signature s = 1.
"""

import argparse
import hashlib
import json
from pathlib import Path


P = int("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16)
N = int("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)
B = int("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16)
G = (
    int("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296", 16),
    int("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5", 16),
)


def on_curve(point):
    if point is None:
        return True
    x, y = point
    return 0 <= x < P and 0 <= y < P and (y * y - x * x * x + 3 * x - B) % P == 0


def add(left, right):
    if left is None:
        return right
    if right is None:
        return left
    x1, y1 = left
    x2, y2 = right
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if x1 == x2:
        slope = (3 * x1 * x1 - 3) * pow(2 * y1, -1, P) % P
    else:
        slope = (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (slope * slope - x1 - x2) % P
    result = (x3, (slope * (x1 - x3) - y1) % P)
    assert on_curve(result)
    return result


def multiply(point, scalar):
    assert scalar >= 0
    result = None
    while scalar:
        if scalar & 1:
            result = add(result, point)
        point = add(point, point)
        scalar >>= 1
    return result


def point_with_x(x):
    assert 0 <= x < P and P % 4 == 3
    square = (pow(x, 3, P) - 3 * x + B) % P
    y = pow(square, (P + 1) // 4, P)
    result = (x, y)
    assert on_curve(result), "Requested x has no curve point"
    return result


def compressed(point):
    x, y = point
    return f"{2 + (y & 1):02x}{x:064x}"


def verify(public_key, digest, r, s):
    if not (0 < r < N and 0 < s < N) or public_key is None:
        return False
    inverse = pow(s, -1, N)
    result = add(multiply(G, digest * inverse % N), multiply(public_key, r * inverse % N))
    return result is not None and result[0] % N == r


def generate():
    assert 0 < N < P < 2 * N < 2**257
    assert on_curve(G) and multiply(G, N) is None
    specifications = [
        (
            "rare_n_plus_3", N + 3, 3, True,
            "Valid second candidate: affine x = n + 3, signature r = 3.",
        ),
        (
            "near_p_minus_3", P - 3, P - N - 3, True,
            "Valid second candidate close to p: affine x = p - 3.",
        ),
        (
            "reject_field_wrap", 0, P - N, False,
            "Invalid: r+n=p must not reduce to affine x=0 modulo p.",
        ),
        (
            "reject_limb_wrap", 0, 2**256 - N, False,
            "Invalid: r+n=2^256 must not truncate to affine x=0.",
        ),
    ]
    vectors = []
    for label, x, r, expected, purpose in specifications:
        assert 0 < r < N
        target = point_with_x(x)
        assert multiply(target, N) is None
        public_key = multiply(target, pow(r, -1, N))
        assert public_key is not None and on_curve(public_key)
        assert multiply(public_key, r) == target
        assert verify(public_key, 0, r, 1) == expected
        vectors.append({
            "label": label,
            "purpose": purpose,
            "public_key": compressed(public_key),
            "digest": "00" * 32,
            "signature": f"{r:064x}{1:064x}",
            "expected_valid": expected,
            "computed_point": compressed(target),
            "computed_affine_x": f"{x:064x}",
            "computed_affine_y": f"{target[1]:064x}",
            "signature_r": f"{r:064x}",
            "signature_s": f"{1:064x}",
            "r_plus_order": f"{r + N:064x}",
            "r_plus_order_below_p": r + N < P,
            "r_plus_order_overflows_u256": r + N >= 2**256,
        })
    return {
        "curve": "NIST P-256 / secp256r1",
        "provenance": {
            "generator": "generate.py",
            "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "construction": "Q = r^-1 R; digest = 0; s = 1; therefore u1*G + u2*Q = R.",
            "oracle": "Independent Python integer affine arithmetic; no plugin or RustCrypto imports.",
            "checks": [
                "p and n bounds",
                "generator and constructed points on curve",
                "n*G and n*R are infinity",
                "r*Q equals the selected target R",
                "ordinary affine ECDSA verification has the expected result",
            ],
        },
        "parameters": {
            "p": f"{P:064x}",
            "n": f"{N:064x}",
            "a": f"{P - 3:064x}",
            "b": f"{B:064x}",
            "p_minus_n": f"{P - N:064x}",
            "u256_modulus_minus_n": f"{2**256 - N:064x}",
        },
        "vectors": vectors,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write JSON here; otherwise print it.")
    args = parser.parse_args()
    output = json.dumps(generate(), indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
