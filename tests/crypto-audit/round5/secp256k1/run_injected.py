#!/usr/bin/env python3
"""Run rare BIP340 branches by replacing only tagged hash outputs in a disposable copy.

No injected code is added to shipped source. The signer, parsers, curve operations,
FFI and debug self-check remain the selected production source. This is a forced
internal-branch regression, not a natural SHA256 vector or end-to-end hash test.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REFERENCE_SHA256 = "4b1d4ad9e60820df4a6d239733d52b014bc03e4c47afd757a2fe4d3b586d892c"
HASH_ORIGINAL = '''fn tagged_hash(tag: &[u8]) -> Sha256 {
    let tag_hash = Sha256::digest(tag);
    let mut digest = Sha256::new();
    digest.update(tag_hash);
    digest.update(tag_hash);
    digest
}'''
HASH_INJECTED = '''extern crate std;
std::thread_local! {
    static AUDIT_HASHES: core::cell::Cell<([u8; 32], [u8; 32])> = const {
        core::cell::Cell::new(([0; 32], [0; 32]))
    };
}
/// Disposable audit-copy hook; absent from production source.
pub fn audit_force_hashes(nonce: [u8; 32], challenge: [u8; 32]) {
    AUDIT_HASHES.with(|cell| cell.set((nonce, challenge)));
}
/// Disposable audit-copy hook; absent from production source.
pub fn audit_challenge() -> [u8; 32] {
    AUDIT_HASHES.with(|cell| cell.get().1)
}
struct AuditHash { tag: u8, digest: Sha256 }
impl AuditHash {
    fn chain_update(mut self, bytes: impl AsRef<[u8]>) -> Self {
        self.digest.update(bytes); self
    }
    fn finalize(self) -> crate::FieldBytes {
        match self.tag {
            1 => AUDIT_HASHES.with(|cell| cell.get().0).into(),
            2 => audit_challenge().into(),
            _ => self.digest.finalize(),
        }
    }
}
fn tagged_hash(tag: &[u8]) -> AuditHash {
    let tag_hash = Sha256::digest(tag);
    let mut digest = Sha256::new();
    digest.update(tag_hash);
    digest.update(tag_hash);
    AuditHash { tag: if tag == NONCE_TAG { 1 } else if tag == CHALLENGE_TAG { 2 } else { 0 }, digest }
}'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--expect-failure", action="store_true")
    args = parser.parse_args()
    source, out = args.source.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    assert sha(args.reference) == REFERENCE_SHA256
    spec = importlib.util.spec_from_file_location("bip340_reference", args.reference)
    reference = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(reference)
    # Bind the independent reference to the unmodified official vectors first.
    for row in csv.DictReader((ROOT / "plugins/secp256k1/tests/vectors/bip340.csv").open()):
        if row["secret key"]:
            assert reference.schnorr_sign(bytes.fromhex(row["message"]), bytes.fromhex(row["secret key"]), bytes.fromhex(row["aux_rand"])).hex() == row["signature"].lower()
    original_hash = reference.tagged_hash
    vectors = []
    for nonce in [1, reference.n - 1, reference.n + 1, 2**256 - 1]:
        reference.tagged_hash = lambda tag, msg, nonce=nonce: nonce.to_bytes(32, "big") if tag == "BIP0340/nonce" else bytes(32) if tag == "BIP0340/challenge" else original_hash(tag, msg)
        signature = reference.schnorr_sign(b"forced nonce", (1).to_bytes(32, "big"), bytes(32))
        vectors.append(f"{nonce:064x}\t{signature.hex()}")
    forced = out / "forced.tsv"
    forced.write_text("\n".join(vectors) + "\n")
    stage = out / "source"
    assert not stage.exists(), "Use a fresh --out directory to preserve previous evidence"
    runtime_relative = Path("plugins/secp256k1/runtime")
    shutil.copytree(source / runtime_relative, stage / runtime_relative)
    harness_relative = Path("tests/crypto-audit/round5/secp256k1/native")
    shutil.copytree(HERE / "native", stage / harness_relative)
    # Runtime's existing cfg(test) vectors are compile-time includes even when filtered out.
    shutil.copytree(source / "plugins/secp256k1/tests", stage / "plugins/secp256k1/tests")
    schnorr = stage / runtime_relative / "vendor/k256/src/schnorr.rs"
    text = schnorr.read_text()
    assert text.count(HASH_ORIGINAL) == 1
    schnorr.write_text(text.replace(HASH_ORIGINAL, HASH_INJECTED))
    runtime = stage / runtime_relative / "src/lib.rs"
    text = runtime.read_text()
    needle = ".chain_update(&c[..32]).chain_update(public_x).chain_update(b).finalize();"
    assert text.count(needle) == 1
    runtime.write_text(text.replace(needle, needle + "\n            let _actual_hash = challenge;\n            let challenge = k256::schnorr::audit_challenge().into();"))
    report = {"method": __doc__, "reference_sha256": REFERENCE_SHA256,
              "source_sha256": {str(p.relative_to(source)): sha(p) for p in [source / runtime_relative / "src/lib.rs", source / runtime_relative / "vendor/k256/src/schnorr.rs", source / runtime_relative / "vendor/k256/src/schnorr/signing.rs"]},
              "injected_source_sha256": {str(p.relative_to(stage)): sha(p) for p in [schnorr, runtime]},
              "forced_vectors_sha256": sha(forced), "runs": []}
    import os
    env = dict(os.environ, SECP_AUDIT_FORCED_VECTORS=str(forced), CARGO_BUILD_JOBS="2")
    for mode in ["debug", "release"]:
        command = ["cargo", "test", "--offline", "--locked", "--jobs", "2", "--manifest-path", str(stage / harness_relative / "Cargo.toml"), "--target-dir", str(out / "target"), "--features", "injected-hashes"]
        if mode == "release": command.append("--release")
        command += ["audit5_rare_", "--", "--test-threads=1", "--nocapture"]
        log = out / (mode + ".log")
        with log.open("w") as f:
            result = subprocess.run(command, stdout=f, stderr=subprocess.STDOUT, env=env)
        text = log.read_text()
        expected = (result.returncode == 101 and "3 failed" in text and "test result: FAILED" in text) if args.expect_failure else (result.returncode == 0 and "3 passed" in text)
        report["runs"].append({"mode": mode, "command": command, "exit": result.returncode, "passed": expected, "log_sha256": sha(log)})
        print(f"{mode}: exit {result.returncode}, expected result={expected}", flush=True)
        if not expected: print(text[-6000:])
    report["passed"] = all(run["passed"] for run in report["runs"])
    (out / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
