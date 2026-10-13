#!/usr/bin/env python3
"""Independent integer/polynomial checks for the round-seven BLS formulas.

This checks algebraic identities, not the Rust implementation or its lowering.
The accompanying review pins the exact source reviewed and tested.
"""
import json
from collections import defaultdict
from itertools import product


class Polynomial:
    def __init__(self, terms):
        self.terms = {term: coefficient for term, coefficient in terms.items() if coefficient}

    @classmethod
    def variable(cls, name):
        return cls({(name,): 1})

    def __add__(self, other):
        terms = defaultdict(int, self.terms)
        for term, coefficient in other.terms.items():
            terms[term] += coefficient
        return Polynomial(terms)

    def __neg__(self):
        return Polynomial({term: -coefficient for term, coefficient in self.terms.items()})

    def __sub__(self, other):
        return self + -other

    def __mul__(self, other):
        terms = defaultdict(int)
        for left, a in self.terms.items():
            for right, b in other.terms.items():
                terms[tuple(sorted(left + right))] += a * b
        return Polynomial(terms)

    def __eq__(self, other):
        return self.terms == other.terms


a0, a1, a2, b0, b1, b2, xi = map(Polynomial.variable, ("a0", "a1", "a2", "b0", "b1", "b2", "xi"))
a, b, c = a0 * b0, a1 * b1, a2 * b2

# Arbitrary commuting coefficients: no subgroup or nonzero preconditions.
assert a - b == a0 * b0 - a1 * b1
assert (a0 + a1) * (b0 + b1) - a - b == a0 * b1 + a1 * b0
assert a + xi * ((a1 + a2) * (b1 + b2) - b - c) == a0 * b0 + xi * (a1 * b2 + a2 * b1)
assert (a0 + a1) * (b0 + b1) - a - b + xi * c == a0 * b1 + a1 * b0 + xi * a2 * b2
assert (a0 + a2) * (b0 + b2) - a + b - c == a0 * b2 + a1 * b1 + a2 * b0

# Fixed multiplier is an integer identity; reduction modulo the subgroup order
# would be insufficient for the on-curve non-subgroup inputs checked in Rust.
magnitude = 1
for gap in [1, 2, 3, 9, 32]:
    magnitude = (magnitude << gap) + 1
magnitude <<= 16
assert magnitude == 0xD201000000010000

# Exhaustive small-word model complements the all-width proof in README.md.
# Both borrow input states cover all inputs because only its high bit is read.
for a in range(256):
    for b in range(256):
        for borrow in [0, 255]:
            first = (a - b) % 256
            first_borrow = a < b
            second_borrow = first < (borrow >> 7)
            result = (first - (borrow >> 7)) % 256
            mask = 255 if first_borrow or second_borrow else 0
            reference = (a - b - (borrow >> 7)) % (256 * 256)
            assert (result, mask) == (reference % 256, reference // 256)

# Exhaust every input to the two-bit-halves model. The proof uses q as a
# variable, so the same intermediate bounds hold for production q=2^32.
q = 4
word = q * q
for a, b, c, carry in product(range(word), repeat=4):
    low = (b % q) * (c % q) + a % q + carry % q
    middle = (b // q) * (c % q) + low // q + a // q
    cross = (b % q) * (c // q) + middle % q + carry // q
    high = (b // q) * (c // q) + middle // q + cross // q
    assert all(0 <= value < word for value in [low, middle, cross, high])
    actual = high * word + (cross % q) * q + low % q
    assert actual == a + b * c + carry

print(json.dumps({
    "status": "PASS",
    "fp2_coefficients": 2,
    "fp6_coefficients": 3,
    "signed_bls_x": -magnitude,
    "borrow_small_word_cases": 256 * 256 * 2,
    "multiply_add_small_word_cases": word**4,
}, indent=2))
