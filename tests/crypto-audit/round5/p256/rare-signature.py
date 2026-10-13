#!/usr/bin/env python3
"""Force a zero-s result through copied production signing implementations.

This is a synthetic nonce-policy regression, not an RFC6979 preimage witness.
Only nonce selection is replaced in temporary source copies. Arithmetic,
validation, result mapping, and the native pointer wrapper remain production
code. No public API, production source, or compiler interface is changed.

Run inside the compiler's Nix environment, with a build slot available:
  python3 tests/crypto-audit/round5/p256/rare-signature.py --output REPORT.json
The unfixed reference intentionally exits nonzero; REPORT.json still records
both the reference failure and native result. Use --reference-only when only
the shared OCaml implementation changed after native validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[4]
NONCE_BINDING = "let next_nonce = nonce_generator curve secret message in"
FORCED_BINDING = """let next_nonce () =
        incr audit_nonce_calls;
        Z.of_int (if !audit_nonce_calls = 1 then 1 else 2)
      in"""
NATIVE_NONCE = """let nonce_bytes = Zeroizing::new(rfc6979::generate_k::<
        <NistP256 as DigestPrimitive>::Digest,
        _,
    >(
        &secret_bytes,
        &NistP256::ORDER.encode_field_bytes(),
        &reduced.to_bytes(),
        &[],
    ));"""
NATIVE_FORCED_NONCE = """let nonce_bytes = Zeroizing::new({
        // Synthetic test seam: preserve all subsequent production code.
        let _ = &secret_bytes;
        let _digest: core::marker::PhantomData<
            <NistP256 as DigestPrimitive>::Digest,
        > = core::marker::PhantomData;
        Scalar::ONE.to_bytes()
    });"""

# The signing branch only needs real Value constructors. The prepared-handle
# plumbing below is inert: no prepared operation is invoked by these tests.
MO_VALUES = """module Value = struct
  type value = Tup of value list | Variant of string * value
    | Blob of string | Bool of bool
end
module Compute_plugin = struct
  module Prepared = struct
    let wrap () bytes = Value.Blob bytes
    let unwrap () = function
      | Value.Blob bytes -> bytes
      | _ -> invalid_arg "unused prepared-handle test stub"
  end
end
"""

OCAML_TESTS = r'''module C = P256_curve
module Z = C.Z
module V = Mo_values.Value
let failures = ref 0
let check label passed =
  Printf.printf "CHECK\t%s\t%s\n%!" label (if passed then "PASS" else "FAIL");
  if not passed then incr failures
let reset () = C.audit_nonce_calls := 0
let one = C.to_bytes 32 Z.one
let bad_key = String.make 32 '\000'
let p256_result secret digest =
  P256_reference.evaluate "sign_prehash" [] [] [V.Blob secret; V.Blob digest]
let p256_error label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let check_curve name curve low_s =
  (* k=d=1 gives r=Gx mod n and s=z+r. z=n-r therefore forces s=0. *)
  let r = C.modulo curve.C.gx curve.C.n in
  let hash = C.to_bytes 32 (Z.sub curve.C.n r) in
  reset ();
  let actual = C.ec_ecdsa_sign ~low_s curve one hash in
  Printf.printf "OBSERVED\t%s\tzero_s_result=%s\tnonce_calls=%d\n%!"
    name (if actual = None then "None" else "Some") !C.audit_nonce_calls;
  check (name ^ "/zero-s-rejected") (actual = None);
  check (name ^ "/exactly-one-nonce") (!C.audit_nonce_calls = 1);
  reset ();
  let control = C.ec_ecdsa_sign ~low_s curve one one in
  let expected_s = C.modulo (Z.add Z.one r) curve.C.n in
  let expected_s =
    if low_s && Z.compare expected_s (Z.shift_right curve.C.n 1) > 0
    then Z.sub curve.C.n expected_s else expected_s in
  check (name ^ "/nonzero-control")
    (control = Some (C.to_bytes 32 r ^ C.to_bytes 32 expected_s));
  check (name ^ "/nonzero-one-nonce") (!C.audit_nonce_calls = 1);
  reset ();
  check (name ^ "/invalid-secret-before-nonce")
    (C.ec_ecdsa_sign ~low_s curve bad_key one = None && !C.audit_nonce_calls = 0);
  reset ();
  check (name ^ "/invalid-digest-before-nonce")
    (C.ec_ecdsa_sign ~low_s curve one "" = None && !C.audit_nonce_calls = 0);
  hash
let () =
  let p256_hash = check_curve "p256" P256_reference.curve false in
  let secp_hash = check_curve "secp256k1" C.secp256k1 true in
  reset ();
  check "p256/real-wrapper-invalid-signature"
    (p256_result one p256_hash = p256_error "invalidSignature"
     && !C.audit_nonce_calls = 1);
  reset ();
  check "secp256k1/real-wrapper-invalid-signature"
    (C.ecdsa_sign one secp_hash = Error "invalidSignature"
     && !C.audit_nonce_calls = 1);
  reset ();
  check "p256/real-wrapper-secret-precedence"
    (p256_result bad_key "" = p256_error "invalidSecretKey"
     && !C.audit_nonce_calls = 0);
  reset ();
  check "secp256k1/real-wrapper-secret-precedence"
    (C.ecdsa_sign bad_key "" = Error "invalidSecretKey"
     && !C.audit_nonce_calls = 0);
  reset ();
  check "p256/real-wrapper-invalid-digest"
    (p256_result one "" = p256_error "invalidDigest"
     && !C.audit_nonce_calls = 0);
  reset ();
  check "secp256k1/real-wrapper-invalid-digest"
    (C.ecdsa_sign one "" = Error "invalidDigest"
     && !C.audit_nonce_calls = 0);
  exit (if !failures = 0 then 0 else 1)
'''

NATIVE_TESTS = r'''
#[cfg(test)]
mod rare_signature_tests {
    use super::*;

    #[test]
    fn forced_zero_s_uses_real_signer_and_error_wrapper() {
        let key = Scalar::ONE.to_bytes();
        let r = <Scalar as Reduce<U256>>::reduce_bytes(&AffinePoint::GENERATOR.x());
        let hash = (-r).to_bytes();
        let mut direct = [0xa5u8; 64];
        assert_eq!(sign_prehash(&key, &hash, &mut direct), Err(INVALID_SIGNATURE));
        // The helper does not write a partial signature on failure.
        assert_eq!(direct, [0xa5u8; 64]);
        let mut guarded = [0xa5u8; 66];
        assert_eq!(unsafe {
            p256_sign_prehash(key.as_ptr(), key.len(), hash.as_ptr(), hash.len(),
                             guarded.as_mut_ptr().add(1))
        }, INVALID_SIGNATURE);
        assert_eq!(&guarded[1..65], &[0u8; 64]);
        assert_eq!((guarded[0], guarded[65]), (0xa5, 0xa5));
    }

    #[test]
    fn nonzero_control_and_real_validation_remain_intact() {
        let key = Scalar::ONE.to_bytes();
        let r = <Scalar as Reduce<U256>>::reduce_bytes(&AffinePoint::GENERATOR.x());
        let mut out = [0u8; 64];
        assert_eq!(sign_prehash(&key, &key, &mut out), Ok(64));
        let expected = Signature::from_scalars(r, Scalar::ONE + r).unwrap();
        assert_eq!(&out[..], &expected.to_bytes()[..]);
        let public = AffinePoint::GENERATOR.to_encoded_point(true);
        assert_eq!(verify_prehash(public.as_bytes(), &key, &out), Ok(true));
        assert_eq!(sign_prehash(&[0; 32], &[], &mut out), Err(INVALID_SECRET_KEY));
        assert_eq!(sign_prehash(&key, &[], &mut out), Err(INVALID_DIGEST));
        let mut guarded = [0xa5u8; 66];
        assert_eq!(unsafe {
            p256_sign_prehash(key.as_ptr(), key.len(), core::ptr::null(), 0,
                             guarded.as_mut_ptr().add(1))
        }, INVALID_DIGEST);
        assert_eq!(&guarded[1..65], &[0u8; 64]);
        assert_eq!((guarded[0], guarded[65]), (0xa5, 0xa5));
    }
}
'''


def replace_once(source: str, old: str, new: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected exactly one production seam; found {count}: {old!r}")
    return source.replace(old, new, 1)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], cwd: Path, environment: dict[str, str] | None = None) -> dict:
    result = subprocess.run(command, cwd=cwd, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    return {"command": command, "returncode": result.returncode, "output": result.stdout}


def reference_test(temp: Path, root: Path) -> dict:
    directory = temp / "reference"
    directory.mkdir()
    source = (root / "plugins/p256/compiler/p256_curve.ml").read_text()
    transformed = "let audit_nonce_calls = ref 0\n" + replace_once(source, NONCE_BINDING, FORCED_BINDING)
    (directory / "p256_curve.ml").write_text(transformed)
    shutil.copyfile(root / "plugins/p256/compiler/reference.ml", directory / "p256_reference.ml")
    (directory / "mo_values.ml").write_text(MO_VALUES)
    (directory / "key_type.ml").write_text("let public_key = ()\n")
    (directory / "rare_signature.ml").write_text(OCAML_TESTS)
    command = ["ocamlfind", "ocamlopt", "-package", "num", "-linkpkg", "-w",
               "+a-4-23-27-30-32-42-44-45-58-60-69-70", "-warn-error", "+a",
               "mo_values.ml", "key_type.ml", "p256_curve.ml", "p256_reference.ml",
               "rare_signature.ml", "-o", "rare_signature"]
    compiled = run(command, directory)
    result = {"compile": compiled, "injected_source_sha256": digest(directory / "p256_curve.ml")}
    if compiled["returncode"] == 0:
        result["test"] = run([str(directory / "rare_signature")], directory)
    result["passed"] = compiled["returncode"] == 0 and result["test"]["returncode"] == 0
    return result


def native_test(temp: Path, root: Path, target_dir: Path | None) -> dict:
    directory = temp / "native"
    (directory / "src").mkdir(parents=True)
    runtime = root / "plugins/p256/runtime"
    source = (runtime / "src/lib.rs").read_text()
    marker = "#[cfg(test)]\nmod tests {"
    if source.count(marker) != 1:
        raise RuntimeError("Expected exactly one original native test module")
    production = source.split(marker, 1)[0]
    for module in ("projective_tests", "ffi_tests", "encoding_tests"):
        production = replace_once(production, f"#[cfg(test)]\nmod {module};", "")
    production = replace_once(production, NATIVE_NONCE, NATIVE_FORCED_NONCE)
    (directory / "src/lib.rs").write_text(production + NATIVE_TESTS)
    for module in ("prepared_table.rs", "secret_table.rs"):
        shutil.copyfile(runtime / "src" / module, directory / "src" / module)
    manifest = replace_once((runtime / "Cargo.toml").read_text(),
                            'path = "vendor/p256"',
                            "path = " + json.dumps(str(runtime / "vendor/p256")))
    (directory / "Cargo.toml").write_text(manifest + "\n[workspace]\n")
    # Retain the workspace's exact registry dependency versions in the isolated
    # package; Cargo may discard unrelated workspace packages from this copy.
    shutil.copyfile(root / "Cargo.lock", directory / "Cargo.lock")
    environment = os.environ.copy()
    if target_dir is not None:
        environment["CARGO_TARGET_DIR"] = str(target_dir.resolve())
    result = run(["cargo", "test", "--offline", "--lib", "--", "--nocapture"],
                 directory, environment)
    return {"test": result, "injected_source_sha256": digest(directory / "src/lib.rs"),
            "passed": result["returncode"] == 0}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference-only", action="store_true")
    parser.add_argument("--target-dir", type=Path)
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    sources = ["plugins/secp256k1/compiler/secp256k1_reference.ml",
               "plugins/p256/compiler/reference.ml", "plugins/p256/runtime/src/lib.rs",
               "plugins/p256/runtime/src/secret_table.rs", "plugins/p256/runtime/src/prepared_table.rs",
               "plugins/p256/runtime/Cargo.toml", "Cargo.lock"]
    report = {
        "kind": "synthetic forced-nonce zero-s signing policy regression",
        "scope": "Actual production arithmetic and wrappers with only nonce selection injected",
        "limitation": "Does not exhibit a real RFC6979 preimage or force a zero-r point",
        "source_sha256": {path: digest(root / path) for path in sources},
        "harness_sha256": digest(Path(__file__)),
    }
    with tempfile.TemporaryDirectory(prefix="p256-rare-signature-") as temporary:
        temp = Path(temporary)
        report["reference"] = reference_test(temp, root)
        if not arguments.reference_only:
            report["native"] = native_test(temp, root, arguments.target_dir)
    report["passed"] = all(report[part]["passed"] for part in ("reference", "native") if part in report)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2) + "\n")
    for part in ("reference", "native"):
        if part in report:
            print(f"{part}: {'PASS' if report[part]['passed'] else 'FAIL'}")
            for step in ("compile", "test"):
                if step in report[part]:
                    print(report[part][step]["output"], end="")
    print(f"Report: {arguments.output}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
