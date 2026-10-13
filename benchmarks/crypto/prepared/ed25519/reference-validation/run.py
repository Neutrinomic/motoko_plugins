#!/usr/bin/env python3
"""Portable prepared Ed25519 semantics against existing independent fixtures.

Uses a tiny Value/Prepared host stub, so this checks cryptographic semantics,
not the SDK's nominal type enforcement. It runs the existing direct-reference
checks unchanged, then prepared signing/verification over RFC/OpenSSL vectors
and the independent adversarial corpus including mixed-order keys. Needs Node,
OCaml and Num; all generated sources and compilation stay in a temporary folder.
"""
import argparse
import hashlib
import subprocess
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
DIRECT = ROOT / "benchmarks/crypto/round3/ed25519/reference-validation"
# This deliberately stubs only the host value plumbing. Nominal constructor
# ownership and type rejection belong to the real SDK integration tests.
VALUE_STUB = """module Value = struct
  type value = Blob of string | Bool of bool | Tup of value list | Variant of string * value
end
module Compute_plugin = struct
  module Prepared = struct
    type t = unit
    let wrap () bytes = Value.Blob bytes
    let unwrap () = function
      | Value.Blob bytes -> bytes
      | _ -> invalid_arg "expected prepared Blob"
  end
end
"""


def run(argv, cwd=None):
    return subprocess.run([str(x) for x in argv], cwd=cwd, check=True,
                          text=True, capture_output=True).stdout.strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ocamlopt", default=shutil.which("ocamlopt"))
    parser.add_argument("--num-dir", type=Path)
    parser.add_argument("--node", default=shutil.which("node"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.ocamlopt or not args.node:
        parser.error("OCaml and Node must be on PATH or supplied explicitly")
    num_dir = args.num_dir
    if num_dir is None:
        findlib = shutil.which("ocamlfind")
        if not findlib:
            parser.error("supply --num-dir or install ocamlfind with num")
        num_dir = Path(run([findlib, "query", "num"]))
    reference = ROOT / "plugins/ed25519/compiler/reference.ml"
    audit = ROOT / "tests/crypto-audit/round3/ed25519/vectors/cases.json"
    rfc = ROOT / "benchmarks/crypto/round3/ed25519/fixtures/rfc8032.json"
    with tempfile.TemporaryDirectory(prefix="ed25519-prepared-reference-") as folder:
        work = Path(folder)
        shutil.copyfile(reference, work / "reference.ml")
        shutil.copyfile(DIRECT / "check.ml", work / "direct_check.ml")
        shutil.copyfile(HERE / "check.ml", work / "prepared_check.ml")
        (work / "mo_values.ml").write_text(VALUE_STUB)
        run([args.node, DIRECT / "vectors.mjs", work])
        vectors = (work / "vectors.txt").read_text().splitlines()
        vectors += ["|".join(case[field] for field in ("seed", "publicKey", "message", "signature"))
                    for case in json.loads(rfc.read_text())["vectors"]]
        (work / "prepared-vectors.txt").write_text("\n".join(dict.fromkeys(vectors)) + "\n")
        cases = json.loads(audit.read_text())["cases"]
        (work / "adversarial.txt").write_text("\n".join(
            "|".join(case[field] for field in ("name", "publicKey", "message", "signature", "expected"))
            for case in cases) + "\n")
        run([args.ocamlopt, "-I", num_dir,
                  "-w", "+a-4-23-27-30-32-42-44-45-58-60-69-70", "-warn-error", "+a",
                  "nums.cmxa", "mo_values.ml", "reference.ml", "direct_check.ml", "prepared_check.ml", "-o", "check"], work)
        results = [json.loads(line) for line in run([work / "check"], work).splitlines()]
        node = json.loads(run([args.node, "-p", "JSON.stringify({node:process.versions.node,openssl:process.versions.openssl})"]))
        result = {
            "status": "passed",
            "scope": "Portable reference cryptographic semantics; SDK nominal enforcement tested separately",
            "referenceSha256": sha256(reference),
            "harnessSha256": {str(path.relative_to(ROOT)): sha256(path)
                              for path in (HERE / "run.py", HERE / "check.ml", DIRECT / "check.ml", DIRECT / "vectors.mjs")},
            "inputSha256": {str(path.relative_to(ROOT)): sha256(path) for path in (audit, rfc)},
            "versions": {"ocaml": run([args.ocamlopt, "-version"]), **node},
            "directChecks": results[0],
            "preparedChecks": results[1],
        }
    output = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
