#!/usr/bin/env python3
"""Native Bech32 round-two workloads with an independent BIP/bitstring oracle.

No plugin implementation or interpreter result is used to derive expected bytes.
The oracle follows BIP173/BIP350 and checks their published address vectors.
"""
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
sys.path.insert(0, str(BENCH))
from common import actor, blob

ALPHABET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
CONSTANTS = {"bech32": 1, "bech32m": 0x2BC830A3}
GENERATORS = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
SOURCES = [
    "https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki",
    "https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki",
]


def polymod(values):
    """BIP checksum recurrence, independently written in Python."""
    remainder = 1
    for value in values:
        assert 0 <= value < 32
        shifted = (remainder << 5) ^ value
        overflow = shifted >> 30
        remainder = shifted & ((1 << 30) - 1)
        for bit, polynomial in enumerate(GENERATORS):
            if overflow & (1 << bit):
                remainder ^= polynomial
    return remainder


def hrp_values(hrp):
    return [ord(c) // 32 for c in hrp] + [0] + [ord(c) % 32 for c in hrp]


def encode(hrp, data, variant):
    assert 1 <= len(hrp) <= 83 and all(33 <= ord(c) <= 126 for c in hrp)
    assert hrp == hrp.lower() or hrp == hrp.upper()
    assert len(hrp) + len(data) + 7 <= 90
    hrp = hrp.lower()
    checksum = polymod(hrp_values(hrp) + list(data) + [0] * 6) ^ CONSTANTS[variant]
    checksum_groups = [(checksum >> shift) & 31 for shift in range(25, -1, -5)]
    return hrp + "1" + "".join(ALPHABET[value] for value in [*data, *checksum_groups])


def decode(address):
    assert 8 <= len(address) <= 90
    assert address == address.lower() or address == address.upper()
    hrp, encoded = address.lower().rsplit("1", 1)
    assert hrp and len(encoded) >= 6 and all(33 <= ord(c) <= 126 for c in hrp)
    values = [ALPHABET.index(c) for c in encoded]
    residue = polymod(hrp_values(hrp) + values)
    variant = next(name for name, constant in CONSTANTS.items() if residue == constant)
    return hrp, bytes(values[:-6]), variant


def convert_bits(data, from_bits, to_bits, pad):
    """Use a literal bitstring, independent of the runtime's accumulator loop."""
    assert 1 <= from_bits <= 8 and 1 <= to_bits <= 8
    assert all(value < 1 << from_bits for value in data)
    bits = "".join(format(value, f"0{from_bits}b") for value in data)
    full_bits = len(bits) // to_bits * to_bits
    if pad:
        bits += "0" * (-len(bits) % to_bits)
    else:
        remainder = bits[full_bits:]
        assert len(remainder) < from_bits and "1" not in remainder
        bits = bits[:full_bits]
    return bytes(int(bits[i:i + to_bits], 2) for i in range(0, len(bits), to_bits))


def segwit_encode(hrp, version, program):
    assert 0 <= version <= 16 and 2 <= len(program) <= 40
    assert version != 0 or len(program) in (20, 32)
    groups = bytes([version]) + convert_bits(program, 8, 5, True)
    return encode(hrp, groups, "bech32" if version == 0 else "bech32m")


def segwit_decode(address):
    hrp, groups, variant = decode(address)
    version = groups[0]
    assert 0 <= version <= 16
    assert variant == ("bech32" if version == 0 else "bech32m")
    program = convert_bits(groups[1:], 5, 8, False)
    assert 2 <= len(program) <= 40 and (version != 0 or len(program) in (20, 32))
    return hrp, version, program


def check_oracle():
    # Published BIP173/BIP350 generic checksums and SegWit address/script pairs.
    assert encode("a", b"", "bech32") == "a12uel5l"
    assert encode("a", b"", "bech32m") == "a1lqfn3a"
    assert encode("abcdef", bytes(range(32)), "bech32") == (
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw")
    official = [
        ("bc", 0, "751e76e8199196d454941c45d1b3a323f1433bd6",
         "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"),
        ("tb", 0, "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262",
         "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"),
        ("bc", 1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
         "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"),
        ("bc", 16, "751e", "bc1sw50qgdz25j"),
    ]
    for hrp, version, program_hex, address in official:
        program = bytes.fromhex(program_hex)
        assert segwit_encode(hrp, version, program) == address
        assert segwit_decode(address.upper()) == (hrp, version, program)
    return official


def unwrap(expression):
    return (f"switch ({expression}) {{ case (#ok(value)) value; "
            'case (#err(_)) Prim.trap("unexpected benchmark error") }')


def frame_decoder(payload, tag):
    # Query-only framing validates all fields without adding work to run().
    return ("Prim.arrayToBlob(Array.concat<Nat8>("
            "Array.concat<Nat8>(Prim.blobToArray(Prim.encodeUtf8(result.hrp)), "
            f"[0, {tag}]), Prim.blobToArray(result.{payload})))")


def generate():
    official = check_oracle()
    cases = []

    def add(name, imports, declarations, configure, measured_operation, expected,
            output_expr="result", output_type="Blob", initial='""', **metadata):
        path = HERE / name / "main.mo"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(actor(imports, declarations, configure, measured_operation,
                              output_expr, output_type, initial))
        cases.append({
            "name": name,
            "family": "bech32",
            "implementation": "native",
            "comparison": "round2-same-public-api",
            "plugins": ["bech32"],
            "source": path.relative_to(BENCH).as_posix(),
            "expected_hex": expected.hex(),
            "notes": "Independent Python BIP checksum/bitstring oracle. Input setup in configure; only API call, unwrap and assignment measured. Result serialization is query-only.",
            **metadata,
        })

    generic_shapes = [
        ("empty", "a", b""),
        ("small3", "bc", bytes([0, 1, 31])),
        ("normal33", "bc", bytes(i % 32 for i in range(33))),
        ("normal53", "bc", bytes((7 * i + 3) % 32 for i in range(53))),
        ("max90", "bc", bytes((11 * i + 5) % 32 for i in range(81))),
        ("hrp83-empty", "a" * 83, b""),
        ("hrp1-groups82", "a", bytes((13 * i + 1) % 32 for i in range(82))),
    ]
    for variant in CONSTANTS:
        for shape, hrp, data in generic_shapes:
            address = encode(hrp, data, variant)
            assert decode(address) == (hrp, data, variant)
            metadata = dict(operation="encode", shape=shape, encoding=variant,
                            hrp_chars=len(hrp), data_groups=len(data), address_chars=len(address))
            add(f"bech32-generic-{variant}-encode-{shape}", 'import B "mo:fast/Bech32";',
                'transient var hrp : Text = ""; transient var input : Blob = "";',
                f"hrp := {json.dumps(hrp)}; input := {blob(data)};",
                f"result := {unwrap(f'B.encode(hrp, input, #{variant})')};", address.encode(),
                "Prim.encodeUtf8(result)", "Text", **metadata)
            metadata["operation"] = "decode"
            expected = hrp.encode() + bytes([0, int(variant == "bech32m")]) + data
            add(f"bech32-generic-{variant}-decode-{shape}",
                'import B "mo:fast/Bech32";\nimport Array "mo:core/Array";',
                'transient var input : Text = "";', f"input := {json.dumps(address)};",
                f"result := {unwrap('B.decode(input)')};", expected,
                frame_decoder("data", "if (result.encoding == #bech32) 0 else 1"),
                "B.Decoded", '{ hrp = ""; data = ""; encoding = #bech32 }', **metadata)

    conversions = []
    for size in (20, 32, 40, 4096):
        data = bytes((i * 73 + 41) % 256 for i in range(size))
        groups = convert_bits(data, 8, 5, True)
        assert convert_bits(groups, 5, 8, False) == data
        conversions.extend([
            (f"8to5-n{size}", data, 8, 5, True),
            (f"5to8-program{size}", groups, 5, 8, False),
        ])
    conversions.extend([
        ("7to3-n19", bytes((i * 31 + 9) % 128 for i in range(19)), 7, 3, True),
        ("5to5-n41", bytes((i * 13 + 7) % 32 for i in range(41)), 5, 5, False),
        ("8to5-empty", b"", 8, 5, True),
        ("5to8-empty", b"", 5, 8, False),
    ])
    for shape, data, from_bits, to_bits, pad in conversions:
        expected = convert_bits(data, from_bits, to_bits, pad)
        expression = f"B.convertBits(input, {from_bits}, {to_bits}, {str(pad).lower()})"
        add(f"bech32-convert-{shape}", 'import B "mo:fast/Bech32";',
            'transient var input : Blob = "";', f"input := {blob(data)};",
            f"result := {unwrap(expression)};", expected,
            operation="convertBits", shape=shape, from_bits=from_bits, to_bits=to_bits,
            pad=pad, input_groups=len(data), output_groups=len(expected))

    for hrp, version, program_hex, address in official:
        program = bytes.fromhex(program_hex)
        shape = f"v{version}-program{len(program)}"
        metadata = dict(shape=shape, witness_version=version, hrp=hrp,
                        program_bytes=len(program), address_chars=len(address))
        add(f"bech32-segwit-encode-{shape}", 'import S "mo:fast/Segwit";',
            'transient var hrp : Text = ""; transient var version : Nat8 = 0; transient var input : Blob = "";',
            f"hrp := {json.dumps(hrp)}; version := {version}; input := {blob(program)};",
            f"result := {unwrap('S.encode(hrp, version, input)')};", address.encode(),
            "Prim.encodeUtf8(result)", "Text", operation="segwit-encode", **metadata)
        expected = hrp.encode() + bytes([0, version]) + program
        add(f"bech32-segwit-decode-{shape}",
            'import S "mo:fast/Segwit";\nimport Array "mo:core/Array";',
            'transient var input : Text = "";', f"input := {json.dumps(address)};",
            f"result := {unwrap('S.decode(input)')};", expected,
            frame_decoder("program", "result.version"), "S.Decoded",
            '{ hrp = ""; version = 0; program = "" }', operation="segwit-decode", **metadata)

    assert len(cases) == 48 and len({case["name"] for case in cases}) == len(cases)
    manifest = {
        "oracle": {
            "description": "Independent Python polymod and literal-bitstring conversion; published BIP173 and BIP350 vectors asserted before generation.",
            "sources": SOURCES,
            "generator": Path(__file__).relative_to(BENCH).as_posix(),
            "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "decoded_result_framing": "UTF-8 HRP, 0x00 delimiter, one-byte tag (generic: Bech32=0/Bech32m=1; SegWit: version), raw data/program bytes.",
        },
        "cases": cases,
    }
    (HERE / "cases.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(cases)} independent-oracle Bech32 round-two workloads")


if __name__ == "__main__":
    generate()
