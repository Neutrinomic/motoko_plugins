#!/usr/bin/env python3
"""Independent integer P-256 oracle for the protected prepared-key ABI.

Does not import runtime or production generation code. The only production
input is the chosen comb width, so expected bytes follow the selected format.
"""

import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
G = (
    0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
    0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5,
)


def add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    x, y = a
    u, v = b
    if x == u:
        if (y + v) % P == 0:
            return None
        slope = (3 * x * x - 3) * pow(2 * y, -1, P) % P
    else:
        slope = (v - y) * pow(u - x, -1, P) % P
    z = (slope * slope - x - u) % P
    return z, (slope * (x - z) - y) % P


def mul(k, point=G):
    k %= N
    result = None
    while k:
        if k & 1:
            result = add(result, point)
        point = add(point, point)
        k >>= 1
    return result


def point_at(x):
    rhs = (x * x * x - 3 * x + B) % P
    y = pow(rhs, (P + 1) // 4, P)
    return (x, y) if y * y % P == rhs else None


def sec1(point, compressed):
    x, y = point
    return bytes([2 | (y & 1)]) + x.to_bytes(32, "big") if compressed else (
        b"\x04" + x.to_bytes(32, "big") + y.to_bytes(32, "big")
    )


def encode_table(point, width):
    rows = (256 + width - 1) // width
    basis = [point]
    for _ in range(width - 1):
        item = basis[-1]
        for _ in range(rows):
            item = add(item, item)
        basis.append(item)
    output = bytearray()
    for digit in range(1, 1 << width):
        entry = None
        for column in range(width):
            if digit >> column & 1:
                entry = add(entry, basis[column])
        assert entry is not None
        for coordinate in entry:
            # Explicit little-endian Montgomery integer, not object bytes.
            output.extend((coordinate * (1 << 256) % P).to_bytes(32, "little"))
    return output.hex()


def main():
    source = ROOT / "plugins/p256/runtime/src/prepared_table.rs"
    source_text = source.read_text()
    width = int(re.search(r"WIDTH: usize = (\d+)", source_text).group(1))
    assert width in (4, 6, 8)
    def constants(name):
        block = re.search(r"pub const " + name + r"\b[^=]*=\s*\[(.*?)\n\];", source_text, re.S)
        assert block is not None, name
        words = [int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]+)", block.group(1))]
        return b"".join(word.to_bytes(8, "little") for word in words).hex()
    assert constants("GENERATOR") == encode_table(G, width)
    assert constants("ODD_GENERATOR") == "".join(encode_table(mul(odd), 1) for odd in range(1, 16, 2))
    keys, indices, vectors = [], {}, []

    def key(point, label):
        encoded = sec1(point, True).hex()
        if encoded not in indices:
            indices[encoded] = len(keys)
            keys.append({
                "label": label,
                "compressed": encoded,
                "uncompressed": sec1(point, False).hex(),
                "prepared": encode_table(point, width),
            })
        return indices[encoded]

    def case(label, point, z, r, s, expected=None):
        assert 0 <= z < 1 << 256 and 0 < r < N and 0 < s < N
        result = add(mul(z * pow(s, -1, N)), mul(r * pow(s, -1, N), point))
        actual = result is not None and result[0] % N == r
        if expected is not None:
            assert actual == expected, label
        vectors.append({
            "label": label,
            "key": key(point, label),
            "digest": z.to_bytes(32, "big").hex(),
            "signature": (r.to_bytes(32, "big") + s.to_bytes(32, "big")).hex(),
            "expected": actual,
        })

    digests = [0, 1, N - 1, N, N + 1, (1 << 256) - 1]
    secrets = [1, 2, N - 1, (1 << 64) - 1, 1 << 128, 1 << 255]
    nonces = [1, N - 1, 1 << 64, (1 << 192) + 1]
    for i, secret in enumerate(secrets):
        point = mul(secret)
        for j, z in enumerate(digests):
            nonce = nonces[(i + j) % len(nonces)]
            r = mul(nonce)[0] % N
            s = pow(nonce, -1, N) * (z + r * secret) % N
            assert r and s
            case(f"valid-{i}-{j}", point, z, r, s, True)
            case(f"flipped-S-{i}-{j}", point, z, r, N - s, True)
            case(f"changed-r-{i}-{j}", point, z, r % (N - 1) + 1, s)

    # Force verification's x-coordinate reduction, including high-S.
    count = 0
    for r in range(1, 100):
        point_r = point_at(N + r)
        if point_r is None:
            continue
        for z, s in [(0, 1), (1, N - 1), ((1 << 256) - 1, 2)]:
            minus_zg = mul(-z)
            point = mul(pow(r, -1, N), add(mul(s, point_r), minus_zg))
            assert point is not None
            case(f"x-ge-n-{r}-{z}-{s}", point, z, r, s, True)
            case(f"x-ge-n-highS-{r}-{z}-{s}", point, z, r, N - s, True)
        count += 1
        if count == 3:
            break
    assert count == 3

    # Complete addition must tolerate cancellation, equal points and zero terms.
    for r in [1, 2, N - 1, 1 << 64, 1 << 255]:
        case(f"identity-G-{r}", G, N - r, r, 1, False)
        case(f"identity-negG-{r}", mul(N - 1), r, r, 1, False)
    for x in [0, 1, 2, P - 1, P - 2, P - 3]:
        point = point_at(x)
        if point is not None:
            key(point, f"field-coordinate-{x}")
            for z in digests:
                case(f"field-boundary-{x}-{z}", point, z, 1, N - 1)

    for i in range(32):
        def integer(tag):
            return int.from_bytes(hashlib.sha256(f"p256-prepared-audit/{i}/{tag}".encode()).digest(), "big")
        secret = integer("secret") % (N - 1) + 1
        z = integer("digest")
        # Reuse six public keys to keep the serialized table corpus compact.
        point = mul(secrets[i % len(secrets)])
        case(f"random-equation-{i}", point, z, secret, integer("s") % (N - 1) + 1)

    invalid_keys = ["", "00", "02", "04", "05" + "00" * 32,
                    "02" + P.to_bytes(32, "big").hex(),
                    "03" + ((1 << 256) - 1).to_bytes(32, "big").hex(),
                    "04" + "00" * 64,
                    "04" + P.to_bytes(32, "big").hex() + G[1].to_bytes(32, "big").hex(),
                    "04" + G[0].to_bytes(32, "big").hex() + P.to_bytes(32, "big").hex(),
                    "06" + sec1(G, False)[1:].hex()]
    report = {
        "width": width, "payload_bytes": ((1 << width) - 1) * 64,
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "chosen_table_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "keys": keys, "verify": vectors, "invalid_keys": invalid_keys,
    }
    (HERE / "vectors.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"keys": len(keys), "verification_cases": len(vectors), "width": width}))


if __name__ == "__main__":
    main()
