#!/usr/bin/env python3
"""Check interpreter Ed25519 against RFC 8032 and Node/OpenSSL independently.

Needs Node, OCaml matching Num, and Num's native archive. No Motoko SDK build,
Cargo, canister, network, or installed plugin is required. All compilation stays
in a temporary directory. Example in a Motoko Nix shell:

  python3 benchmarks/crypto/round3/ed25519/reference-validation/run.py

Explicit tool paths can be passed with --ocamlopt, --num-dir, and --node.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


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
    if not (num_dir / "nums.cmxa").is_file():
        parser.error("--num-dir must contain nums.cmxa")
    reference = ROOT / "plugins/ed25519/compiler/reference.ml"
    with tempfile.TemporaryDirectory(prefix="ed25519-reference-") as folder:
        work = Path(folder)
        shutil.copyfile(reference, work / "reference.ml")
        shutil.copyfile(HERE / "check.ml", work / "check.ml")
        (work / "mo_values.ml").write_text(
            "module Value = struct\n"
            "  type value = Blob of string | Bool of bool | Tup of value list "
            "| Variant of string * value\nend\n")
        run([args.node, HERE / "vectors.mjs", work])
        run([args.ocamlopt, "-I", num_dir,
             "-w", "+a-4-23-27-30-32-42-44-45-58-60-69-70", "-warn-error", "+a",
             "nums.cmxa", "mo_values.ml", "reference.ml", "check.ml", "-o", "check"], work)
        checks = json.loads(run([work / "check"], work))
        node = json.loads(run([args.node, "-p", "JSON.stringify({node:process.versions.node,openssl:process.versions.openssl})"]))
        result = {
            "status": "passed",
            "referenceSha256": sha256(reference),
            "harnessSha256": {name: sha256(HERE / name)
                               for name in ["run.py", "vectors.mjs", "check.ml"]},
            "generatedVectorsSha256": sha256(work / "vectors.txt"),
            "generatedShaVectorsSha256": sha256(work / "sha.txt"),
            "versions": {"ocaml": run([args.ocamlopt, "-version"]), **node},
            "checks": checks,
        }
    output = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
