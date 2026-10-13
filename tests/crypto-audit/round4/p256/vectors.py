#!/usr/bin/env python3
"""Extend preserved independent oracles for the round-four P256 changes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ORACLE = ROOT / "tests/crypto-audit/prepared/p256/generate.py"
VERIFY = ROOT / "tests/crypto-audit/prepared/p256/vectors.json"
SIGN = ROOT / "benchmarks/crypto/round3/p256/audit/independent-vectors.json"
spec = importlib.util.spec_from_file_location("independent_curve_oracle", ORACLE)
curve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(curve)


def main():
    table_path = ROOT / "plugins/p256/runtime/src/secret_table.rs"
    table_source = table_path.read_text()
    tables = int(re.search(r"TABLES: usize = (\d+)", table_source)[1])
    rows = int(re.search(r"ROWS: usize = (\d+)", table_source)[1])
    assert tables in (2, 4) and rows * tables == 64
    positions = [bit + rows * chunk + 64 * column
                 for bit in range(rows) for chunk in range(tables) for column in range(4)]
    assert sorted(positions) == list(range(256))
    actual_words = [int(word, 16) for word in re.findall(r"0x([0-9a-f]{16})", table_source)]
    expected_words = []
    for chunk in range(tables):
        for digit in range(1, 16):
            coefficient = sum(1 << (rows * chunk + 64 * column)
                              for column in range(4) if digit >> column & 1)
            assert 0 < coefficient < curve.N
            point = curve.mul(coefficient)
            for coordinate in point:
                montgomery = coordinate * (1 << 256) % curve.P
                expected_words.extend((montgomery >> (64 * limb)) & ((1 << 64) - 1) for limb in range(4))
    assert actual_words == expected_words
    original = json.loads(VERIFY.read_text())
    cases = [{**case, "public": original["keys"][case["key"]]["compressed"]}
             for case in original["verify"]]
    for label, x, r, expected in [
        ("valid-x-n-plus-three", curve.N + 3, 3, True),
        ("valid-x-p-minus-three", curve.P - 3, curve.P - curve.N - 3, True),
        ("reject-field-wrap-to-zero", 0, curve.P - curve.N, False),
        ("reject-u256-carry-wrap-to-zero", 0, (1 << 256) - curve.N, False),
    ]:
        point_r = curve.point_at(x)
        assert point_r is not None and 0 < r < curve.N
        q = curve.mul(pow(r, -1, curve.N), point_r)
        assert curve.mul(r, q) == point_r
        assert (point_r[0] % curve.N == r) == expected
        cases.append({"label": label, "public": curve.sec1(q, True).hex(),
                      "digest": "00" * 32,
                      "signature": (r.to_bytes(32, "big") + (1).to_bytes(32, "big")).hex(),
                      "expected": expected})
    values = {0, 1, 2, curve.N - 1}
    for bit in range(256):
        values.update({(1 << bit) % curve.N, ((1 << bit) - 1) % curve.N,
                       ((1 << bit) + 1) % curve.N, (-(1 << bit)) % curve.N})
    for i in range(64):
        values.add(int.from_bytes(hashlib.sha256(f"round4-p256-inverse-{i}".encode()).digest(), "big") % curve.N)
    inverse = [{"input": f"{x:064x}", "square": f"{x * x % curve.N:064x}",
                "inverse": f"{pow(x, -1, curve.N):064x}" if x else None}
               for x in sorted(values)]
    derive = []
    for bit in range(256):
        for scalar in [1 << bit, curve.N - (1 << bit)]:
            point = curve.mul(scalar)
            derive.append({"label": f"power-{bit}-{'positive' if scalar == 1 << bit else 'negative'}",
                           "secret": f"{scalar:064x}", "public": curve.sec1(point, True).hex(),
                           "uncompressed": curve.sec1(point, False).hex()})
    result = {"schema": 1, "verify": cases, "inverse": inverse, "derive": derive,
              "sign": json.loads(SIGN.read_text())["vectors"],
              "secret_table": {"tables": tables, "rows": rows, "all_points_independently_checked": tables * 15,
                               "all_256_scalar_bits_covered_once": True,
                               "sha256": hashlib.sha256(table_path.read_bytes()).hexdigest()},
              "oracle_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in [ORACLE, VERIFY, SIGN]},
              "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (HERE / "vectors.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({name: len(result[name]) for name in ["verify", "inverse", "derive", "sign"]}))


if __name__ == "__main__":
    main()
