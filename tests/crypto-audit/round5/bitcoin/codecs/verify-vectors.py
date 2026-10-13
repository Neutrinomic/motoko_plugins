#!/usr/bin/env python3
"""Independently check fixed codec fixtures and their mutation premises."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[5]
fixture = root / "packages/fast/tests/lib/CodecPropertiesCases.mo"
source = fixture.read_text()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bech32-reference", type=Path, help="Pinned upstream ref/python/segwit_addr.py (see REPORT.md)")
args = parser.parse_args()


def blob(name):
    match = re.search(rf'let {name} : Blob = "([^"]+)";', source)
    assert match, name
    return bytes.fromhex(match[1].replace("\\", ""))


def checksum(payload):
    return hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]


def base58(payload):
    alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    number = int.from_bytes(payload, "big")
    result = ""
    while number:
        number, remainder = divmod(number, 58)
        result = alphabet[remainder] + result
    return "1" * (len(payload) - len(payload.lstrip(b"\0"))) + result


payload, protected = blob("payload"), blob("protected")
assert protected == payload + checksum(payload)
address = re.search(r'assert Base58.encode\(protected\) == "([^"]+)";', source)[1]
assert base58(protected) == address
corruptions = 0
for position in range(len(protected)):
    for bit in range(8):
        damaged = bytearray(protected)
        damaged[position] ^= 1 << bit
        assert checksum(damaged[:-4]) != damaged[-4:]
        corruptions += 1
assert corruptions == 200
report = {
    "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "genesis_address": address,
    "checksum_hex": protected[-4:].hex(),
    "one_bit_corruptions_rejected": corruptions,
    "oracle": "Python standard-library hashlib double SHA-256 and integer Base58",
}
if args.bech32_reference:
    # sipa/bech32 7a7d7ab158db7078a333384e0e918c90dbc42917, MIT license.
    expected_hash = "2884ce04a36c8374c4249177cd90e91e545ac73b5c9260307bbeb74ae2e9de0f"
    assert hashlib.sha256(args.bech32_reference.read_bytes()).hexdigest() == expected_hash
    spec = importlib.util.spec_from_file_location("upstream_bech32", args.bech32_reference)
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    examples = re.findall(r'\("([a-z0-9]+)", (\d+), #(bech32m?)\)', source)
    assert len(examples) == 4
    mutations = 0
    for encoded, separator, encoding in examples:
        separator = int(separator)
        assert upstream.bech32_decode(encoded)[2].name.lower() == encoding
        for position, original in enumerate(encoded):
            if position == separator:
                continue
            alphabet = "abcdefghijklmnopqrstuvwxyz" if position < separator else upstream.CHARSET
            for replacement in alphabet:
                if replacement != original:
                    damaged = encoded[:position] + replacement + encoded[position + 1:]
                    # The upstream decoder recognizes BOTH checksum constants.
                    assert upstream.bech32_decode(damaged) == (None, None, None)
                    mutations += 1
    assert mutations == 3078
    report["bech32_reference_sha256"] = expected_hash
    report["bech32_substitutions_rejected_by_both_variants"] = mutations
print(json.dumps(report, indent=2))
