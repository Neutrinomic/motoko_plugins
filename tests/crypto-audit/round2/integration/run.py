#!/usr/bin/env python3
"""Run the complete integration suites against already-built, frozen artifacts."""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def inventory(motoko, bundle):
    files = set()
    for pattern in ("Cargo.toml", "Cargo.lock", "plugins/*/plugin.json", "plugins/*/compiler/**/*", "plugins/*/runtime/**/*", "packages/fast/mops.toml", "packages/fast/src/**/*.mo", "packages/fast/.mops/*/src/**/*.mo", "scripts/test*.sh", "tests/packaging.py", "tests/check-expectations.py", "dist/*/*"):
        files.update(p for p in ROOT.glob(pattern) if p.is_file() and "target" not in p.relative_to(ROOT).parts)
    directories = list(ROOT.glob("plugins/*/tests")) + [ROOT / "packages/fast/tests", ROOT / "tests/integration"]
    for directory in directories:
        for p in directory.rglob("*"):
            if p.is_file() and "_out" not in p.relative_to(directory).parts and (p.suffix == ".mo" or p.name.endswith((".ok", ".ash.json"))):
                files.add(p)
    values = {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)}
    for key, p in {"compiler/moc": motoko / "src/moc", "compiler/release-rts": motoko / "rts/mo-rts.wasm", "compiler/debug-rts": motoko / "rts/mo-rts-debug.wasm", "ash/moc": bundle / "moc", "ash/release-rts": bundle / "mo-rts.wasm", "ash/debug-rts": bundle / "mo-rts-debug.wasm"}.items():
        values[key] = digest(p)
    return values


def artifact_checks(motoko):
    result = {}
    moc = digest(motoko / "src/moc")
    manifests = sorted(ROOT.glob("plugins/*/plugin.json"))
    assert len(manifests) == 20, f"Expected all 20 plugins; found {len(manifests)}"
    for manifest in manifests:
        name = manifest.parent.name
        directory = ROOT / "dist" / name
        metadata = json.loads((directory / "build.json").read_text())
        own_prefix = f"plugins/{name}/"
        own = {key: value for key, value in metadata["source_sha256"].items() if key.startswith(own_prefix)}
        assert own, f"No source hashes for {name}"
        mismatches = [key for key, value in own.items() if not (ROOT / key).is_file() or digest(ROOT / key) != value]
        assert not mismatches, f"Stale {name} sources: {mismatches}"
        assert metadata["moc_sha256"] == moc, f"{name} compiler mismatch"
        stale_host_sources = [key for key, value in metadata["motoko_source_sha256"].items() if not (motoko / key).is_file() or digest(motoko / key) != value]
        assert not stale_host_sources, f"Stale {name} compiler source snapshot: {stale_host_sources}"
        artifacts = {key: digest(directory / key) for key in metadata["sha256"]}
        assert artifacts == metadata["sha256"], f"{name} artifact hash mismatch"
        stale_peer_sources = [key for key, value in metadata["source_sha256"].items() if not key.startswith(own_prefix) and (not (ROOT / key).is_file() or digest(ROOT / key) != value)]
        assert not stale_peer_sources, f"Stale {name} peer source snapshot: {stale_peer_sources}"
        result[name] = {"source_sha256": own, "artifact_sha256": artifacts, "build_metadata_sha256": digest(directory / "build.json"), "stale_peer_snapshot_sources": stale_peer_sources}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--ash-source", type=Path, required=True)
    parser.add_argument("--build-log", type=Path, required=True, help="Successful final shared build log to archive with the results")
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    ash_source = args.ash_source.resolve()
    output = ROOT / "_build/crypto-optimization-round2"
    output.mkdir(parents=True, exist_ok=True)
    build_log = args.build_log.resolve()
    assert build_log.is_file(), f"Missing final build log: {build_log}"
    ash_bin = Path(subprocess.check_output(["bun", str(ash_source / "src/index.ts"), "bin"], text=True).strip())
    bundle = ash_bin.parent / "lib/motoko-compute"
    for source, installed in ((motoko / "src/moc", bundle / "moc"), (motoko / "rts/mo-rts.wasm", bundle / "mo-rts.wasm"), (motoko / "rts/mo-rts-debug.wasm", bundle / "mo-rts-debug.wasm")):
        assert digest(source) == digest(installed), f"Ash toolchain mismatch: {source} != {installed}"
    artifact_evidence = artifact_checks(motoko)
    before = inventory(motoko, bundle)
    write_json(output / "final-before.json", before)
    shutil.copyfile(output / "final-before.json", EVIDENCE / "before.json")
    shutil.copyfile(build_log, EVIDENCE / "build.log")
    configs = sorted(ROOT.glob("packages/fast/tests/ash/*.ash.json"))
    expected_methods = 0
    for config in configs:
        for canister in json.loads(config.read_text())["canisters"]:
            source = (config.parent / canister["src"]).read_text()
            expected_methods += len(re.findall(r"public\s+(?:shared\s+)?(?:query\s+)?func\s+test\w*\s*\(", source))
    fixtures = []
    for pattern in ("plugins/*/tests", "packages/*/tests", "tests/integration"):
        for parent in ROOT.glob(pattern):
            for kind in ("run", "fail", "trap", "run-drun"):
                fixtures.extend((parent / kind).glob("*.mo"))
    commands = {
        "tests": ["nix", "develop", "--command", str(ROOT / "scripts/test.sh"), "--motoko", str(motoko)],
        "ash": [str(ROOT / "scripts/test-ash.sh"), "--ash-source", str(ash_source)],
    }

    def run(name):
        started = time.monotonic()
        path = output / f"final-{name}.log"
        with path.open("w") as logfile:
            completed = subprocess.run(commands[name], cwd=motoko if name == "tests" else ROOT, stdout=logfile, stderr=subprocess.STDOUT)
        durable_log = EVIDENCE / f"{name}.log"
        shutil.copyfile(path, durable_log)
        result = {"command": commands[name], "cwd": str(motoko if name == "tests" else ROOT), "exit_code": completed.returncode, "seconds": round(time.monotonic() - started, 2), "log": str(durable_log.relative_to(ROOT)), "log_sha256": digest(durable_log)}
        write_json(output / f"final-{name}-status.json", result)
        print(f"{name}: exit {completed.returncode}; {result['seconds']}s; {path}", flush=True)
        return result

    print(f"Starting frozen integration verification: {len(fixtures)} Motoko fixtures, {len(configs)} Ash configurations, {expected_methods} Ash test methods", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        tasks = {pool.submit(run, name): name for name in commands}
        executions = {tasks[f]: f.result() for f in concurrent.futures.as_completed(tasks)}
    after = inventory(motoko, bundle)
    write_json(output / "final-after.json", after)
    shutil.copyfile(output / "final-after.json", EVIDENCE / "after.json")
    changed = [key for key in sorted(before.keys() | after.keys()) if before.get(key) != after.get(key)]
    tests_log = (output / "final-tests.log").read_text()
    ash_log = (output / "final-ash.log").read_text()
    native = [(int(a), int(b)) for a, b in re.findall(r"test result: \w+\. (\d+) passed; (\d+) failed", tests_log)]
    motoko_run = [int(n) for n in re.findall(r"You ran (\d+) tests", tests_log)]
    motoko_passed = [int(n) for n in re.findall(r"(\d+) tests ran successfully", tests_log)]
    ash = [tuple(map(int, row)) for row in re.findall(r"Summary: (\d+) succeeded, (\d+) failed, (\d+) skipped, (\d+) total", ash_log)]
    report = {
        "schema": 1,
        "recorded_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "runner_sha256": digest(Path(__file__)),
        "status": "passed" if not changed and all(x["exit_code"] == 0 for x in executions.values()) and motoko_run == [len(fixtures)] and motoko_passed == [len(fixtures)] and len(ash) == len(configs) and sum(x[0] for x in ash) == expected_methods else "failed",
        "executions": executions,
        "build_log": {"path": str((EVIDENCE / "build.log").relative_to(ROOT)), "sha256": digest(EVIDENCE / "build.log")},
        "source_and_artifacts_unchanged": not changed,
        "changed_paths": changed,
        "inventory": {"files": len(before), "before_sha256": digest(EVIDENCE / "before.json"), "after_sha256": digest(EVIDENCE / "after.json"), "before_path": str((EVIDENCE / "before.json").relative_to(ROOT)), "after_path": str((EVIDENCE / "after.json").relative_to(ROOT))},
        "toolchain_sha256": {key: value for key, value in before.items() if key.startswith(("compiler/", "ash/"))},
        "native": {"test_groups": len(native), "passed": sum(x[0] for x in native), "failed": sum(x[1] for x in native)},
        "motoko": {"fixture_count_from_source": len(fixtures), "runner_counts": motoko_run, "passed_counts": motoko_passed, "expectation_acceptance": False, "includes_packaging_and_expectation_guard": executions["tests"]["exit_code"] == 0},
        "ash": {"configurations_from_source": len(configs), "methods_from_source": expected_methods, "summaries": len(ash), "passed": sum(x[0] for x in ash), "failed": sum(x[1] for x in ash), "skipped": sum(x[2] for x in ash), "total": sum(x[3] for x in ash)},
        "plugins": artifact_evidence,
    }
    write_json(Path(__file__).parent / "report.json", report)
    print(json.dumps({key: report[key] for key in ("status", "changed_paths", "native", "motoko", "ash")}, indent=2), flush=True)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
