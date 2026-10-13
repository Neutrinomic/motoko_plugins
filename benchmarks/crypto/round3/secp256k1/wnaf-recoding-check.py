#!/usr/bin/env python3
"""Independent integer-model check of the public-scalar wNAF recoder.

Run from any directory with Python 3. This does not execute Rust/Wasm and does
not replace curve differential tests or signature vectors. Pinning the exact
Rust function prevents a changed implementation silently inheriting this result.
"""

import hashlib
import json
from pathlib import Path
import random


SOURCE = "plugins/secp256k1/runtime/vendor/k256/src/arithmetic/mul.rs"
FRAGMENT_SHA256 = "04a197820f8677c8a60d999f06b85fd1e3fe531fbb89d42a901140223f03cea2"
SEED = 0x57
U64_MASK = (1 << 64) - 1


def recode(k):
    """Mirror the Rust two-u64 shifts, carry and fixed 129-slot array."""
    lo = k & U64_MASK
    hi = k >> 64
    digits = [0] * 129
    position = 0
    carry = 0
    while position < 128 or carry != 0:
        if position < 64:
            overlap = ((hi << (64 - position)) & U64_MASK) if position > 59 else 0
            bits = (lo >> position) | overlap
        elif position < 128:
            bits = hi >> (position - 64)
        else:
            bits = 0
        window = (bits & 31) + carry
        if window & 1 == 0:
            position += 1
            continue
        carry = int(window >= 16)
        digits[position] = window - (carry << 5)
        position += 5
    return digits


def main():
    script = Path(__file__).resolve()
    root = script.parents[4]
    source = root / SOURCE
    text = source.read_text()
    start = text.index("fn wnaf_128_vartime(")
    end = text.index("\n}\n", start) + 2
    fragment_hash = hashlib.sha256((text[start:end] + "\n").encode()).hexdigest()
    if fragment_hash != FRAGMENT_SHA256:
        raise RuntimeError("Rust recoder changed; review and update the independent model first")

    values = set(range(65536))
    for bit in range(129):
        for offset in range(-65, 66):
            value = (1 << bit) + offset
            if 0 <= value < 1 << 128:
                values.add(value)
    rng = random.Random(SEED)
    values.update(rng.getrandbits(128) for _ in range(100000))

    max_nonzero = 0
    highest_nonzero_position = 0
    for value in sorted(values):
        digits = recode(value)
        if sum(digit << bit for bit, digit in enumerate(digits)) != value:
            raise AssertionError(f"incorrect reconstruction for {value:#x}")
        if not all(digit == 0 or (digit & 1 and -15 <= digit <= 15) for digit in digits):
            raise AssertionError(f"invalid digit for {value:#x}")
        nonzero = [bit for bit, digit in enumerate(digits) if digit]
        if not all(right - left >= 5 for left, right in zip(nonzero, nonzero[1:])):
            raise AssertionError(f"invalid non-adjacent spacing for {value:#x}")
        max_nonzero = max(max_nonzero, len(nonzero))
        highest_nonzero_position = max(highest_nonzero_position, max(nonzero, default=0))

    if len(values) != 180208:
        raise AssertionError(f"case generation changed: {len(values)}")
    result = {
        "status": "pass",
        "scope": "Independent Python integer model; not execution of Rust or Wasm",
        "source": SOURCE,
        "sourceFragment": "fn wnaf_128_vartime through its closing brace, with trailing LF",
        "sourceFragmentSha256": fragment_hash,
        "scriptSha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "cases": len(values),
        "method": {
            "exhaustiveSmallIntegers": {"minimum": 0, "maximumInclusive": 65535},
            "powerBoundaries": {
                "powersInclusive": [0, 128],
                "offsetsInclusive": [-65, 65],
                "filter": "0 <= value < 2^128",
            },
            "random": {"generator": "Python random.Random.getrandbits", "seed": SEED,
                       "bits": 128, "draws": 100000},
            "combination": "deduplicated union",
        },
        "checks": [
            "exact integer reconstruction",
            "nonzero digits are odd and between -15 and 15 inclusive",
            "nonzero positions are separated by at least 5 bits",
            "every emitted digit fits the 129-slot array",
        ],
        "maxNonzeroDigitsObserved": max_nonzero,
        "highestNonzeroPositionObserved": highest_nonzero_position,
    }
    output = script.with_name("wnaf-recoding-result.json")
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS: {len(values):,} cases; evidence: {output.relative_to(root)}")


if __name__ == "__main__":
    main()
