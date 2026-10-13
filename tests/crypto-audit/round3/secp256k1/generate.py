#!/usr/bin/env python3
"""Generate independent full-width arithmetic/signature Motoko expectations.

The retained earlier audit supplies Python-bigint affine arithmetic, RFC6979,
Wycheproof, and published BIP340 vectors. This adds independently generated
BIP340 signatures and deterministic full-width arithmetic/ECDSA cases.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("previous_audit", ROOT / "tests/crypto-audit/curves/run_audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
curve = audit.CURVES["secp256k1"]
n, p = curve["n"], curve["p"]
octets, blob, multiply = audit.octets, audit.blob, lambda k: audit.multiply(curve, k)

def encoded(point):
    x, y = point
    return bytes([2 + y % 2]) + octets(x)

def tag(label, data):
    h = hashlib.sha256(label.encode()).digest()
    return hashlib.sha256(h + h + data).digest()

def schnorr(secret, message, auxiliary):
    px, py = multiply(secret)
    d = secret if py % 2 == 0 else n - secret
    t = bytes(a ^ b for a, b in zip(octets(d), tag("BIP0340/aux", auxiliary)))
    k0 = int.from_bytes(tag("BIP0340/nonce", t + octets(px) + message), "big") % n
    assert k0 != 0
    rx, ry = multiply(k0)
    k = k0 if ry % 2 == 0 else n - k0
    e = int.from_bytes(tag("BIP0340/challenge", octets(rx) + octets(px) + message), "big") % n
    return octets(rx) + octets((k + e * d) % n)

def generated(label, i):
    return hashlib.sha256(label.encode() + i.to_bytes(4, "big")).digest()

def multiply_point(point, scalar):
    result = None
    while scalar:
        if scalar & 1:
            result = audit.add(curve, result, point)
        point = audit.add(curve, point, point)
        scalar >>= 1
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    plugin, out = args.plugin.resolve(), args.out.resolve()
    run = out / "run"
    run.mkdir(parents=True, exist_ok=True)
    audit.WORK = out
    inherited = audit.fixtures("secp256k1", plugin)
    # Validate our independent BIP340 implementation before generating cases.
    import csv
    official = list(csv.DictReader((ROOT / "plugins/secp256k1/tests/vectors/bip340.csv").open()))
    for row in official:
        if row["secret key"]:
            assert schnorr(int(row["secret key"], 16), bytes.fromhex(row["message"]), bytes.fromhex(row["aux_rand"])).hex() == row["signature"].lower()
    counts = {"ecdsa_signatures": 0, "ecdsa_high_s": 0, "schnorr_signatures": 0, "mutations": 0, "arithmetic_cases": 0}
    lengths = [0, 1, 17, 31, 32, 33, 64, 255]
    for group in range(4):
        text = audit.flags("secp256k1", plugin)
        for i in range(group * 8, group * 8 + 8):
            secret = int.from_bytes(generated("independent-round3/secret", i), "big") % (n - 1) + 1
            scalar = int.from_bytes(generated("independent-round3/scalar", i), "big") % (n - 1) + 1
            digest = generated("independent-round3/digest", i)
            point = multiply(secret)
            key = encoded(point)
            signature = audit.sign(curve, secret, digest, True)
            high = signature[:32] + octets(n - int.from_bytes(signature[32:], "big"))
            wrong_digest = bytes([digest[0] ^ 1]) + digest[1:]
            # Expected invalidity also checked independently by ECDSA algebra.
            z, r, s = int.from_bytes(wrong_digest, "big"), int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big")
            wrong_point = multiply(((z + r * secret) * pow(s, -1, n)) % n)
            assert wrong_point is None or wrong_point[0] % n != r
            for expr, expected in [
                (f"derivePublicKey({blob(octets(secret))})", blob(key)),
                (f"baseMultiply({blob(octets(scalar))})", blob(encoded(multiply(scalar)))),
                (f"pointMultiply({blob(key)},{blob(octets(scalar))})", blob(encoded(multiply(secret * scalar % n)))),
                (f"pointAdd({blob(key)},{blob(encoded(multiply(scalar)))})", blob(encoded(multiply((secret + scalar) % n)))),
                (f"signPrehash({blob(octets(secret))},{blob(digest)})", blob(signature)),
                (f"verifyPrehash({blob(key)},{blob(digest)},{blob(signature)})", "true"),
                (f"verifyPrehash({blob(key)},{blob(digest)},{blob(high)})", "true"),
                (f"verifyPrehash({blob(key)},{blob(wrong_digest)},{blob(signature)})", "false"),
            ]:
                text += f"assert Curve.{expr} == #ok({expected});\n"
            message = (generated("independent-round3/message", i) * 8)[:lengths[i % len(lengths)]]
            aux = generated("independent-round3/aux", i)
            sig = schnorr(secret, message, aux)
            x = octets(point[0])
            text += f"assert Curve.schnorrSign({blob(octets(secret))},{blob(message)},{blob(aux)}) == #ok({blob(sig)});\n"
            text += f"assert Curve.schnorrVerify({blob(x)},{blob(message)},{blob(sig)}) == #ok(true);\n"
            # Changing s by 1 changes the reconstructed point by G, so it
            # cannot preserve the required same even-Y R.
            bad = sig[:32] + octets((int.from_bytes(sig[32:], "big") + 1) % n)
            text += f"assert Curve.schnorrVerify({blob(x)},{blob(message)},{blob(bad)}) == #ok(false);\n"
            counts["ecdsa_signatures"] += 1
            counts["ecdsa_high_s"] += 1
            counts["schnorr_signatures"] += 1
            counts["mutations"] += 2
            counts["arithmetic_cases"] += 4
        (run / f"audit-secp256k1-random-{group}.mo").write_text(text)
    text = audit.flags("secp256k1", plugin)
    # Force the ECDSA verification point to infinity: z=-1, r=s=1, Q=G.
    for s in [1, n - 1]:
        text += f"assert Curve.verifyPrehash({blob(encoded(curve['g']))},{blob(octets(n - 1))},{blob(octets(1) + octets(s))}) == #ok(false);\n"
    # Exercise the rare reduction x>=n branch with an independently built key.
    x = n
    while True:
        x += 1
        rhs = (pow(x, 3, p) + 7) % p
        y = pow(rhs, (p + 1) // 4, p)
        if y * y % p == rhs: break
    r = x % n
    key_point = multiply_point((x, y), pow(r, -1, n))
    assert multiply_point(key_point, r) == (x, y)
    for s in [1, n - 1]:
        text += f"assert Curve.verifyPrehash({blob(encoded(key_point))},{blob(octets(0))},{blob(octets(r) + octets(s))}) == #ok(true);\n"
    (run / "audit-secp256k1-equation-boundaries.mo").write_text(text)
    counts["ecdsa_identity_and_reduced_x_cases"] = 4
    (out / "generated.json").write_text(json.dumps({"inherited": inherited, "additional": counts,
        "fixture_sha256": {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(run.glob("*.mo"))}}, indent=2) + "\n")
    print(json.dumps(counts))

if __name__ == "__main__":
    main()
