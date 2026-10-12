#!/usr/bin/env python3
"""Generate the P256 comb and independently check runtime constants with OpenSSL.

Run with an OpenSSL executable on PATH, or pass --openssl /path/to/openssl.
This script does not modify runtime sources; JSON evidence is printed to stdout
unless --output is provided. Point arithmetic below uses Python integers rather
than RustCrypto. OpenSSL independently derives every encoded table point from
its exact private scalar, so validation checks its value and curve membership.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

P = 2**256 - 2**224 + 2**192 + 2**96 - 1
G = (
    int("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296", 16),
    int("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5", 16),
)


def add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    x, y = a
    u, v = b
    if x == u:
        if (y + v) % P == 0:
            return None
        slope = (3 * x * x - 3) * pow(2 * y, -1, P) % P
    else:
        slope = (v - y) * pow(u - x, -1, P) % P
    z = (slope * slope - x - u) % P
    return z, (slope * (x - z) - y) % P


def generate():
    basis = [G]
    for _ in range(3):
        point = basis[-1]
        for _ in range(64):
            point = add(point, point)
        basis.append(point)
    points = []
    for index in range(1, 16):
        point = None
        for column in range(4):
            if index >> column & 1:
                point = add(point, basis[column])
        points.append(bytes([4]) + point[0].to_bytes(32, "big") + point[1].to_bytes(32, "big"))
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--runtime", type=Path,
                        default=Path(__file__).resolve().parents[2] / "runtime/src/lib.rs")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    points = generate()
    source = args.runtime.read_bytes()
    table = source.decode().split("const GENERATOR_COMB: [[u8; 65]; 15] = [", 1)[1].split("];", 1)[0]
    actual = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})\b", table))
    assert actual == b"".join(points), "Runtime table differs from independent Python result"
    spki_prefix = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
    coefficients = []
    for index, point in enumerate(points, 1):
        coefficient = sum(((index >> column) & 1) << (64 * column) for column in range(4))
        scalar = coefficient.to_bytes(32, "big")
        coefficients.append(scalar.hex())
        private_key = bytes.fromhex("30310201010420") + scalar + bytes.fromhex("a00a06082a8648ce3d030107")
        derived = subprocess.run(
            [args.openssl, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
            input=private_key, capture_output=True, check=True,
        ).stdout
        assert derived == spki_prefix + point, f"OpenSSL derived a different table point {index}"
    version = subprocess.check_output([args.openssl, "version"], text=True).strip()
    report = {
        "basis": "G,2^64G,2^128G,2^192G",
        "runtime_sha256": hashlib.sha256(source).hexdigest(),
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "openssl": version,
        "validated": "All 15 constants match independent Python arithmetic and OpenSSL exact-scalar public-key derivation",
        "coefficients": coefficients,
        "points": [point.hex() for point in points],
    }
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded)
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
