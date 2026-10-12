#!/usr/bin/env python3
"""Pin combined artifacts, recheck all comb constants, extract reviewed Wasm."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--candidate", required=True, type=Path)
parser.add_argument("--openssl", required=True)
parser.add_argument("--previous-wat", required=True, type=Path)
args = parser.parse_args()
root = args.candidate.resolve()
out = Path(__file__).resolve().parent
paths = [
    "plugins/p256/runtime/src/lib.rs",
    "plugins/p256/compiler/register.ml",
    "dist/p256/runtime.wasm",
    "dist/p256/plugin.cmxs",
    "dist/p256/build.json",
]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in paths}
assert hashes[paths[0]] == "62d91a66f36452d67dba91e93092aceb3ec83368816a60e42fbf333d138cb664"
assert hashes[paths[1]] == "369d3b99f0c8d00e497728baf872d5b2f4817dafc6a6f22c741e1521c3ca7f8c"
assert hashes[paths[2]] == "83803f3d2462cb866e730fad94d73073cffdb574333a48301917e52c529c1c84"
assert hashes[paths[3]] == "e08b0987cb80beb26448900fe6c7c75a8e6a7b6e4153ea09e02f3f652c9a1c74"
source = (root / paths[0]).read_text()
table_source = source.split("const GENERATOR_COMB: [[u8; 65]; 15] = [", 1)[1].split("\n];", 1)[0]
table = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-f]{2})", table_source))
assert len(table) == 15 * 65
checks = []
for index in range(1, 16):
    encoded = table[(index - 1) * 65:index * 65]
    scalar = sum(1 << (64 * column) for column in range(4) if (index >> column) & 1)
    # No public key included: OpenSSL must derive the exact generator multiple.
    private = bytes.fromhex("30310201010420") + scalar.to_bytes(32, "big") + bytes.fromhex("a00a06082a8648ce3d030107")
    generated = subprocess.run(
        [args.openssl, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
        input=private, capture_output=True, check=True,
    ).stdout
    expected = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200") + encoded
    assert generated == expected, index
    checks.append({"index": index, "scalar_hex": f"{scalar:064x}", "point_hex": encoded.hex(), "correct": True})

wat = subprocess.check_output(["wasm2wat", "--enable-memory64", str(root / paths[2])], text=True)
start = wat.index("  (func $p256_public_key ")
end = wat.find("\n  (func ", start + 1)
function = wat[start:end] + "\n"
assert function == args.previous_wat.read_text()
(out / "p256-public-key.wat").write_text(function)
(out / "register.ml.reviewed").write_text((root / paths[1]).read_text())
result = {
    "candidate": str(root),
    "artifact_sha256": hashes,
    "verifier_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "openssl_version": subprocess.check_output([args.openssl, "version"], text=True).strip(),
    "openssl_binary_sha256": hashlib.sha256(Path(args.openssl).read_bytes()).hexdigest(),
    "wasm2wat_version": subprocess.check_output(["wasm2wat", "--version"], text=True).strip(),
    "public_key_wat_sha256": hashlib.sha256(function.encode()).hexdigest(),
    "identical_to_previously_reviewed_comb_function": True,
    "previous_wat_path": str(args.previous_wat.resolve()),
    "table_checks": checks,
    "passed": len(checks),
}
(out / "results.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"passed": len(checks), "identical_public_key_function": True, "output_directory": str(out)}))
