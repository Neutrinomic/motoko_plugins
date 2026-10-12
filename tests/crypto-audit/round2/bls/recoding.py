#!/usr/bin/env python3
"""Independent integer audit of the frozen BLS round-two MSM recodings.

No crypto dependency is used: integer reconstruction proves the recoded sum
acts as the original scalar in every additive group. This supplements, rather
than replaces, the separate compiled-runtime differential tests.
"""

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
R = int("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001", 16)
FINAL_HASH = "c7dff4e213b7d2faaf1934c6f67060339a28d53732f1e91a4d8a88cc513a78f0"
BASELINE_HASH = "db6eaf197f4f71a67385e2aaa627b81c5a954ea64bff06854b51b27221eb1059"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def source_wnaf(n):
    """Model the reviewed byte-reading implementation, checking each access."""
    scalar = n.to_bytes(32, "little") + b"\0"
    digits = [0] * 256
    bit, carry, max_byte = 0, 0, 0
    while bit < 256:
        byte = bit // 8
        assert 0 <= byte < byte + 1 < 33
        max_byte = max(max_byte, byte + 1)
        word = scalar[byte] | scalar[byte + 1] << 8
        value = ((word >> (bit % 8)) & 15) + carry
        if value & 1 == 0:
            bit += 1
        else:
            carry = int(value >= 8)
            digits[bit] = value - carry * 16
            bit += 4
    return digits, max_byte


def independent_wnaf(n):
    """Ordinary integer residual method; no byte reads or retained carry."""
    digits = []
    while n:
        digit = 0
        if n % 2:
            digit = n % 16
            if digit > 8:
                digit -= 16
            n -= digit
        digits.append(digit)
        n //= 2
    assert len(digits) <= 256
    return digits + [0] * (256 - len(digits))


def source_booth(n, width):
    """Model the reviewed overlapping byte windows, retaining bound checks."""
    scalar = n.to_bytes(32, "little") + b"\0"
    half = 1 << (width - 1)
    digits = []
    max_byte = 0
    for k in range((256 + width - 1) // width):
        bit = k * width
        byte = bit // 8
        assert 0 <= byte < byte + 1 < 33
        max_byte = max(max_byte, byte + 1)
        word = scalar[byte] | scalar[byte + 1] << 8
        raw = (word >> (bit % 8)) & ((half << 1) - 1)
        previous = 0 if bit == 0 else (scalar[(bit - 1) // 8] >> ((bit - 1) % 8)) & 1
        digit = (raw & (half - 1)) + previous - (raw & half)
        assert -half <= digit <= half
        assert abs(digit) <= 32  # The allocation has indices 0..32 inclusive.
        digits.append(digit)
    return digits, max_byte


def reconstruct(digits, radix):
    # Horner evaluation mirrors the mathematical group operation, using exact
    # unbounded integers and no reduction modulo the curve order.
    result = 0
    for digit in reversed(digits):
        result = result * radix + digit
    return result


def cases():
    exhaustive = list(range(1 << 16))
    edge = set()
    for k in range(256):
        for delta in range(-16, 17):
            for n in ((1 << k) + delta, R - (1 << k) + delta):
                if 0 <= n < R:
                    edge.add(n)
    for delta in range(2049):
        edge.add(R - 1 - delta)
    for width in (3, 4, 5, 6):
        for base_digit in (0, 1, (1 << (width - 1)) - 1, 1 << (width - 1), (1 << width) - 1):
            n = sum(base_digit << (k * width) for k in range((255 + width - 1) // width))
            edge.add(n % R)
    edge.difference_update(exhaustive)
    random = set()
    counter = 0
    while len(random) < 8192:
        candidate = int.from_bytes(hashlib.sha256(b"bls-round2-independent-recoding\0" + counter.to_bytes(8, "big")).digest(), "big")
        counter += 1
        # Full-width canonical rejection sampling; no modulo-biased conversion.
        if 0 <= candidate < R and candidate not in edge and candidate >= 1 << 16:
            random.add(candidate)
    return {"exhaustive_u16": exhaustive, "boundary_and_pattern": sorted(edge), "deterministic_full_width_random": sorted(random)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--final", type=Path, default=ROOT / "_build/crypto-optimization-round2/bls-final")
    parser.add_argument("--baseline", type=Path, default=ROOT / "_build/crypto-optimization-round2/baseline")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("recoding-report.json"))
    args = parser.parse_args()
    source = (args.final / "plugins/bls12-381/runtime/src/lib.rs").read_bytes()
    baseline = (args.baseline / "plugins/bls12-381/runtime/src/lib.rs").read_bytes()
    assert sha256(source) == FINAL_HASH, "Changed candidate: review the byte-level models again"
    assert sha256(baseline) == BASELINE_HASH, "Unexpected baseline"
    code = source.decode()
    old_code = baseline.decode()
    # Exact source comparison: neither single-scalar operation dispatches to a
    # variable-time MSM implementation. Point decoding changes are public-only.
    multiplication = code[code.index("        5 =>"):code.index("        7 =>")]
    old_multiplication = old_code[old_code.index("        5 =>"):old_code.index("        7 =>")]
    assert multiplication == old_multiplication
    assert "G1Affine::from(g1(a)? * scalar(b)?).to_compressed()" in multiplication
    assert "G2Affine::from(g2(a)? * scalar(b)?).to_compressed()" in multiplication
    macro = code[code.index("macro_rules! define_msm"):code.index("define_msm!(msm_g1")]
    assert macro.index("scalar(s)?;") < macro.index("inputs.push((point, little))")
    assert "if count < 2" in macro and "if count < 4" in macro
    api = (args.final / "packages/fast/src/BLS12381.mo").read_text()
    assert "MSM is variable-time and is intended only for public scalars" in api

    groups = cases()
    transcript = hashlib.sha256()
    scalar_transcript = hashlib.sha256()
    wnaf_top_carries = 0
    wnaf_max_byte, max_table_index = 0, 0
    booth_stats = {width: {"max_byte_index": 0, "min_digit": 0, "max_digit": 0, "top_window_nonzero": 0} for width in (3, 4, 5, 6)}
    count = 0
    for group in groups.values():
        for n in group:
            assert 0 <= n < R
            encoded = n.to_bytes(32, "big")
            scalar_transcript.update(encoded)
            count += 1
            digits, max_byte = source_wnaf(n)
            assert digits == independent_wnaf(n), hex(n)
            assert reconstruct(digits, 2) == n, hex(n)
            wnaf_max_byte = max(wnaf_max_byte, max_byte)
            wnaf_top_carries += int(digits[255] != 0)
            for bit, digit in enumerate(digits):
                if digit:
                    assert abs(digit) in (1, 3, 5, 7)
                    assert not any(digits[bit + 1:bit + 4])
                    index = abs(digit) // 2
                    assert index < 4
                    max_table_index = max(max_table_index, index)
            transcript.update(b"wnaf" + encoded + bytes(digit + 128 for digit in digits))
            for width in (3, 4, 5, 6):
                digits, max_byte = source_booth(n, width)
                assert reconstruct(digits, 1 << width) == n, (width, hex(n))
                # Independent signed-window identity: each ordinary radix
                # digit loses B when its high bit is set and receives the
                # previous window's high bit. Those terms telescope exactly.
                ordinary = [(n >> (k * width)) % (1 << width) for k in range(len(digits))]
                expected = [ordinary[k] - ((1 << width) if ordinary[k] >= 1 << (width - 1) else 0)
                            + (int(ordinary[k - 1] >= 1 << (width - 1)) if k else 0)
                            for k in range(len(digits))]
                assert digits == expected
                assert ordinary[-1] < 1 << (width - 1), "Unrepresented carry above highest window"
                stats = booth_stats[width]
                stats["max_byte_index"] = max(stats["max_byte_index"], max_byte)
                stats["min_digit"] = min(stats["min_digit"], min(digits))
                stats["max_digit"] = max(stats["max_digit"], max(digits))
                stats["top_window_nonzero"] += int(digits[-1] != 0)
                transcript.update(b"booth" + bytes([width]) + encoded + bytes(digit + 128 for digit in digits))
    assert wnaf_top_carries > 0 and max_table_index == 3 and wnaf_max_byte == 32
    for width, stats in booth_stats.items():
        assert stats["max_byte_index"] == 32
        assert stats["min_digit"] == -(1 << (width - 1))
        assert stats["max_digit"] == 1 << (width - 1)
    report = {
        "status": "pass",
        "scope": "Independent integer-model audit and static source review; compiled-runtime differential tests are reported separately.",
        "script_sha256": sha256(Path(__file__).read_bytes()),
        "candidate_source_sha256": sha256(source),
        "baseline_source_sha256": sha256(baseline),
        "scalar_modulus_hex": f"{R:064x}",
        "case_counts": {name: len(group) for name, group in groups.items()},
        "unique_scalar_cases": count,
        "reconstructions": count * 5,
        "scalar_corpus_sha256": scalar_transcript.hexdigest(),
        "recoding_transcript_sha256": transcript.hexdigest(),
        "wnaf": {"width": 4, "max_byte_index": wnaf_max_byte, "max_table_index": max_table_index, "bit255_carry_cases": wnaf_top_carries, "residual_oracle_comparisons": count},
        "booth": booth_stats,
        "review": {
            "canonical_scalars_validated_before_recoding": True,
            "single_scalar_dispatch_unchanged": True,
            "msm_public_variable_time_contract_documented": True,
            "scalar_dependent_table_indexes_confined_to_msm": True,
            "bounds": "33-byte padded scalar; wNAF digits[0..255] and odd-multiple table[0..3]; Booth bucket magnitudes <=32, fitting [0..32].",
            "booth_proof": "d_k = u_k - B*h_k + h_(k-1), where h_k is u_k's high bit, h_-1=0. Summing d_k*B^k telescopes to n because the padded top h_k is zero.",
            "timing_limit": "This is a source-level contract check, not a formal or empirical constant-time proof of the dependency or compiler output. Public point decoding shortcuts do not branch on secret scalar data.",
        },
        "findings": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "unique_scalar_cases": count, "reconstructions": count * 5, "recoding_transcript_sha256": transcript.hexdigest()}))


if __name__ == "__main__":
    main()
