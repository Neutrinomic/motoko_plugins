#!/usr/bin/env python3
"""Create an isolated, instrumented copy; never edit the production crate.

Python/OpenSSL SHAKE supplies the oracle, independent of the Rust SHAKE and
coefficient helpers. Cargo execution is deliberately separate from preparation.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct

AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[3]
VENDOR = ROOT / "plugins/ml-dsa/runtime/vendor/fips204"
WORKSPACE_LOCK = ROOT / "Cargo.lock"
OUT = AUDIT / "_out"
CRATE = OUT / "instrumented-fips204"
Q = 8_380_417


def sha(data):
    return hashlib.sha256(data).hexdigest()


def sample(rho, column, row, ctest=False):
    stream = hashlib.shake_128(rho + bytes([column, row])).digest(4096)
    accepted, rejected = [], []
    for index in range(len(stream) // 3):
        coefficient = int.from_bytes(stream[index * 3:index * 3 + 3], "little")
        coefficient &= 0x3FFFFF if ctest else 0x7FFFFF
        if coefficient < Q:
            accepted.append(coefficient)
            if len(accepted) == 256:
                return accepted, rejected, (index + 1) * 3
        else:
            rejected.append(index)
    raise AssertionError("Fixed fixture stream exhausted")


def fixtures():
    selected = []
    # Both sides of three complete SHAKE blocks and the last required candidate.
    for wanted in (55, 56, 111, 112, 223, 224, 255):
        for counter in range(100_000):
            rho = counter.to_bytes(4, "little") + bytes(28)
            coefficients, rejected, consumed = sample(rho, 0, 0)
            if wanted in rejected:
                selected.append((f"reject-at-{wanted}", rho, 0, 0, False))
                break
        else:
            raise AssertionError(f"No deterministic fixture for {wanted}")
    selected += [
        ("zero-rho", bytes(32), 0, 0, False),
        ("ones-rho-last-cell", bytes([255]) * 32, 3, 3, False),
        ("nonce-order-a", bytes(range(32)), 1, 3, False),
        ("nonce-order-b", bytes(range(32)), 3, 1, False),
        ("ctest-zero", bytes(32), 0, 0, True),
        ("ctest-ones", bytes([255]) * 32, 3, 3, True),
    ]
    binary = bytearray()
    report = []
    for label, rho, column, row, ctest in selected:
        coefficients, rejected, consumed = sample(rho, column, row, ctest)
        encoded = struct.pack("<256i", *coefficients)
        binary.extend(rho + bytes([column, row, int(ctest)]) + encoded)
        report.append(dict(label=label, rho=rho.hex(), column=column, row=row,
                           ctest=ctest, rejectedCandidateIndices=rejected,
                           bytesConsumedByOriginalSampler=consumed,
                           expectedCoefficientsSha256=sha(encoded)))
    return bytes(binary), report


HASHING_TESTS = r'''

#[cfg(test)]
mod round4_independent {
    #[test]
    fn python_shake_rate_boundary_fixtures() {
        const STRIDE: usize = 32 + 3 + 256 * 4;
        let fixtures = include_bytes!("round4-shake-fixtures.bin");
        assert_eq!(fixtures.len(), 13 * STRIDE);
        for case in fixtures.chunks_exact(STRIDE) {
            let rhos: &[&[u8]] = &[&case[..32], &case[32..33], &case[33..34]];
            let actual = if case[34] == 0 {
                super::rej_ntt_poly::<false>(rhos)
            } else {
                super::rej_ntt_poly::<true>(rhos)
            };
            for (value, encoded) in actual.0.iter().zip(case[35..].chunks_exact(4)) {
                assert_eq!(*value, i32::from_le_bytes(encoded.try_into().unwrap()));
            }
        }
    }
}
'''

READER_TESTS = r'''

#[cfg(test)]
mod round4_independent {
    const VALUES: [i32; 9] = [i32::MIN, i32::MAX, -1, 0, 1, -8_380_417, 8_380_416, -17, 513];
    fn value(index: usize) -> i32 { VALUES[index % VALUES.len()] }

    #[test]
    fn signed_le_unaligned_matrix_and_next_vector() {
        // Nonzero unaligned offset; four matrix rows followed by another vector.
        let mut encoded = [0xA5; 3 + 5 * 4096 + 7];
        for (index, bytes) in encoded[3..3 + 5 * 4096].chunks_exact_mut(4).enumerate() {
            bytes.copy_from_slice(&value(index).to_le_bytes());
        }
        let before = encoded;
        let mut reader = super::Reader { bytes: &encoded, offset: 3 };
        let matrix = reader.matrix();
        assert_eq!(reader.offset, 3 + 4 * 4096);
        for (index, coefficient) in matrix.iter().flatten().flat_map(|poly| poly.0.iter()).enumerate() {
            assert_eq!(*coefficient, value(index));
        }
        let vector = reader.vector();
        for (index, coefficient) in vector.iter().flat_map(|poly| poly.0.iter()).enumerate() {
            assert_eq!(*coefficient, value(4096 + index));
        }
        assert_eq!(reader.offset, 3 + 5 * 4096);
        assert_eq!(reader.bytes::<7>(), [0xA5; 7]);
        assert_eq!(reader.offset, encoded.len());
        assert_eq!(encoded, before);
    }

    #[test]
    #[should_panic]
    fn short_vector_is_bounds_checked() {
        let encoded = [0u8; 4095];
        let mut reader = super::Reader { bytes: &encoded, offset: 0 };
        drop(reader.vector());
    }
}
'''


def main():
    OUT.mkdir(exist_ok=True)
    if CRATE.exists():
        shutil.rmtree(CRATE)
    CRATE.mkdir()
    shutil.copytree(VENDOR / "src", CRATE / "src")
    for name in ("Cargo.toml", "README.md"):
        shutil.copyfile(VENDOR / name, CRATE / name)
    # Use the production lock, avoiding transitive crypto-version drift from
    # standalone vendor resolution. Existing source unit tests require only
    # rand/rand_chacha; unrelated integration/benchmark dev deps are unnecessary.
    shutil.copyfile(WORKSPACE_LOCK, CRATE / "Cargo.lock")
    manifest = (CRATE / "Cargo.toml").read_text()
    manifest = re.sub(r"^\[dev-dependencies\.(?:criterion|hex|regex|serde_json)\].*?(?=^\[|\Z)",
                      "", manifest, flags=re.M | re.S)
    (CRATE / "Cargo.toml").write_text(manifest + "\n[workspace]\n")
    source_pins = {str(path.relative_to(VENDOR)): sha(path.read_bytes())
                   for path in sorted(VENDOR.joinpath("src").rglob("*.rs"))}
    for filename, appendix in (("hashing.rs", HASHING_TESTS),
                              ("motoko_prepared.rs", READER_TESTS)):
        original = (VENDOR / "src" / filename).read_bytes()
        (CRATE / "src" / filename).write_bytes(original + appendix.encode())
        assert (CRATE / "src" / filename).read_bytes().startswith(original)
    binary, cases = fixtures()
    (CRATE / "src/round4-shake-fixtures.bin").write_bytes(binary)
    report = dict(schema=1, sourceFilesSha256=source_pins,
                  productionCargoLockSha256=sha(WORKSPACE_LOCK.read_bytes()),
                  originalVendorCargoTomlSha256=sha((VENDOR / "Cargo.toml").read_bytes()),
                  harnessCargoTomlSha256=sha((CRATE / "Cargo.toml").read_bytes()),
                  harnessScriptSha256=sha(Path(__file__).read_bytes()),
                  hashingTestAppendixSha256=sha(HASHING_TESTS.encode()),
                  readerTestAppendixSha256=sha(READER_TESTS.encode()),
                  fixtureBinarySha256=sha(binary), fixtureCount=len(cases), cases=cases,
                  oracle="Python hashlib SHAKE128, explicit 23-bit little-endian candidates and FIPS Q; no Rust sampler/helper reuse",
                  productionFilesEdited=False)
    (AUDIT / "harness-provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(dict(crate=str(CRATE), fixtureCount=len(cases),
                          fixtureBinarySha256=sha(binary))))


if __name__ == "__main__":
    main()
