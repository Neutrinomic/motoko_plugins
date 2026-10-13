#!/usr/bin/env python3
"""Prove the addition-chain exponent by interpreting the checked-in Rust source.

No Rust compilation is performed. Modular arithmetic remains the vendored
implementation's responsibility; this checks the exact exponent schedule and
the fixed-count squaring helper independently with Python integers.
"""

import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[5]
SOURCE = ROOT / "plugins/p256/runtime/vendor/p256/src/arithmetic/scalar.rs"
ORDER = int("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)


def function_body(source, declaration):
    start = source.index("{", source.index(declaration)) + 1
    depth = 1
    position = start
    while depth:
        if source[position] == "{":
            depth += 1
        elif source[position] == "}":
            depth -= 1
        position += 1
    return source[start:position - 1]


def without_comments(source):
    return "\n".join(line.split("//", 1)[0] for line in source.splitlines())


source = SOURCE.read_text()
body = function_body(source, "const fn invert_unchecked(")
helper = function_body(source, "const fn sqn(")
expected_helper = """
    let mut result = *self;
    let mut i = 0;
    while i < count {
        result = result.square();
        i += 1;
    }
    result
"""
assert re.sub(r"\s+", "", without_comments(helper)) == re.sub(r"\s+", "", expected_helper)

exponents = {}
squares = 0
multiplies = 0


def exponent(expression):
    global squares, multiplies
    if expression == "*self":
        return 1
    first = re.match(r"([a-z][a-z0-9_]*)", expression)
    assert first, expression
    result = exponents[first[1]]
    tail = expression[first.end():]
    while tail:
        operation = re.match(r"\.(square|sqn|multiply)\(([^()]*)\)", tail)
        assert operation, tail
        method, argument = operation.groups()
        if method == "multiply":
            assert re.fullmatch(r"&[a-z][a-z0-9_]*", argument), argument
            result += exponents[argument[1:]]
            multiplies += 1
        else:
            if method == "square":
                assert not argument
                count = 1
            else:
                assert re.fullmatch(r"[0-9]+", argument), argument
                count = int(argument)
            result <<= count
            squares += count
        tail = tail[operation.end():]
    return result


statements = without_comments(body).strip().split(";")
for statement in statements[:-1]:
    assignment = re.fullmatch(r"(?:let (?:mut )?)?([a-z][a-z0-9_]*) = (.+)", statement.strip())
    assert assignment, statement
    name, expression = assignment.groups()
    exponents[name] = exponent(expression)
    if re.fullmatch(r"x[0-9]+", name):
        assert exponents[name] == int(name[1:]), name

result = exponents[statements[-1].strip()]
assert result == ORDER - 2
assert (squares, multiplies) == (254, 38)

# Independent bigint inverse checks establish the algebra for representative
# inputs; they do not substitute for running native/Wasm Rust arithmetic tests.
samples = {0, 1, 2, ORDER - 2, ORDER - 1}
for bit in range(256):
    power = 1 << bit
    samples.update(((power - 1) % ORDER, power, (power + 1) % ORDER, (-power) % ORDER))
for index in range(256):
    sample = hashlib.sha256(b"p256 scalar inversion proof" + index.to_bytes(4, "big")).digest()
    samples.add(int.from_bytes(sample, "big") % ORDER)
for value in sorted(samples):
    inverse = pow(value, result, ORDER)
    if value == 0:
        assert inverse == 0
    else:
        assert inverse == pow(value, -1, ORDER)
        assert (value * inverse) % ORDER == 1

print(json.dumps({
    "source": str(SOURCE.relative_to(ROOT)),
    "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
    "inversion_body_sha256": hashlib.sha256(body.encode()).hexdigest(),
    "squaring_helper_sha256": hashlib.sha256(helper.encode()).hexdigest(),
    "expected_exponent_hex": hex(ORDER - 2),
    "evaluated_exponent_hex": hex(result),
    "symbolic_source_check": "pass",
    "old_binary_exponentiation": {"squares": 256, "multiplies": (ORDER - 2).bit_count()},
    "new_addition_chain": {"squares": squares, "multiplies": multiplies},
    "saved_scalar_multiply_calls_with_current_square": 256 + (ORDER - 2).bit_count() - squares - multiplies,
    "independent_python_integer_inverse_cases": len(samples),
    "rust_tests_run": False,
}, indent=2))
