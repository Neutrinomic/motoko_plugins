#!/usr/bin/env python3
"""Run independent native and all-backend Motoko hash/codec audits.

Invoke from any directory with --motoko COMPILER and seven --plugin NAME=DIR
arguments (sha256, blake3, sha512, ripemd160, hmac-sha2, base58, bech32).
All generated artifacts live under the repository's ignored _build directory.
The Motoko fixture has predetermined success output: failures are never accepted.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
NAMES = {"sha256", "blake3", "sha512", "ripemd160", "hmac-sha2", "base58", "bech32"}
MODULES = {"SHA256", "BLAKE3", "SHA512", "RIPEMD160", "HMAC", "Base58", "Base58Check", "Bech32", "Segwit"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--plugin", action="append", default=[], metavar="NAME=DIR")
    parser.add_argument("--native-only", action="store_true")
    args = parser.parse_args()
    compiler = args.motoko.resolve()
    plugins = {}
    for spec in args.plugin:
        name, directory = spec.split("=", 1)
        plugins[name] = Path(directory).resolve()
    if not args.native_only and set(plugins) != NAMES:
        parser.error("--plugin must supply exactly: " + ", ".join(sorted(NAMES)))
    parent = ROOT / "_build/crypto-audit/hash-codec"
    parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
    report = {"stage": str(stage), "commands": [], "source_sha256": {}}

    def run(command, cwd=ROOT, env=None):
        index = len(report["commands"])
        log = stage / f"command-{index}.log"
        print("Running: " + " ".join(map(str, command)), flush=True)
        start = time.monotonic()
        with log.open("w") as out:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                                    stdout=out, stderr=subprocess.STDOUT)
        report["commands"].append({"argv": list(map(str, command)), "cwd": str(cwd),
                                   "exit_code": result.returncode,
                                   "seconds": round(time.monotonic() - start, 3),
                                   "log": str(log)})
        (stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(log.read_text(), end="", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)

    for name in sorted(NAMES):
        for directory in (ROOT / "plugins" / name / "runtime/src", ROOT / "plugins" / name / "compiler"):
            for path in sorted(directory.rglob("*")):
                if path.is_file():
                    report["source_sha256"][str(path.relative_to(ROOT))] = sha(path)
    for path in sorted(ROOT / "packages/fast/src" / (name + ".mo") for name in MODULES):
        report["source_sha256"][str(path.relative_to(ROOT))] = sha(path)
    for path in sorted(HERE.iterdir()):
        if path.is_file():
            report["source_sha256"][str(path.relative_to(ROOT))] = sha(path)
    report["compiler_sha256"] = {str(path): sha(path) for path in
                                 (compiler / "src/moc", compiler / "bin/moc") if path.is_file()}
    env = dict(os.environ, CARGO_TARGET_DIR=str(parent / "native-target"))
    run(["cargo", "test", "--locked", "--manifest-path", HERE / "Cargo.toml", "audit_", "--", "--nocapture"], env=env)
    if not args.native_only:
        module_dir = stage / "fast"
        shutil.copytree(ROOT / "packages/fast/src", module_dir)
        fixture_dir = stage / "tests/run"
        (fixture_dir / "ok").mkdir(parents=True)
        flags = ["--hide-warnings", "--sanity-checks", "--package", "fast", str(module_dir),
                 "--package", "core", str(ROOT / "packages/fast/.mops/core@2.5.0/src")]
        for name, directory in sorted(plugins.items()):
            if not directory.is_dir():
                parser.error("missing plugin directory: " + str(directory))
            flags += ["--plugin", str(directory)]
            for path in sorted(directory.rglob("*")):
                if path.is_file():
                    report["source_sha256"][str(path)] = sha(path)
        fixture = fixture_dir / "public-audit.mo"
        fixture.write_text("//MOC-FLAG " + " ".join(flags) + "\n" + (HERE / "public-audit.mo").read_text())
        for backend in ("run", "run-ir", "run-low", "wasm-run"):
            (fixture_dir / "ok" / f"public-audit.{backend}.ok").write_text("hash-codec independent audit ok\n")
        run(["nix", "develop", "--command", "test-runner", "-b", "--jobs", "1", fixture_dir], cwd=compiler)
        outputs = fixture_dir / "_out"
        failed = list(outputs.glob("*.ret"))
        if failed:
            raise SystemExit("failed backend exit status: " + ", ".join(map(str, failed)))
        for backend in ("run", "run-ir", "run-low", "wasm-run"):
            value = (outputs / f"public-audit.{backend}").read_text()
            if value != "hash-codec independent audit ok\n":
                raise SystemExit("missing explicit success marker in " + backend)
        report["public_backends"] = ["source", "IR", "lowered IR", "Wasm/Wasmtime with RTS sanity checks"]
    changed = []
    for name, digest in report["source_sha256"].items():
        path = Path(name) if Path(name).is_absolute() else ROOT / name
        if not path.is_file() or sha(path) != digest:
            changed.append(name)
    if changed:
        raise SystemExit("audited source changed during run; rerun after owners freeze: " + ", ".join(changed))
    report["status"] = "passed"
    (stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Audit passed; evidence: " + str(stage / "report.json"))


if __name__ == "__main__":
    main()
