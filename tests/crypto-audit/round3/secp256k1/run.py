#!/usr/bin/env python3
"""Run this audit inside the matching compiler's Nix development environment."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin", type=Path, required=True)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    plugin, motoko, out = args.plugin.resolve(), args.motoko.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    stage = plugin.parent.parent
    build = json.loads((plugin / "build.json").read_text())
    sources = {f: h for f, h in build["source_sha256"].items() if f.startswith("plugins/secp256k1/")}
    artifacts = {f.name: sha(f) for f in plugin.iterdir() if f.is_file()}
    for f, h in sources.items():
        assert sha(stage / f) == h, f"stale source: {f}"
    for f, h in build["sha256"].items():
        assert artifacts[f] == h, f"stale artifact: {f}"
    assert sha(motoko / "src/moc") == build["moc_sha256"], "compiler differs from plugin build"
    report = {"scope": "Independent Secp256k1 Wasm64, source/IR/lowered interpreters, and direct field-backend differential audit",
              "sources_sha256": sources, "artifacts_sha256": artifacts, "moc_sha256": build["moc_sha256"], "runs": []}
    def run(command, name, cwd):
        logfile = out / name
        with logfile.open("w") as log:
            result = subprocess.run(list(map(str, command)), cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        report["runs"].append({"command": list(map(str, command)), "cwd": str(cwd), "exit": result.returncode,
                               "log": name, "sha256": sha(logfile)})
        print(f"{name}: exit {result.returncode}", flush=True)
        if result.returncode:
            print(logfile.read_text()[-8000:], flush=True)
        return result.returncode == 0
    generated = run([sys.executable, HERE / "generate.py", "--plugin", plugin, "--out", out], "generate.log", ROOT)
    outcomes = [generated]
    for mode in ["debug", "release"]:
        command = ["cargo", "test", "--offline", "--locked", "--manifest-path", HERE / "field-backends/Cargo.toml",
                   "--target-dir", out / "native-target"]
        if mode == "release": command.append("--release")
        command += ["--", "--nocapture"]
        outcomes.append(run(command, f"field-{mode}.log", ROOT))
    if generated:
        outcomes.append(run(["test-runner", "-b", "-j", "1", out / "run"], "motoko.log", motoko))
    report["generated"] = json.loads((out / "generated.json").read_text()) if generated else None
    report["engines"] = {}
    for fixture in sorted((out / "run").glob("*.mo")):
        engines = {suffix: out / "run/_out" / (fixture.stem + "." + suffix)
                   for suffix in ["run", "run-ir", "run-low", "wasm-run", "valid"]}
        report["engines"][fixture.name] = {suffix: sha(path) for suffix, path in engines.items() if path.is_file()}
        outcomes.append(all(path.is_file() for path in engines.values()))
    # Source/artifact identity is checked again after executing the suite.
    outcomes.append(all(sha(stage / f) == h for f, h in sources.items()))
    outcomes.append(all(sha(plugin / f) == h for f, h in artifacts.items()))
    report["audit_sources_sha256"] = {str(f.relative_to(HERE)): sha(f) for f in [
        HERE / "generate.py", HERE / "run.py", HERE / "field-backends/Cargo.toml",
        HERE / "field-backends/Cargo.lock", HERE / "field-backends/src/lib.rs"]}
    report["passed"] = all(outcomes)
    (out / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {out / 'evidence.json'}; passed={report['passed']}", flush=True)
    return 0 if report["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
