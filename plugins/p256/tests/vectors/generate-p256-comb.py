#!/usr/bin/env python3
"""Independently verify the selected P256 secret comb with Python and OpenSSL.

Run with an OpenSSL executable on PATH, or pass --openssl /path/to/openssl.
This script does not modify runtime sources; JSON evidence is printed to stdout
unless --output is provided. Point arithmetic below uses Python integers rather
than RustCrypto. OpenSSL independently derives every encoded table point from
its exact private scalar, so validation checks its value and curve membership.
"""

import argparse
import ast
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


def read_table(source):
    text = re.sub(r"//[^\n]*", "", source.decode())
    dimensions = []
    for name in ("TABLES", "ROWS"):
        matches = re.findall(rf"pub const {name}: usize = ([0-9]+);", text)
        assert len(matches) == 1, f"Expected one {name} declaration"
        dimensions.append(int(matches[0]))
    tables, rows = dimensions
    assert tables > 0 and rows > 0 and tables * rows == 64, "Invalid comb dimensions"
    declaration = re.search(
        r"pub const POINTS: \[\[\[u64; 8\]; 15\]; TABLES\] = (\[.*\]);\s*$",
        text, re.DOTALL,
    )
    assert declaration, "Expected the selected runtime Montgomery table"
    words = ast.literal_eval(declaration[1])
    assert isinstance(words, list) and len(words) == tables
    for table in words:
        assert isinstance(table, list) and len(table) == 15
        for point in table:
            assert isinstance(point, list) and len(point) == 8
            assert all(type(word) is int and 0 <= word < 2**64 for word in point)
            for offset in (0, 4):
                coordinate = sum(point[offset + limb] << (64 * limb) for limb in range(4))
                assert coordinate < P, "Noncanonical Montgomery coordinate"
    return tables, rows, words


def generate(tables, rows):
    powers = [G]
    for _ in range(255):
        powers.append(add(powers[-1], powers[-1]))
    points, coefficients, words = [], [], []
    for chunk in range(tables):
        table_points, table_coefficients, table_words = [], [], []
        for digit in range(1, 16):
            point, coefficient = None, 0
            for column in range(4):
                if digit >> column & 1:
                    bit = rows * chunk + 64 * column
                    point = add(point, powers[bit])
                    coefficient += 1 << bit
            assert point is not None, "Unexpected identity table entry"
            encoded = b"\x04" + point[0].to_bytes(32, "big") + point[1].to_bytes(32, "big")
            montgomery = []
            for coordinate in point:
                value = coordinate * 2**256 % P
                montgomery.extend((value >> (64 * limb)) & (2**64 - 1) for limb in range(4))
            table_points.append(encoded)
            table_coefficients.append(coefficient)
            table_words.append(montgomery)
        points.append(table_points)
        coefficients.append(table_coefficients)
        words.append(table_words)
    return points, coefficients, words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--runtime", type=Path,
                        default=Path(__file__).resolve().parents[2] / "runtime/src/secret_table.rs")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.runtime.read_bytes()
    tables, rows, actual = read_table(source)
    points, coefficients, expected = generate(tables, rows)
    assert actual == expected, "Runtime table differs from independent Python result"
    spki_prefix = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
    for chunk in range(tables):
        for digit, (point, coefficient) in enumerate(zip(points[chunk], coefficients[chunk]), 1):
            scalar = coefficient.to_bytes(32, "big")
            private_key = bytes.fromhex("30310201010420") + scalar + bytes.fromhex("a00a06082a8648ce3d030107")
            derived = subprocess.run(
                [args.openssl, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
                input=private_key, capture_output=True, check=True,
            ).stdout
            assert derived == spki_prefix + point, f"OpenSSL mismatch: table {chunk}, digit {digit}"
    version = subprocess.check_output([args.openssl, "version"], text=True).strip()
    report = {
        "tables": tables,
        "rows": rows,
        "points_per_table": 15,
        "basis": "Table t uses 2^(ROWS*t + 64*c) G for columns c = 0,1,2,3",
        "encoding": "Canonical xR,yR mod p; R=2^256; four little-endian u64 words per coordinate",
        "runtime_table_sha256": hashlib.sha256(source).hexdigest(),
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "openssl": version,
        "validated": f"All {tables * 15} constants match independent Python arithmetic and OpenSSL exact-scalar public-key derivation",
        "coefficients": [[f"{coefficient:064x}" for coefficient in table] for table in coefficients],
        "points": [[point.hex() for point in table] for table in points],
        "montgomery_words": actual,
    }
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded)
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
