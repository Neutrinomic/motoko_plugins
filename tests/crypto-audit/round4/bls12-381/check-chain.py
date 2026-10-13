#!/usr/bin/env python3
"""Evaluate the exponent schedule symbolically, without implementing field arithmetic."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.vendor / "src/hash_to_curve/chain.rs"
    fp = args.vendor / "src/fp.rs"
    modulus_body = re.search(r"const MODULUS: \[u64; 6\] = \[(.*?)\];", fp.read_text(), re.S)[1]
    limbs = [int(s.replace("_", ""), 16) for s in re.findall(r"0x[0-9a-f_]+", modulus_body)]
    assert len(limbs) == 6
    p = sum(limb << (64 * i) for i, limb in enumerate(limbs))
    assert p % 4 == 3
    code = re.sub(r"//[^\n]*", "", source.read_text())
    header = re.search(r"fn chain_pm3div4[^\{]+\{", code)
    assert header
    start = header.end()
    end = code.index("\n}", start)
    statements = [s.strip() for s in code[start:end].split(";") if s.strip()]
    exponents = {"var0": 1}
    squarings, multiplies = 0, 0
    for statement in statements:
        statement = re.sub(r"\s+", " ", statement)
        if statement == "let var0 = *var0":
            continue
        match = re.fullmatch(r"square!\((var\d+), (\d+)\)", statement)
        if match:
            name, count = match[1], int(match[2])
            exponents[name] <<= count
            squarings += count
            continue
        match = re.fullmatch(r"(var\d+)\.mul_assign\(&?(var\d+)\)", statement)
        if match:
            exponents[match[1]] += exponents[match[2]]
            multiplies += 1
            continue
        match = re.fullmatch(r"(?:(?:let (?:mut )?)?(var\d+) = )?(var\d+)\.square\(\)", statement)
        if match:
            value = exponents[match[2]] * 2
            squarings += 1
            if match[1]:
                exponents[match[1]] = value
            else:
                result = value
            continue
        match = re.fullmatch(r"(?:let (?:mut )?)?(var\d+) = (var\d+) \* (var\d+)", statement)
        if match:
            exponents[match[1]] = exponents[match[2]] + exponents[match[3]]
            multiplies += 1
            continue
        raise AssertionError("Unrecognized chain statement: " + statement)
    assert result == (p - 3) // 4
    assert result + 1 == (p + 1) // 4
    assert 4 * result + 1 == p - 2
    assert 2 * result + 1 == (p - 1) // 2
    report = {
        "status": "pass",
        "source_sha256": {
            str(path.relative_to(args.vendor)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (source, fp)
        },
        "modulus": str(p), "chain_exponent": str(result),
        "chain_squarings": squarings, "chain_multiplies": multiplies,
        "identities": ["e=(p-3)/4", "sqrt exponent=e+1=(p+1)/4",
                       "inverse exponent=4e+1=p-2", "Fp2 second exponent=2e+1=(p-1)/2"],
        "scope": "Exact integer exponent schedule, with no reduction modulo group order. Therefore includes zero and works identically for Fp/Fp2; field implementation, CtOption predicates and root selection require separate executed tests."
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: exact e=(p-3)/4; {squarings} squares, {multiplies} multiplies; all three derived exponents match.")


if __name__ == "__main__":
    main()
