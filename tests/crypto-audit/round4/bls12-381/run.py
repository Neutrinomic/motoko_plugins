#!/usr/bin/env python3
"""Execute retained independent BLS oracles against one frozen round4 artifact."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PREPARED = ROOT / "tests/crypto-audit/prepared/bls12-381"
ROUND3 = ROOT / "tests/crypto-audit/round3/bls12-381"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--motoko", type=Path, required=True)
parser.add_argument("--run", required=True)
parser.add_argument("--phase", choices=["all", "native", "public"], default="all")
args = parser.parse_args()
compiler = args.motoko.resolve()
dist = ROOT / "dist/bls12-381"
evidence = HERE / "evidence" / args.run
evidence.mkdir(parents=True, exist_ok=False)
scratch = ROOT / "_build/round4-bls-independent" / args.run
scratch.mkdir(parents=True, exist_ok=False)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
expected_toolchain = {
    "src/moc": "24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2",
    "rts/mo-rts.wasm": "8456e47e527bbd584ee2d5d867b0c93f5596d2bcdaa87bba53c04281562c820f",
    "rts/mo-rts-debug.wasm": "f87c1f4a8b15e6e5949f618195cd303bd0d07fc85f1f73e9f0a244eacecb24c9",
}
for name, expected in expected_toolchain.items():
    assert sha(compiler / name) == expected, "Unapproved compiler/RTS: " + name
manifest = json.loads((dist / "build.json").read_text())
assert manifest["moc_sha256"] == expected_toolchain["src/moc"]
selected_sources = {name: value for name, value in manifest["source_sha256"].items()
                    if name.startswith("plugins/bls12-381/")}
for name, expected in selected_sources.items():
    assert sha(ROOT / name) == expected, "Stale plugin input: " + name
for name, expected in manifest["sha256"].items():
    assert sha(dist / name) == expected, "Stale plugin artifact: " + name

tests = [
    ("prepared-oracles", PREPARED / "public.mo"),
    ("direct-oracles", ROUND3 / "public.mo"),
    ("aggregate-boundaries", ROOT / "plugins/bls12-381/tests/run/aggregate-boundaries.mo"),
    ("ordinary-callbacks", ROOT / "plugins/bls12-381/tests/run/aggregate-functions.mo"),
]
input_paths = [ROOT / name for name in selected_sources]
input_paths += [dist / name for name in ("build.json", "plugin.cmxs", "runtime.wasm")]
input_paths += [compiler / name for name in expected_toolchain]
input_paths += [ROOT / "packages/fast/src/BLS12381.mo", HERE / "run.py", HERE / "check-chain.py"]
for directory in (PREPARED, ROUND3):
    input_paths += [p for p in directory.iterdir()
                    if p.is_file() and p.suffix in (".mo", ".rs", ".tsv", ".toml", ".lock")]
input_paths += [source for _, source in tests]
before = {str(path): sha(path) for path in input_paths}
commands = []
tool_environment = dict(os.environ)
tool_environment.update({"MOC_RELEASE_RTS": str(compiler / "rts/mo-rts.wasm"),
                         "MOC_DEBUG_RTS": str(compiler / "rts/mo-rts-debug.wasm"),
                         "CARGO_BUILD_JOBS": "2", "RUST_TEST_THREADS": "2"})


def save():
    stable = all(sha(Path(path)) == expected for path, expected in before.items())
    report = {"phase": args.phase, "inputs_sha256": before, "inputs_unchanged": stable,
              "artifact_sha256": manifest["sha256"], "commands": commands,
              "tool_environment": {key: tool_environment[key] for key in
                                   ("MOC_RELEASE_RTS", "MOC_DEBUG_RTS", "CARGO_BUILD_JOBS", "RUST_TEST_THREADS")},
              "all_passed": stable and all(c["exit_code"] == 0 for c in commands)}
    (evidence / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    assert stable, "Frozen inputs changed during execution"


def run(name, command):
    log = evidence / (name + ".log")
    start = time.monotonic()
    command = [str(x) for x in command]
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                env=tool_environment)
    row = {"name": name, "command": command, "exit_code": result.returncode,
           "seconds": round(time.monotonic() - start, 3), "log": log.name, "log_sha256": sha(log)}
    commands.append(row)
    print(json.dumps(row), flush=True)
    save()
    if result.returncode:
        raise SystemExit(result.returncode)


run("symbolic-chain", ["python3", HERE / "check-chain.py", "--vendor",
                       ROOT / "plugins/bls12-381/runtime/vendor/bls12_381",
                       "--output", evidence / "chain-review.json"])
if args.phase in ("all", "native"):
    run("native-independent", ["cargo", "test", "--manifest-path", PREPARED / "Cargo.toml",
                               "--locked", "--offline", "--release", "--target-dir", scratch / "target",
                               "audit_", "--", "--nocapture"])
if args.phase in ("all", "public"):
    flags = ["--package", "fast", ROOT / "packages/fast/src", "--plugin", dist, "--sanity-checks"]
    for name, source in tests:
        run(name + "-interpreter", [compiler / "bin/moc", *flags, "-r", source])
        wasm = scratch / (name + ".wasm")
        run(name + "-compile", [compiler / "bin/moc", *flags, "-wasi-system-api", "-c", source, "-o", wasm])
        run(name + "-validate", ["wasm-validate", "--enable-memory64", "--enable-multi-memory", wasm])
        run(name + "-wasm", ["wasmtime", "run", "-C", "cache=n", "-W", "memory64", "-W", "multi-memory",
                             "-W", "bulk-memory", wasm])
        commands[-1]["wasm_sha256"] = sha(wasm)
        commands[-1]["wasm_bytes"] = wasm.stat().st_size
        save()
