#!/usr/bin/env python3
"""Package integration checks; run after scripts/build.sh in the Motoko Nix shell."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--motoko", type=Path, default=os.environ.get("MOTOKO_ROOT"),
                    help="Motoko compiler checkout (or set MOTOKO_ROOT)")
args = parser.parse_args()
if args.motoko is None:
    parser.error("--motoko PATH or MOTOKO_ROOT is required")
MOTOKO_ROOT = args.motoko.resolve()
PACKAGES = ROOT / "dist"
MOC = MOTOKO_ROOT / "bin/moc"


def compile_program(source, output, packages=(), error=None, arguments=()):
    command = [str(MOC), "-wasi-system-api"]
    for package in packages:
        command.extend(["--plugin", str(package)])
    command.extend(str(argument) for argument in arguments)
    command.extend([str(source), "-o", str(output)])
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if error is None:
        assert result.returncode == 0, result.stderr
        return output.read_bytes()
    assert result.returncode != 0, "invalid package unexpectedly compiled"
    assert error in result.stderr, result.stderr
    assert "OOPS" not in result.stderr, result.stderr


def plugin_load_error(source, components):
    command = [str(MOC)]
    for component in components:
        command.extend(["--plugin", str(component)])
    command.extend(["--check", str(source)])
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 1, (result.returncode, result.stderr)
    assert "OOPS" not in result.stderr, result.stderr
    return result.stderr


def unsupported_plugin(source, component, reason):
    diagnostic = plugin_load_error(source, [component])
    assert "unsupported compute plugin" in diagnostic, diagnostic
    assert reason in diagnostic, diagnostic
    assert "Use a plugin built for this compiler" in diagnostic, diagnostic
    assert "(moc " in diagnostic and "; OCaml " in diagnostic, diagnostic
    assert "host platform" in diagnostic, diagnostic
    return diagnostic


def check_compatibility(work, source):
    # A type-only dependency records the wrong Codegen interface checksum
    # without requiring any fake native symbol or executing an initializer.
    interface = work / "interface-mismatch"
    interface.mkdir()
    (interface / "codegen.mli").write_text(
        "type compiler_build = Incompatible_interface\n"
    )
    (interface / "interface_mismatch.ml").write_text(
        "let identity (value : Codegen.compiler_build) = value\n"
    )
    subprocess.run(["ocamlopt", "-c", "codegen.mli"], cwd=interface, check=True)
    subprocess.run(["ocamlopt", "-shared", "-o", "plugin.cmxs",
                    "interface_mismatch.ml"], cwd=interface, check=True)
    unsupported_plugin(source, interface / "plugin.cmxs",
                       "interface mismatch on Codegen")

    # Build against the real compiler interfaces, but request the next SDK ABI.
    # No binding or Wasm runtime is needed: registration must reject it first.
    abi = work / "abi-mismatch"
    abi.mkdir()
    (abi / "abi_mismatch.ml").write_text(
        "module P = Codegen.Plugin_codegen\n"
        "let () = P.register P.{\n"
        "  abi = P.abi_version + 1; name = \"unsupported_abi\";\n"
        "  runtime = Some \"runtime.wasm\"; imports = []; bindings = [];\n"
        "}\n"
    )
    includes = []
    for kind in ["byte", "native"]:
        for directory in sorted((MOTOKO_ROOT / "src/_build/default").glob(
                f"*/.*.objs/{kind}")):
            includes.extend(["-I", str(directory)])
    subprocess.run(["ocamlopt", *includes, "-shared", "-o", "plugin.cmxs",
                    "abi_mismatch.ml"], cwd=abi, check=True)
    diagnostic = unsupported_plugin(source, abi, "requires compute plugin ABI")
    versions = re.search(r"requires compute plugin ABI (\d+), "
                         r"but this compiler supports ABI (\d+)", diagnostic)
    assert versions is not None, diagnostic
    requested, supported = map(int, versions.groups())
    assert requested == supported + 1, diagnostic

    # A plugin's own initialization bug or duplicate registration is not a
    # toolchain mismatch and must retain its actual error classification.
    initializer = work / "initializer-failure"
    initializer.mkdir()
    failure = "compatibility fixture initializer failure"
    (initializer / "initializer_failure.ml").write_text(
        f'let () = failwith "{failure}"\n'
    )
    subprocess.run(["ocamlopt", "-shared", "-o", "plugin.cmxs",
                    "initializer_failure.ml"], cwd=initializer, check=True)
    diagnostic = plugin_load_error(source, [initializer])
    assert failure in diagnostic, diagnostic
    assert "unsupported compute plugin" not in diagnostic, diagnostic
    diagnostic = plugin_load_error(source, [PACKAGES / "sha256"] * 2)
    assert "duplicate compute plugin: sha256" in diagnostic, diagnostic
    assert "unsupported compute plugin" not in diagnostic, diagnostic


def check_collections(work, manifests):
    # Compiler-only packages must work using their native component alone.
    # Copying just that component prevents a stray local runtime from masking
    # an accidental runtime dependency in a generated collection operation.
    packages = []
    for manifest in manifests:
        package = PACKAGES / manifest.parent.name
        if json.loads(manifest.read_text()).get("runtime_crate") is None:
            assert not (package / "runtime.wasm").exists(), package
            copied = work / ("native-" + manifest.parent.name)
            copied.mkdir()
            shutil.copyfile(package / "plugin.cmxs", copied / "plugin.cmxs")
            package = copied
        packages.append(package)

    core = os.environ.get("MOTOKO_CORE")
    assert core, "MOTOKO_CORE must point to Core sources; use the Motoko Nix shell"
    arguments = ["--package", "fast", ROOT / "packages/fast/src",
                 "--package", "core", core]
    source = ROOT / "tests/integration/run/collections.mo"
    expected = compile_program(source, work / "collections.wasm",
                               [PACKAGES / path.parent.name for path in manifests],
                               arguments=arguments)
    actual = compile_program(source, work / "collections-native.wasm", packages,
                             arguments=arguments)
    assert expected == actual, "compiler-only package copy changed emitted Wasm"
    actual = compile_program(source, work / "collections-files.wasm",
                             [path / "plugin.cmxs" for path in packages],
                             arguments=arguments)
    assert expected == actual, "directory and .cmxs loading changed emitted Wasm"


def check_crypto_packages(work):
    # Each public primitive must load independently, and its interpreter must
    # remain usable without the canister's Wasm kernel being present.
    probes = {
        "blake3": ("BLAKE3", 'assert Crypto.digest("").size() == 32;'),
        "sha512": ("SHA512", 'assert Crypto.digest("").size() == 64;'),
        "ripemd160": ("RIPEMD160", 'assert Crypto.digest("").size() == 20;'),
        "hmac-sha2": ("HMAC", 'assert Crypto.sha256("key", "").size() == 32;'),
        "secp256k1": ("Secp256k1", 'assert Crypto.derivePublicKey("") == #err(#invalidSecretKey);'),
        "p256": ("P256", 'assert Crypto.derivePublicKey("") == #err(#invalidSecretKey);'),
        "base58": ("Base58", 'assert Crypto.encode("\\00") == "1";'),
        "bech32": ("Bech32", 'assert Crypto.encode("a", "", #bech32) == #ok("a12uel5l");'),
        "bls12-381": ("BLS12381", 'assert Crypto.validateG1(Crypto.g1Generator) == #ok(Crypto.g1Generator);'),
    }
    arguments = ["--package", "fast", ROOT / "packages/fast/src"]
    for name, (module, expression) in probes.items():
        source = work / f"{name}-public.mo"
        source.write_text(f'import Crypto "mo:fast/{module}";\n{expression}\n')
        package = work / f"{name}-standalone"
        package.mkdir()
        shutil.copyfile(PACKAGES / name / "plugin.cmxs", package / "plugin.cmxs")
        for mode in [["--check"], ["-r"], ["-r", "-iR"]]:
            result = subprocess.run(
                [str(MOC), "--plugin", str(package), *map(str, arguments),
                 *mode, str(source)], cwd=ROOT, capture_output=True, text=True,
            )
            assert result.returncode == 0, (name, mode, result.stderr)
        compile_program(source, work / f"{name}-missing.wasm", [package],
                        arguments=arguments, error="compute plugin")
        shutil.copyfile(PACKAGES / name / "runtime.wasm", package / "runtime.wasm")
        directory = compile_program(source, work / f"{name}-directory.wasm", [package],
                                    arguments=arguments)
        component = compile_program(source, work / f"{name}-component.wasm",
                                    [package / "plugin.cmxs"], arguments=arguments)
        assert directory == component, f"{name}: directory and component loading differ"


def main():
    with tempfile.TemporaryDirectory(prefix="motoko-compute-packages-") as work:
        work = Path(work)
        empty = work / "unused.mo"
        empty.write_text("assert true;\n")
        check_compatibility(work, empty)
        used = work / "used.mo"
        used.write_text('import Prim "mo:⛔"; ignore Prim.sha256("abc");\n')
        plain = compile_program(empty, work / "plain.wasm")
        manifests = sorted((ROOT / "plugins").glob("*/plugin.json"))
        packages = [PACKAGES / manifest.parent.name for manifest in manifests]
        loaded = compile_program(empty, work / "loaded.wasm", packages)
        assert plain == loaded, "unused plugins changed the output module"
        check_collections(work, manifests)
        check_crypto_packages(work)

        # Typechecking and interpretation can load a compiler component alone.
        # An unused runtime is never opened; a used missing runtime is an error.
        package = work / "sha256"
        package.mkdir()
        shutil.copyfile(PACKAGES / "sha256/plugin.cmxs", package / "plugin.cmxs")
        assert compile_program(empty, work / "missing-unused.wasm", [package]) == plain
        compile_program(used, work / "missing.wasm", [package],
                        error="compute plugin sha256:")
        for mode in [["--check"], ["-r"], ["-r", "-iR"]]:
            result = subprocess.run([str(MOC), "--plugin", str(package), *mode,
                                     str(used)], cwd=ROOT, capture_output=True,
                                    text=True)
            assert result.returncode == 0, result.stderr

        # Loading a .cmxs path and a directory have the same runtime location.
        shutil.copyfile(PACKAGES / "sha256/runtime.wasm", package / "runtime.wasm")
        expected = compile_program(used, work / "directory.wasm", [package])
        actual = compile_program(used, work / "file.wasm", [package / "plugin.cmxs"])
        assert expected == actual

        # Decode and unresolved-export failures must be normal CLI diagnostics.
        (package / "runtime.wasm").write_bytes(b"not a Wasm library")
        compile_program(used, work / "malformed.wasm", [package],
                        error="invalid runtime Wasm")

        # The dylink.0 section contains four memory-info fields, but its
        # subsection claims only three bytes. This must not raise an assertion.
        (package / "runtime.wasm").write_bytes(
            b"\x00asm\x01\x00\x00\x00\x00\x0f\x08dylink.0"
            b"\x01\x03\x00\x00\x00\x00"
        )
        compile_program(used, work / "malformed-dylink.wasm", [package],
                        error="invalid runtime Wasm")

        shutil.copyfile(PACKAGES / "candidx/runtime.wasm", package / "runtime.wasm")
        compile_program(used, work / "wrong-library.wasm", [package],
                        error="unresolved compute plugin import")

    print("compute plugin packaging checks passed")


if __name__ == "__main__":
    main()
