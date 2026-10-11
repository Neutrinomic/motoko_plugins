#!/usr/bin/env python3
"""Independent CBOR->LEB oracle; generated inputs stay in audit scratch."""
from pathlib import Path
import argparse
import hashlib
import importlib.metadata
import json
import random
import cbor2

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--worktree", required=True, type=Path)
parser.add_argument("--out", required=True, type=Path)
args = parser.parse_args()
root = args.out.resolve()
root.mkdir(parents=True, exist_ok=True)
(root / "run").mkdir(exist_ok=True)
(root / "run-drun").mkdir(exist_ok=True)
source = args.worktree / "plugins/cbor/runtime/src/lib.rs"

def leb(n, signed):
    out = bytearray()
    while True:
        byte = n & 127
        n >>= 7
        if (not signed and n == 0) or (signed and ((n == 0 and byte & 64 == 0) or (n == -1 and byte & 64 != 0))):
            out.append(byte)
            return bytes(out)
        out.append(byte | 128)

values = {0, 1}
for bit in list(range(257)) + [511, 512, 513, 1023, 1024, 1025, 2047, 2048, 4095, 4096, 8191, 8192, 16383, 16384, 32767, 32768]:
    for delta in [-2, -1, 0, 1, 2]:
        n = (1 << bit) + delta
        if 0 <= n < 1 << 32768:
            values.add(n)
rng = random.Random(0xCBC2026)
for size in [1, 2, 7, 8, 9, 16, 31, 32, 63, 64, 127, 128, 255, 256, 511, 512, 1023, 4095, 4096]:
    for _ in range(8):
        values.add(int.from_bytes(rng.randbytes(size), "big"))

rows = []
for n in sorted(values):
    for value, signed in [(n, False), (n, True), (-1-n, True)]:
        rows.append((cbor2.dumps(value, canonical=True), signed, leb(value, signed)))
    # A decoder may accept nonpreferred bignum representations, including
    # empty magnitude and redundant leading zero bytes. Their numeric value
    # must be preserved; input limits still apply to the original magnitude.
    if n < 1 << 128:
        raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
        for padding in [0, 1, 9]:
            magnitude = b"\0" * padding + raw
            for value, signed, tag in [(n, False, 2), (n, True, 2), (-1-n, True, 3)]:
                wire = bytes([0xc0 + tag]) + cbor2.dumps(magnitude)
                assert cbor2.loads(wire) == value
                rows.append((wire, signed, leb(value, signed)))

vectors = "".join(f"{wire.hex()} {int(signed)} {expected.hex()}\n" for wire, signed, expected in rows)
(root / "vectors.txt").write_text(vectors)
extra = r'''
#[test]
fn independent_python_integer_oracle_and_reused_scalar() {
    fn bytes(hex: &str) -> Vec<u8> {
        hex.as_bytes().chunks_exact(2).map(|part| {
            u8::from_str_radix(core::str::from_utf8(part).unwrap(), 16).unwrap()
        }).collect()
    }
    let mut context = Context::new(&[]);
    let mut count = 0;
    for line in include_str!("vectors.txt").lines() {
        let parts: Vec<_> = line.split(' ').collect();
        let mut wire = bytes(parts[0]);
        wire.extend_from_slice(&[0x62, 0xc3, 0xa9]);
        context.input = Box::leak(wire.into_boxed_slice());
        context.at = 0;
        let signed: usize = parts[1].parse().unwrap();
        let previous_capacity = context.scalar.capacity();
        let previous_pointer = context.scalar.as_ptr();
        unsafe { cbor_read_bigint(&mut context as *mut Context as usize, signed) };
        assert!(context.error.is_none(), "case {count}");
        let expected = bytes(parts[2]);
        assert_eq!(context.scalar, expected, "case {count}");
        assert!(context.borrowed.is_none());
        assert!(context.scalar.len() <= MAX_LEB_BYTES);
        if context.scalar.capacity() == previous_capacity {
            assert_eq!(context.scalar.as_ptr(), previous_pointer);
        }
        assert_eq!(*context.scalar.last().unwrap() & 128, 0);
        assert!(context.scalar[..context.scalar.len()-1].iter().all(|byte| byte & 128 != 0));
        unsafe { cbor_read_string(&mut context as *mut Context as usize) };
        assert_eq!(context.borrowed, Some(&[0xc3, 0xa9][..]));
        count += 1;
    }
    println!("independent Python integer oracle: {count} canonical/nonpreferred cases; scalar reuse and borrowed UTF-8 interleaving passed");
}

#[test]
fn audit_integer_input_limits_and_errors_after_reuse() {
    for (wire, signed, kind) in [
        (vec![0x20], 0, "range"),
        (vec![0xc3, 0x40], 0, "range"),
        (vec![0xc2, 0x61, b'x'], 1, "type"),
        (vec![0xc2, 0x49, 1, 2, 3], 1, "syntax"),
        (vec![0x1a, 0], 1, "syntax"),
        (vec![0xff], 1, "unsupported"),
        ({ let mut v = vec![0xc2, 0x59, 0x10, 0x01]; v.extend(vec![0; 4097]); v }, 1, "limit"),
    ] {
        let mut context = Context::new(Box::leak(wire.into_boxed_slice()));
        context.scalar = vec![0x80; 5000];
        context.borrowed = Some(b"stale");
        unsafe { cbor_read_bigint(&mut context as *mut Context as usize, signed) };
        assert_eq!(context.error.as_ref().unwrap().kind, kind);
        assert_eq!(context.scalar, [0]);
        assert!(context.borrowed.is_none());
    }
}
'''
(root / "oracle.rs").write_text(source.read_text() + extra)

def blob(wire):
    return '"' + ''.join(f'\\{byte:02x}' for byte in wire) + '"'

# Full retained values, generated independently from cbor2 wire bytes, cross
# LEB group, compact integer and managed bignum boundaries in both signs.
small = {0, 1}
for bit in [6, 7, 8, 13, 14, 15, 31, 32, 62, 63, 64, 65, 127, 128, 255, 256, 4095]:
    small.update([(1 << bit) - 1, 1 << bit, (1 << bit) + 1])
ints = [x for n in sorted(small) for x in (n, -1-n)]
tuples = [[n, "é", -1-n, b"\0\xff"] for n in sorted(small)]
expected_ints = '[' + ','.join(str(n) for n in ints) + ']'
expected_tuples = '[' + ','.join(f'({n},"é",{-1-n},"\\00\\ff")' for n in sorted(small)) + ']'
common = f'''import Prim "mo:⛔";
func ok<T,E>(value : {{#ok : T; #err : E}}) : T {{ switch value {{case (#ok v) v;case _ Prim.trap("CBOR error")}} }};
let expectedInts : [Int] = {expected_ints};
let expectedTuples : [(Nat, Text, Int, Blob)] = {expected_tuples};
'''
flags = f'//MOC-FLAG --plugin {args.worktree.resolve() / "dist/cbor"}\n//MOC-FLAG --sanity-checks\n'
(root / "run/cbor-audit-oracle.mo").write_text(flags + common + f'''
let ints = ok(Prim.from_cbor<[Int]>({blob(cbor2.dumps(ints, canonical=True))}));
let tuples = ok(Prim.from_cbor<[(Nat, Text, Int, Blob)]>({blob(cbor2.dumps(tuples, canonical=True))}));
assert ints == expectedInts;
assert tuples == expectedTuples;
''')
gc = flags + '//MOC-FLAG --force-gc\n//SKIP run\n//SKIP run-ir\n//SKIP run-low\nimport Prim "mo:⛔";\nactor {\n'
gc += common.split('\n', 1)[1]
gc += f'''
var ints : [Int] = [];
var tuples : [(Nat, Text, Int, Blob)] = [];
public func prepare() : async () {{
  ints := ok(Prim.from_cbor<[Int]>({blob(cbor2.dumps(ints, canonical=True))}));
  tuples := ok(Prim.from_cbor<[(Nat, Text, Int, Blob)]>({blob(cbor2.dumps(tuples, canonical=True))}));
  assert ints == expectedInts; assert tuples == expectedTuples;
}};
public func churn() : async () {{ var i = 0; while(i < 9) {{ ignore Prim.Array_init<Nat>(1024*1024, i); i += 1 }} }};
public func check() : async () {{ var i = 0; while(i < 4) {{ await async {{}}; assert ints == expectedInts; assert tuples == expectedTuples; i += 1 }} }};
}};
//CALL ingress prepare "DIDL\\x00\\x00"
//CALL ingress churn "DIDL\\x00\\x00"
//CALL ingress check "DIDL\\x00\\x00"
'''
(root / "run-drun/cbor-audit-gc.mo").write_text(gc)
print(json.dumps({"vectors": len(rows), "retained_ints": len(ints), "retained_mixed_tuples": len(tuples), "cbor2_version": importlib.metadata.version("cbor2"), "runtime_source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "vectors_sha256": hashlib.sha256(vectors.encode()).hexdigest()}, indent=2))
