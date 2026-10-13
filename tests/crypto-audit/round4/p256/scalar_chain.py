#!/usr/bin/env python3
"""Symbolically evaluate the actual Rust scalar inversion expression chain."""
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "plugins/p256/runtime/vendor/p256/src/arithmetic/scalar.rs"
ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551


def main():
    source = SOURCE.read_text()
    body = source.split("const fn invert_unchecked(&self) -> Self {", 1)[1].split("\n    }", 1)[0]
    body = re.sub(r"//[^\n]*", "", body)
    values = {"self": 1}
    squares = multiplies = 0
    assignments = []
    for statement in body.split(";"):
        statement = statement.strip()
        if statement == "acc":
            continue
        match = re.fullmatch(r"(?:let (?:mut )?)?(\w+) = (.+)", statement)
        assert match, statement
        name, expression = match.groups()
        expression = expression.removeprefix("*")
        start = re.match(r"\w+", expression)
        value = values[start[0]]
        suffix = expression[start.end():]
        while suffix:
            operation = re.match(r"\.(square|sqn|multiply)\(([^)]*)\)", suffix)
            assert operation, suffix
            method, argument = operation.groups()
            if method == "square":
                assert argument == ""
                value *= 2
                squares += 1
            elif method == "sqn":
                assert argument.isdecimal()
                count = int(argument)
                value <<= count
                squares += count
            else:
                assert re.fullmatch(r"&\w+", argument)
                value += values[argument[1:]]
                multiplies += 1
            suffix = suffix[operation.end():]
        values[name] = value
        assignments.append({"name": name, "expression": expression, "exponent": hex(value)})
    assert values["acc"] == ORDER - 2
    assert squares == 254 and multiplies == 38
    report = {"schema": 1, "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              "checker_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "exponent": hex(values["acc"]), "squares": squares, "multiplies": multiplies,
              "schedule_matches_order_minus_two": True, "assignments": assignments}
    (HERE / "scalar-chain.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "assignments"}, indent=2))


if __name__ == "__main__":
    main()
