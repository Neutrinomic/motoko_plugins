#!/usr/bin/env python3
"""Generate independent JSON oracles without committing generated test data."""

import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import random
import re
import struct
import zlib


AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[3]


def header(plugin):
    return [
        f"//MOC-FLAG --plugin {plugin}",
        'import Prim "mo:⛔";',
        "type E = { kind:Text; message:Text; path:Text; offset:Nat64 };",
        'func ok<T>(r:{#ok:T;#err:E}):T { switch r { case (#ok v) v; case (#err e) Prim.trap(debug_show e) } };',
    ]


def scalar_cases(plugin):
    rng = random.Random(312031)
    lines = header(plugin)
    count = 0
    for typ, bits, signed in [
        ("Nat8", 8, False), ("Int8", 8, True),
        ("Nat16", 16, False), ("Int16", 16, True),
        ("Nat32", 32, False), ("Int32", 32, True),
        ("Nat64", 64, False), ("Int64", 64, True),
    ]:
        lo = -(1 << (bits - 1)) if signed else 0
        hi = (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1
        values = [lo, lo + 1, 0, 1, hi - 1, hi]
        values += [rng.randint(lo, hi) for _ in range(30)]
        for value in values:
            token = json.dumps(str(value)) if bits == 64 else str(value)
            encoded = json.dumps(token)
            lines += [
                f"assert ok(Prim.to_json(({value} : {typ}))) == {encoded};",
                f"assert ok(Prim.from_json<{typ}>({encoded})) == ({value} : {typ});",
            ]
            count += 1
    for typ, signed in [("Nat", False), ("Int", True)]:
        for bits in [
            0, 1, 6, 7, 8, 13, 14, 15, 31, 32, 33, 63, 64, 65,
            127, 128, 129, 255, 256, 257, 1023, 4095, 10000, 13600,
        ]:
            value = rng.getrandbits(bits)
            if signed and rng.randrange(2):
                value = -value
            encoded = json.dumps(json.dumps(str(value)))
            lines += [
                f"assert ok(Prim.to_json(({value} : {typ}))) == {encoded};",
                f"assert ok(Prim.from_json<{typ}>({encoded})) == ({value} : {typ});",
            ]
            count += 1
    for typ, bits in [("Float", 64), ("Float32", 32)]:
        values = []
        while len(values) < 128:
            value = struct.unpack(
                ">d" if bits == 64 else ">f",
                rng.getrandbits(bits).to_bytes(bits // 8, "big"),
            )[0]
            if math.isfinite(value):
                values.append(value)
        values += [0.0, -0.0, 1.0, -1.0, 2.0, 0.5]
        for value in values:
            mantissa, exponent = format(value, ".16e").split("e")
            encoded = json.dumps(mantissa + "e" + str(int(exponent)))
            literal = value.hex()
            lines += [
                f"assert ok(Prim.to_json(({literal} : {typ}))) == {encoded};",
                f"assert ok(Prim.from_json<{typ}>({encoded})) == ({literal} : {typ});",
            ]
            count += 1
    source = "\n".join(lines) + "\n"
    # Hex literals describe the exact independent IEEE values. Convert f32
    # values from exact binary64 literals rather than parsing decimal twice.
    source = re.sub(
        r"\(([-+]?0x[0-9a-f.]+p[+-]\d+) : Float32\)",
        r"Prim.floatToFloat32(\1 : Float)",
        source,
    )
    # The current compiler can emit M0266 for exact negative hex literals.
    # Suppress only that diagnostic in this generated numeric corpus.
    return "//MOC-FLAG -A M0266\n" + source, count


def mo_bytes(value):
    return '"' + "".join(f"\\{byte:02x}" for byte in value) + '"'


def mo_text(value):
    # Keep JSON escape spelling separate from Motoko escape spelling.
    return mo_bytes(value.encode())


def principal_text(value):
    checksum = zlib.crc32(value).to_bytes(4, "big")
    encoded = base64.b32encode(checksum + value).decode().lower().rstrip("=")
    return "-".join(encoded[i:i + 5] for i in range(0, len(encoded), 5))


def binary_cases(plugin):
    rng = random.Random(3980)
    lines = header(plugin) + [
        'func err<T>(r:{#ok:T;#err:E}):E { switch r { case (#err e) e; case (#ok _) Prim.trap("expected error") } };',
    ]
    count = 0
    for size in [0, 1, 2, 3, 4, 5, 7, 8, 9, 13, 63, 64, 127, 255, 256, 257, 1023, 4096]:
        value = rng.randbytes(size)
        encoded = mo_text(json.dumps(base64.b64encode(value).decode()))
        lines += [
            f"assert ok(Prim.to_json(({mo_bytes(value)} : Blob))) == {encoded};",
            f"assert ok(Prim.from_json<Blob>({encoded})) == ({mo_bytes(value)} : Blob);",
        ]
        count += 1
    for _ in range(4):
        for size in range(30):
            value = rng.randbytes(size)
            principal = principal_text(value)
            encoded = mo_text(json.dumps(principal))
            lines += [
                f"assert ok(Prim.to_json(Prim.principalOfBlob({mo_bytes(value)}))) == {encoded};",
                f"assert ok(Prim.from_json<Principal>({encoded})) == Prim.principalOfBlob({mo_bytes(value)});",
            ]
            for bad in [
                principal.upper(), "-" + principal, principal + "-",
                principal.replace("-", ""), principal + "a",
            ]:
                if bad != principal:
                    lines.append(
                        f'assert err(Prim.from_json<Principal>({mo_text(json.dumps(bad))})).kind == "principal";'
                    )
            count += 1
    for codepoint in [
        0, 8, 9, 10, 12, 13, 31, 32, 34, 47, 92, 127, 128, 255, 256,
        2047, 2048, 0xD7FF, 0xE000, 0xFFFE, 0xFFFF, 0x10000, 0x10FFFF,
    ]:
        character = chr(codepoint)
        decoded = mo_text(json.dumps(character, ensure_ascii=True))
        encoded = json.dumps(character, ensure_ascii=False)
        encoded = mo_text(encoded.replace("\\b", "\\u0008").replace("\\f", "\\u000c"))
        literal = "'\\u{" + format(codepoint, "x") + "}'"
        lines += [
            f"assert ok(Prim.from_json<Char>({decoded})) == {literal};",
            f"assert ok(Prim.to_json({literal})) == {encoded};",
        ]
        count += 1
    return "\n".join(lines) + "\n", count


def reject_constant(value):
    raise ValueError(value)


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate")
        result[key] = value
    return result


def validate_unicode(value):
    if isinstance(value, str):
        value.encode("utf-8")
    elif isinstance(value, list):
        for child in value:
            validate_unicode(child)
    elif isinstance(value, dict):
        for key, child in value.items():
            validate_unicode(key)
            validate_unicode(child)


def syntax_cases():
    rng = random.Random(317)
    seeds = [
        "null", "true", "false", "0", "-0", "1", "-128", "1.00e+30",
        "[]", "{}", "[1,2]", '{"a":0,"b":[true,null]}', '""', '"😀"',
        '"\\uD83D\\uDE00"', '"\\u0061"', '"\\n\\t\\u0000"',
        '{"x":0,"\\u0078":1}', '{"café/~": ["x", 1, {"β":null}]}',
        '"\\uD800"', '"\\uDC00"', '"\\uD800\\uDC00"',
    ]
    characters = '[]{}:,"\\01239-.eE+atfnrulxyz \t\r\n' + 'é😀' + '\x00\x01\x08\x1f\ufeff'
    cases = set(seeds)
    for seed in seeds:
        for _ in range(300):
            value = seed
            for _ in range(rng.randint(1, 3)):
                index = rng.randrange(len(value) + 1)
                if rng.randrange(2) and value:
                    value = value[:index] + value[index + 1:]
                else:
                    value = value[:index] + rng.choice(characters) + value[index:]
            cases.add(value)
    for _ in range(3000):
        cases.add("".join(rng.choice(characters) for _ in range(rng.randrange(25))))
    rows = []
    for value in sorted(cases):
        try:
            validate_unicode(json.loads(
                value, parse_constant=reject_constant, object_pairs_hook=reject_duplicates,
            ))
            valid = 1
        except (ValueError, UnicodeError):
            valid = 0
        rows.append(f"{valid}\t{value.encode().hex()}")

    rng = random.Random(3940)
    keys = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k",
        "~", "/", "😀", "é", "\n", "\x00", "\\", '"', "💯", "z", "",
    ]
    for _ in range(2000):
        selected = rng.sample(keys, rng.randrange(8, len(keys)))
        duplicate = rng.randrange(2) == 0
        if duplicate:
            selected.insert(rng.randrange(len(selected) + 1), rng.choice(selected))
        parts = []
        for index, key in enumerate(selected):
            # Keep the parent frame active across nested small and wide frames.
            child = "{" + ",".join(
                json.dumps("child" + str(i)) + ":" + str(i)
                for i in range(1 + (index * 3) % 15)
            ) + "}"
            parts.append(json.dumps(key, ensure_ascii=rng.randrange(2) == 0) + ":" + child)
        value = "{" + ",".join(parts) + "}"
        rows.append(f"{int(not duplicate)}\t{value.encode().hex()}")
    return "\n".join(rows) + "\n", len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "_build/json-audit")
    parser.add_argument("--plugin", type=Path, default=ROOT / "dist/json")
    args = parser.parse_args()
    output = args.output.resolve()
    plugin = args.plugin.resolve()
    # test-runner's MOC-FLAG syntax uses whitespace-separated arguments.
    if any(character.isspace() for character in str(plugin)):
        parser.error("--plugin must point to a path without whitespace")
    (output / "run").mkdir(parents=True, exist_ok=True)
    (output / "src").mkdir(parents=True, exist_ok=True)
    scalar_source, scalar_count = scalar_cases(plugin)
    binary_source, binary_count = binary_cases(plugin)
    syntax_source, syntax_count = syntax_cases()
    (output / "run/roundtrip.mo").write_text(scalar_source)
    (output / "run/binary-unicode.mo").write_text(binary_source)
    (output / "src/oracle.tsv").write_text(syntax_source)

    # Compile a copy of the current production runtime, adding probes inside
    # its native-test module to reuse the allocation counter. Never edit it.
    runtime_path = ROOT / "plugins/json/runtime/src/lib.rs"
    runtime = runtime_path.read_text()
    if "\nmod tests {" not in runtime or not runtime.rstrip().endswith("}"):
        parser.error("runtime test module changed; update the probe insertion point")
    probes = (AUDIT / "runtime-probes.rs").read_text()
    (output / "src/lib.rs").write_text(runtime.rstrip()[:-1] + probes + "}\n")
    (output / "Cargo.toml").write_text(
        '[package]\nname = "json-independent-audit"\nversion = "0.0.0"\n'
        'edition = "2024"\n[workspace]\n'
    )
    counts = {"scalar": scalar_count, "binary_unicode": binary_count, "syntax": syntax_count}
    hashes = {"runtime_source": hashlib.sha256(runtime_path.read_bytes()).hexdigest()}
    for name in ["runtime.wasm", "plugin.cmxs"]:
        path = plugin / name
        if path.exists():
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    (output / "manifest.json").write_text(json.dumps({
        "cases": counts, "sha256": hashes,
        "seeds": {"scalar": 312031, "binary_unicode": 3980, "syntax": 317, "wide_objects": 3940},
    }, indent=2) + "\n")
    print(json.dumps({"output": str(output), "cases": counts}))


if __name__ == "__main__":
    main()
