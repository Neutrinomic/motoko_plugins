#!/usr/bin/env python3
"""Regenerate independent P-256 RFC6979 SHA-256 prehash boundary vectors.

Requires cryptography==46.0.3. The nonce generator below follows RFC6979
sections 2.3.4 and 3.2. OpenSSL derives the public point for each nonce;
Python integer arithmetic performs the ECDSA scalar equation. OpenSSL's
separate deterministic ECDSA implementation must produce identical bytes.
No plugin, RustCrypto or Mops implementation participates in this oracle.
"""

import hashlib
import hmac
import json

import cryptography
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

N = int("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)
SECRET = bytes.fromhex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
KEY = ec.derive_private_key(int.from_bytes(SECRET, "big"), ec.SECP256R1())


def mac(key, value):
    return hmac.new(key, value, hashlib.sha256).digest()


def nonces(digest):
    # qlen == hlen == 256 here. bits2octets must reduce modulo N before
    # seeding RFC6979; simply passing the raw digest is incorrect for h >= N.
    reduced = (int.from_bytes(digest, "big") % N).to_bytes(32, "big")
    seed = SECRET + reduced
    value = b"\x01" * 32
    key = b"\x00" * 32
    key = mac(key, value + b"\x00" + seed)
    value = mac(key, value)
    key = mac(key, value + b"\x01" + seed)
    value = mac(key, value)
    while True:
        value = mac(key, value)
        candidate = int.from_bytes(value, "big")
        if 0 < candidate < N:
            yield candidate
        key = mac(key, value + b"\x00")
        value = mac(key, value)


def sign(digest):
    secret = int.from_bytes(SECRET, "big")
    z = int.from_bytes(digest, "big")
    for nonce in nonces(digest):
        point = ec.derive_private_key(nonce, ec.SECP256R1()).public_key().public_numbers()
        r = point.x % N
        s = (pow(nonce, -1, N) * (z + r * secret)) % N
        if r == 0 or s == 0:
            continue
        compact = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        openssl_der = KEY.sign(
            digest, ec.ECDSA(utils.Prehashed(hashes.SHA256()), deterministic_signing=True)
        )
        assert utils.decode_dss_signature(openssl_der) == (r, s)
        KEY.public_key().verify(openssl_der, digest, ec.ECDSA(utils.Prehashed(hashes.SHA256())))
        return nonce, compact
    raise AssertionError("unreachable")


def main():
    # Validate this reference against both published RFC6979 P-256 SHA256
    # vectors before producing inputs that the RFC appendix does not include.
    for message, expected_nonce, expected_signature in [
        (
            b"sample",
            "a6e3c57dd01abe90086538398355dd4c3b17aa873382b0f24d6129493d8aad60",
            "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716"
            "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8",
        ),
        (
            b"test",
            "d16b6ae827f17175e040871a1c7ec3500192c4c92677336ec2537acaee0008e0",
            "f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367"
            "019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083",
        ),
    ]:
        nonce, signature = sign(hashlib.sha256(message).digest())
        assert nonce == int(expected_nonce, 16)
        assert signature.hex() == expected_signature

    vectors = []
    for name, integer in [("zero", 0), ("n_minus_one", N - 1), ("n", N), ("all_ff", 2**256 - 1)]:
        digest = integer.to_bytes(32, "big")
        nonce, signature = sign(digest)
        vectors.append({"name": name, "digest": digest.hex(), "nonce": f"{nonce:064x}", "signature": signature.hex()})
    assert vectors[0]["signature"] == vectors[2]["signature"]
    print(json.dumps({
        "source": "RFC6979 sections 2.3.4 and 3.2; independent Python HMAC/scalar equation and OpenSSL deterministic ECDSA",
        "cryptography_version": cryptography.__version__,
        "openssl_version": default_backend().openssl_version_text(),
        "secret_key": SECRET.hex(),
        "public_key_compressed": KEY.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.CompressedPoint).hex(),
        "vectors": vectors,
    }, indent=2))


if __name__ == "__main__":
    main()
