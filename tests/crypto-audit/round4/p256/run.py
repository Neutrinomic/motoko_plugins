#!/usr/bin/env python3
"""Run a coordinated audit phase without rebuilding the compiler or plugin."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
MOC = "24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2"
RTS = {"MOC_RELEASE_RTS": ("mo-rts.wasm", "8456e47e527bbd584ee2d5d867b0c93f5596d2bcdaa87bba53c04281562c820f"),
       "MOC_DEBUG_RTS": ("mo-rts-debug.wasm", "f87c1f4a8b15e6e5949f618195cd303bd0d07fc85f1f73e9f0a244eacecb24c9")}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--phase", choices=["native", "motoko", "public", "ash", "stack"], required=True)
    args = parser.parse_args()
    sdk = args.motoko.resolve()
    build = json.loads((ROOT / "dist/p256/build.json").read_text())
    assert sha(sdk / "src/moc") == build["moc_sha256"] == MOC
    env = os.environ.copy()
    env.update({"MOTOKO_ROOT": str(sdk), "CARGO_BUILD_JOBS": "2", "RUST_TEST_THREADS": "2",
                "PATH": str(sdk / "bin") + ":" + env["PATH"]})
    for name, (file, digest) in RTS.items():
        path = sdk / "rts" / file
        assert sha(path) == digest
        env[name] = str(path)
    source = {**build["source_sha256"], "packages/fast/src/P256.mo": sha(ROOT / "packages/fast/src/P256.mo")}
    for name, digest in source.items():
        assert sha(ROOT / name) == digest, name
    artifacts = {name: sha(ROOT / "dist/p256" / name) for name in ["runtime.wasm", "plugin.cmxs", "build.json"]}
    for name, digest in build["sha256"].items():
        assert artifacts[name] == digest
    report = {"phase": args.phase, "compiler_sha256": MOC,
              "compiler_revision": build["motoko_revision"], "rts_sha256": RTS,
              "source_sha256": source, "artifact_sha256": artifacts, "commands": []}

    def run(command, label, cwd=ROOT):
        command = [str(x) for x in command]
        log = HERE / (label + ".log")
        start = time.monotonic()
        with log.open("w") as out:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT)
        row = {"command": command, "cwd": str(cwd), "exit": result.returncode,
               "seconds": time.monotonic() - start, "log": log.name, "log_sha256": sha(log)}
        report["commands"].append(row)
        print(json.dumps(row), flush=True)
        if result.returncode:
            print(log.read_text()[-8000:], flush=True)
        return result.returncode == 0

    success = True
    if args.phase == "native":
        for name in ["scalar_chain", "vectors", "render"]:
            if success:
                success = run(["python3", HERE / (name + ".py")], name)
        for name, flags in [("debug", []), ("release", ["--release"])]:
            if success:
                success = run(["cargo", "test", "--offline", "--manifest-path", HERE / "native/Cargo.toml",
                               "--lib", "--target-dir", HERE / "native/target", *flags], "native-" + name)
    elif args.phase == "motoko":
        success = run(["test-runner", "-b", "-j", "1", HERE / "run"], "motoko", sdk)
        if success:
            outputs = {kind: HERE / "run/_out" / ("independent." + kind)
                       for kind in ["run", "run-ir", "run-low", "wasm-run", "valid", "wasm"]}
            assert all(path.is_file() for path in outputs.values())
            report["engines_sha256"] = {kind: sha(path) for kind, path in outputs.items()}
    elif args.phase == "public":
        fixtures = [ROOT / "packages/fast/tests/run" / name for name in
                    ["crypto-p256.mo", "crypto-p256-projective-check.mo"]]
        report["public_fixture_sha256"] = {str(p.relative_to(ROOT)): sha(p) for p in fixtures}
        success = run(["test-runner", "-b", "-j", "1", *fixtures], "public", sdk)
        if success:
            outputs = [p.parent / "_out" / (p.stem + "." + kind) for p in fixtures
                       for kind in ["run", "run-ir", "run-low", "wasm-run", "valid", "wasm"]]
            assert all(p.is_file() for p in outputs)
            report["engines_sha256"] = {str(p.relative_to(ROOT)): sha(p) for p in outputs}
    elif args.phase == "ash":
        private = ROOT.parents[1] / "prepared-crypto/rsa/_build/prepared-validation"
        provenance = json.loads((private / "ash-source-provenance.json").read_text())
        for name, hashes in provenance["files"].items():
            assert sha(private / "ash-local" / name) == hashes["copied_sha256"], name
        report["ash_harness"] = provenance
        fixture = ROOT / "packages/fast/tests/ash/P256.mo"
        config = {"mo": {"fast": str(ROOT / "packages/fast/src"),
                          "core": str(ROOT / "packages/fast/.mops/core@2.5.0/src")},
                  "canisters": [{"name": "p256", "src": str(fixture),
                                  "mocArgs": ["--plugin", str(ROOT / "dist/p256"),
                                              "--sanity-checks", "--force-gc"]}]}
        config_path = HERE / "P256.ash.json"
        config_path.write_text(json.dumps(config, indent=2) + "\n")
        report["public_fixture_sha256"] = {str(fixture.relative_to(ROOT)): sha(fixture),
                                            str(config_path.relative_to(ROOT)): sha(config_path)}
        success = run(["bun", private / "ash-local/src/index.ts", "test", config_path, "--verbose"], "ash", HERE)
        report["generated_wasm_sha256"] = {str(p.relative_to(HERE)): sha(p) for p in HERE.rglob("*.wasm")
                                            if "target" not in p.parts and "_out" not in p.parts}
    else:
        analyzer = ROOT / "tests/crypto-audit/prepared/p256/stack.py"
        report["stack_analyzer_sha256"] = sha(analyzer)
        success = run(["python3", analyzer, ROOT / "dist/p256/runtime.wasm",
                       "--expect-sha256", artifacts["runtime.wasm"]], "stack")
    assert source == {name: sha(ROOT / name) for name in source}
    assert artifacts == {name: sha(ROOT / "dist/p256" / name) for name in artifacts}
    report["passed"] = success
    report["fixture_sha256"] = {str(path.relative_to(HERE)): sha(path) for path in HERE.rglob("*")
                                if path.is_file() and not any(part in {"target", "_out"} for part in path.parts)
                                and (path.suffix in {".py", ".rs", ".mo", ".toml"} or path.name in {"vectors.json", "Cargo.lock"})}
    (HERE / ("execution-" + args.phase + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
