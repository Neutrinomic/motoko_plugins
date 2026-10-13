#!/usr/bin/env python3
"""Independent RFC6979/HMAC/scalar oracle; OpenSSL supplies P-256 points.

Only deterministic public test seeds are used. The plugin, RustCrypto and
Motoko reference implementation do not participate in expected outputs.
"""
import argparse
import hashlib
import hmac
import json
from pathlib import Path
import subprocess

ORDER = int("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)
SPKI = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")


def mac(key, value):
    return hmac.new(key, value, hashlib.sha256).digest()


def nonce(secret, digest):
    material = secret + (int.from_bytes(digest, "big") % ORDER).to_bytes(32, "big")
    key, value = bytes(32), bytes([1]) * 32
    key = mac(key, value + b"\x00" + material)
    value = mac(key, value)
    key = mac(key, value + b"\x01" + material)
    value = mac(key, value)
    while True:
        value = mac(key, value)
        result = int.from_bytes(value, "big")
        if 0 < result < ORDER:
            return result
        key = mac(key, value + b"\x00")
        value = mac(key, value)


def point(openssl, scalar):
    sec1 = bytes.fromhex("30310201010420") + scalar.to_bytes(32, "big")
    sec1 += bytes.fromhex("a00a06082a8648ce3d030107")
    result = subprocess.run(
        [openssl, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
        input=sec1, capture_output=True, check=True,
    ).stdout
    assert result.startswith(SPKI) and len(result) == len(SPKI) + 65
    return result[len(SPKI):]


def vector(openssl, label, scalar, digest):
    secret = scalar.to_bytes(32, "big")
    k = nonce(secret, digest)
    r = int.from_bytes(point(openssl, k)[1:33], "big") % ORDER
    s = pow(k, -1, ORDER) * (int.from_bytes(digest, "big") + r * scalar) % ORDER
    assert r and s
    public = point(openssl, scalar)
    compressed = bytes([2 + (public[-1] & 1)]) + public[1:33]
    return {
        "label": label,
        "secret": secret.hex(),
        "digest": digest.hex(),
        "public": compressed.hex(),
        "signature": (r.to_bytes(32, "big") + s.to_bytes(32, "big")).hex(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    vectors = []
    for label, scalar in [("one", 1), ("order-minus-one", ORDER - 1), ("high-bit", 1 << 255)]:
        for name, digest in [("zero", 0), ("one", 1), ("order-minus-one", ORDER - 1),
                             ("order", ORDER), ("order-plus-one", ORDER + 1), ("max", 2**256 - 1)]:
            vectors.append(vector(args.openssl, f"{label}/{name}", scalar, digest.to_bytes(32, "big")))
    for i in range(24):
        scalar = int.from_bytes(hashlib.sha256(f"p256-independent-key-{i}".encode()).digest(), "big")
        scalar = scalar % (ORDER - 1) + 1
        digest = hashlib.sha256(f"p256-independent-digest-{i}".encode()).digest()
        vectors.append(vector(args.openssl, f"sha256-pair-{i}", scalar, digest))
    # Published RFC6979 Appendix A.2.5 validates this oracle's independent nonce
    # generation, integer equation and OpenSSL point encoding together.
    sample = vector(args.openssl, "RFC6979/sample",
                    int("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721", 16),
                    hashlib.sha256(b"sample").digest())
    assert sample["signature"] == (
        "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716"
        "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8")
    vectors.append(sample)
    result = {
        "openssl": subprocess.check_output([args.openssl, "version"], text=True).strip(),
        "oracle": "Python hashlib/HMAC RFC6979, Python modular scalar arithmetic, OpenSSL P-256 public-point derivation",
        "generatorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "count": len(vectors),
        "vectors": vectors,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
