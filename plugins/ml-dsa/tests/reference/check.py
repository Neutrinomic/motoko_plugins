#!/usr/bin/env python3
"""Check the portable interpreter using pinned external FIPS vectors and hashlib.

Only Python's standard library and ocamlopt are needed. All build products go
into a temporary directory. No compiler, Rust kernel, native crypto binding,
network access or subprocess is used by the reference implementation itself.
"""

import argparse
import hashlib
import json
import pathlib
import random
import shutil
import subprocess
import tempfile


def blob(hexadecimal):
    return f'(unhex "{hexadecimal}")'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ocamlopt", default="ocamlopt")
    parser.add_argument("--internal-vectors", type=pathlib.Path,
                        help="Optional fips204/tests/nist_vectors directory")
    args = parser.parse_args()
    plugin = pathlib.Path(__file__).resolve().parents[2]
    vectors = json.loads((plugin / "tests/vectors/acvp-ml-dsa-44.json").read_text())
    lines = [
        'let unhex s = String.init (String.length s / 2) (fun i ->',
        '  Char.chr (int_of_string ("0x" ^ String.sub s (2 * i) 2)))',
        'let require condition label = if not condition then failwith label',
        'let passed = ref 0',
        'let check condition label = require condition label; incr passed',
        'let () =',
    ]

    def check(expression, label):
        lines.append(f'check ({expression}) "{label}";')

    for test in vectors["keyGen"]:
        check(f'Mldsa.public_key {blob(test["seed"])} = {blob(test["pk"])}',
              f'ACVP keyGen {test["tcId"]}')
    for test in vectors["sigGen"]:
        seed, message, context, rnd, signature, public = (
            blob(test[key]) for key in ("seed", "message", "context", "rnd", "signature", "pk"))
        check(f'Mldsa.sign {seed} {message} {context} {rnd} = {signature}',
              f'ACVP sigGen {test["tcId"]}')
        check(f'Mldsa.verify {public} {message} {signature} {context}',
              f'ACVP sigGen verify {test["tcId"]}')
    for test in vectors["sigVer"]:
        public, message, signature, context = (
            blob(test[key]) for key in ("pk", "message", "signature", "context"))
        check(f'Mldsa.verify {public} {message} {signature} {context} = '
              f'{str(test["testPassed"]).lower()}', f'ACVP sigVer {test["tcId"]}')

    # Optional older internal-interface vectors additionally exercise the
    # expanded secret encoding and raw internal message domain.
    if args.internal_vectors:
        for path in sorted(args.internal_vectors.glob("*/internalProjection.json")):
            document = json.loads(path.read_text())
            for group in document["testGroups"]:
                if group["parameterSet"] != "ML-DSA-44":
                    continue
                for test in group["tests"]:
                    label = f'internal {document["mode"]} {test["tcId"]}'
                    if document["mode"] == "keyGen":
                        lines.append(f'let pk, sk = Mldsa.keygen {blob(test["seed"])} in')
                        check(f'pk = {blob(test["pk"])}', label + " pk")
                        check(f'Mldsa.encode_private sk = {blob(test["sk"])}', label + " sk")
                    elif document["mode"] == "sigGen":
                        secret = f'(Mldsa.decode_private {blob(test["sk"])})'
                        rnd = blob(test.get("rnd", "00" * 32))
                        check(f'Mldsa.sign_internal {secret} {blob(test["message"])} {rnd}'
                              f' = {blob(test["signature"])}', label)
                    elif document["mode"] == "sigVer":
                        public = blob(test.get("pk", group.get("pk")))
                        check(f'Mldsa.verify_internal {public} {blob(test["message"])} '
                              f'{blob(test["signature"])} = {str(test["testPassed"]).lower()}', label)

    rng = random.Random(20444)
    sizes = [0, 1, 135, 136, 137, 167, 168, 169, 271, 272, 273, 335, 336, 337, 1024, 4096]
    messages = [rng.randbytes(size) for size in sizes] + [b"abc"]
    for algorithm in (128, 256):
        digest = getattr(hashlib, f"shake_{algorithm}")
        for i, message in enumerate(messages):
            for size in sizes:
                check(f'Mldsa_shake.digest{algorithm} {blob(message.hex())} {size} = '
                      f'{blob(digest(message).hexdigest(size))}', f'SHAKE{algorithm} {i}/{size}')
            lines.append(f'let state = Mldsa_shake.create{algorithm} {blob(message.hex())} in')
            lines.append('let output = Buffer.create 1024 in')
            for size in (0, 1, 135, 32, 136, 168, 257, 295):
                lines.append(f'Buffer.add_string output (Mldsa_shake.squeeze state {size});')
            check(f'Buffer.contents output = {blob(digest(message).hexdigest(1024))}',
                  f'SHAKE{algorithm} streaming {i}')

    # Test the actual Motoko-result adapter without loading a compiler. Its
    # only dependency here is the small Value constructors it returns.
    lines.extend([
        'let module V = Mo_values.Value in',
        'let run name arguments = Reference.evaluate name [] [] arguments in',
        'let err label = Ok (V.Variant ("err", V.Variant (label, V.Tup []))) in',
        'let b bytes = V.Blob bytes in',
        'let seed = String.make 32 \'\\000\' in',
        'let context = String.make 256 \'x\' in',
        'let public = Mldsa.public_key seed in',
        'let signature = Mldsa.sign seed "message" "context" seed in',
    ])
    for expression, label in [
        ('run "public_key" [b ""] = err "invalidSecretKey"', 'public key seed length'),
        ('run "sign" [b ""; b ""; b context] = err "invalidSecretKey"', 'sign seed precedence'),
        ('run "sign" [b seed; b ""; b context] = err "invalidContext"', 'sign context length'),
        ('run "sign_randomized" [b ""; b ""; b context; b ""] = err "invalidSecretKey"', 'random sign seed precedence'),
        ('run "sign_randomized" [b seed; b ""; b context; b ""] = err "invalidContext"', 'random sign context precedence'),
        ('run "sign_randomized" [b seed; b ""; b ""; b ""] = err "invalidRandomness"', 'random sign randomness length'),
        ('run "verify" [b ""; b ""; b ""; b context] = err "invalidPublicKey"', 'verify public key precedence'),
        ('run "verify" [b public; b ""; b ""; b context] = err "invalidSignature"', 'verify signature precedence'),
        ('run "verify" [b public; b ""; b signature; b context] = err "invalidContext"', 'verify context length'),
        ('run "public_key" [b seed] = Ok (V.Variant ("ok", b public))', 'public key adapter'),
        ('run "sign" [b seed; b "message"; b "context"] = Ok (V.Variant ("ok", b signature))', 'sign adapter'),
        ('run "sign_randomized" [b seed; b "message"; b "context"; b seed] = Ok (V.Variant ("ok", b signature))', 'random sign adapter'),
        ('run "verify" [b public; b "message"; b signature; b "context"] = Ok (V.Variant ("ok", V.Bool true))', 'verify adapter'),
        ('run "verify" [b public; b "different"; b signature; b "context"] = Ok (V.Variant ("ok", V.Bool false))', 'wrong message'),
        ('run "verify" [b public; b "message"; b signature; b "other"] = Ok (V.Variant ("ok", V.Bool false))', 'wrong context'),
    ]:
        check(expression, label)
    lines.extend([
        'for i = 0 to String.length signature - 1 do',
        '  let mutated = Bytes.of_string signature in',
        '  Bytes.set mutated i (Char.chr (Char.code (Bytes.get mutated i) lxor 1));',
        '  check (run "verify" [b public; b "message"; b (Bytes.to_string mutated); b "context"]',
        '    = Ok (V.Variant ("ok", V.Bool false))) ("signature mutation " ^ string_of_int i)',
        'done;',
        'for i = 0 to 255 do',
        '  let ctx = String.make i \'x\' in',
        '  let sig_ = Mldsa.sign seed "" ctx seed in',
        '  check (Mldsa.verify public "" sig_ ctx) ("context length " ^ string_of_int i)',
        'done;',
        'Printf.printf "PASS: %d portable reference checks\\n" !passed',
    ])

    with tempfile.TemporaryDirectory(prefix="ml-dsa-reference-") as tmp:
        build = pathlib.Path(tmp)
        for name in ("mldsa_shake.mli", "mldsa_shake.ml", "mldsa.ml", "reference.ml"):
            shutil.copyfile(plugin / "compiler" / name, build / name)
        (build / "mo_values.ml").write_text(
            'module Value = struct\n'
            'type value = Blob of string | Bool of bool | Variant of string * value | Tup of value list\n'
            'end\n')
        (build / "check.ml").write_text("\n".join(lines) + "\n")
        subprocess.run([args.ocamlopt, "-w", "+a-4-70", "-warn-error", "+a-4-70", "-o", "check",
                        "mldsa_shake.mli", "mldsa_shake.ml", "mldsa.ml", "mo_values.ml",
                        "reference.ml", "check.ml"], cwd=build, check=True)
        subprocess.run([str(build / "check")], cwd=build, check=True)


if __name__ == "__main__":
    main()
