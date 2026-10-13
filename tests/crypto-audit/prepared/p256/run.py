#!/usr/bin/env python3
"""Run one coordinated phase of the independent prepared-P256 audit.

Run native/Motoko phases inside the selected compiler's Nix environment.
This runner never rebuilds the plugin or changes a global toolchain.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, log, cwd, env):
    started = time.monotonic()
    command = [str(item) for item in command]
    with log.open("w") as out:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT)
    row = {"command": command, "cwd": str(cwd), "exit": result.returncode,
           "seconds": time.monotonic() - started, "log": log.name, "log_sha256": sha(log)}
    print(json.dumps(row), flush=True)
    if result.returncode:
        print(log.read_text()[-10000:], flush=True)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--phase", choices=["native", "motoko", "ash", "inspect"], required=True)
    parser.add_argument("--ash-source", type=Path)
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    env = os.environ.copy()
    env["PATH"] = str(motoko / "bin") + ":" + env["PATH"]
    env["MOTOKO_ROOT"] = str(motoko)
    env["CARGO_BUILD_JOBS"] = "2"
    build_path = ROOT / "dist/p256/build.json"
    build = json.loads(build_path.read_text())
    for name, digest in build["source_sha256"].items():
        assert sha(ROOT / name) == digest, "stale source: " + name
    assert sha(motoko / "src/moc") == build["moc_sha256"], "wrong compiler binary"
    artifacts = {name: sha(ROOT / "dist/p256" / name) for name in ["runtime.wasm", "plugin.cmxs", "build.json"]}
    for name, digest in build["sha256"].items():
        assert artifacts[name] == digest, "stale artifact: " + name
    watched = dict(build["source_sha256"])
    watched["packages/fast/src/P256.mo"] = sha(ROOT / "packages/fast/src/P256.mo")
    report = {"schema": 1, "phase": args.phase, "compiler_revision": build["motoko_revision"],
              "compiler_sha256": build["moc_sha256"], "artifact_sha256": artifacts,
              "source_sha256": watched, "commands": []}

    def run(command, label, cwd=ROOT):
        row = execute(command, HERE / (label + ".log"), cwd, env)
        report["commands"].append(row)
        return row["exit"] == 0

    success = True
    if args.phase == "native":
        success = run(["python3", HERE / "generate.py"], "generate")
        if success:
            success = run(["python3", HERE / "render.py"], "render")
        for profile, flags in [("debug", []), ("release", ["--release"])]:
            if success:
                success = run(["cargo", "test", "--offline", "--manifest-path", HERE / "native/Cargo.toml",
                               "--lib", "--target-dir", HERE / "native/target", *flags], "native-" + profile)
    elif args.phase == "motoko":
        success = run(["test-runner", "-b", "-j", "1", HERE / "run"], "motoko", motoko)
        if success:
            paths = {kind: HERE / "run/_out" / ("independent." + kind)
                     for kind in ["run", "run-ir", "run-low", "wasm-run", "valid"]}
            assert all(path.is_file() for path in paths.values()), "missing execution engine"
            report["engines"] = {kind: sha(path) for kind, path in paths.items()}
    elif args.phase == "ash":
        assert args.ash_source is not None, "pass the isolated Ash source checkout"
        ash = args.ash_source.resolve()
        provenance_path = ash.parent / "ash-source-provenance.json"
        provenance = json.loads(provenance_path.read_text())
        assert Path(provenance["sdk_moc_override"]).resolve() == (motoko / "bin/moc").resolve()
        for name, pins in provenance["files"].items():
            assert sha(ash / name) == pins["copied_sha256"], "changed private Ash source: " + name
        report["ash_provenance_sha256"] = sha(provenance_path)
        report["ash_source_sha256"] = {name: pins["copied_sha256"] for name, pins in provenance["files"].items()}
        success = run(["bun", ash / "src/index.ts", "test", HERE / "Retained.ash.json", "--verbose"], "ash")
    else:
        analyzer = HERE / "stack.py"
        report["stack_analyzer_sha256"] = sha(analyzer)
        success = run(["python3", analyzer, ROOT / "dist/p256/runtime.wasm",
                       "--expect-sha256", artifacts["runtime.wasm"]], "stack")

    assert watched == {name: sha(ROOT / name) for name in watched}, "source changed during audit"
    assert artifacts == {name: sha(ROOT / "dist/p256" / name) for name in artifacts}, "artifact changed during audit"
    report["fixture_sha256"] = {
        str(path.relative_to(HERE)): sha(path) for path in sorted(HERE.rglob("*"))
        if path.is_file() and "target" not in path.parts and "_out" not in path.parts
        and (path.suffix in {".py", ".rs", ".mo", ".toml"} or path.name in {"vectors.json", "Retained.ash.json", "Cargo.lock"})
    }
    report["passed"] = success
    (HERE / ("execution-" + args.phase + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
