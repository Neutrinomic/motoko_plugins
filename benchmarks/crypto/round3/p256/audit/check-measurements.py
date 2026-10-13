#!/usr/bin/env python3
"""Independently verify the paired PocketIC artifacts and audited candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(stage):
    build = json.loads((stage / "build.json").read_text())
    results = json.loads((stage / "results.json").read_text())
    assert build["complete"] and results["complete"]
    assert build["expected_case_count"] == results["expected_case_count"] == 30
    assert results["trials"] == 3 and results["failed_measurements"] == 0
    assert results["build_sha256"] == digest((stage / "build.json").read_bytes())
    assert results["runner_sha256"] == build["runner_sha256"]
    for path, expected in build["frozen_inputs_sha256"].items():
        assert digest((stage / "inputs" / path).read_bytes()) == expected, path
    with tarfile.open(stage / "sources.tar.gz") as archive:
        for member in archive.getmembers():
            assert member.isfile(), member.name
            expected = build["frozen_inputs_sha256"][member.name]
            assert digest(archive.extractfile(member).read()) == expected, member.name
    builds = {case["name"]: case for case in build["cases"]}
    cases = {case["name"]: case for case in results["cases"]}
    assert len(builds) == len(cases) == 30 and builds.keys() == cases.keys()
    for name, case in cases.items():
        assert case["returncode"] == builds[name]["returncode"] == 0
        assert len(case["measurements"]) == 3
        assert {m["trial"] for m in case["measurements"]} == {0, 1, 2}
        wasm = (stage / case["wasm"]).read_bytes()
        assert digest(wasm) == case["wasm_sha256"] == builds[name]["wasm_sha256"]
        assert len(wasm) == case["wasm_bytes"]
        expected = bytes.fromhex(case["expected_hex"])
        for m in case["measurements"]:
            assert m["correct"] and m["output_sha256"] == digest(expected)
            assert m["output_bytes"] == len(expected)
    return build, results, cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-root", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    paths = [args.results_root / f"round3-p256-{suffix}" for suffix in ["baseline", "comb"]]
    before, after = [load(path) for path in paths]
    bbuild, bresults, bcases = before
    abuild, aresults, acases = after
    assert bbuild["compiler_sha256"] == abuild["compiler_sha256"]
    assert bbuild["runner_sha256"] == abuild["runner_sha256"]
    assert bresults["pocket_ic_sha256"] == aresults["pocket_ic_sha256"]
    for path, value in bbuild["frozen_inputs_sha256"].items():
        if path.startswith(("toolchain/", "benchmarks/crypto/dependencies/")):
            assert abuild["frozen_inputs_sha256"][path] == value, path
    for path in ["plugins/p256/runtime/src/lib.rs", "plugins/p256/runtime/Cargo.toml",
                 "dist/p256/runtime.wasm", "plugins/p256/compiler/register.ml"]:
        assert digest((args.candidate_root / path).read_bytes()) == abuild["frozen_inputs_sha256"][path]
    rows = []
    for name, before in bcases.items():
        after = acases[name]
        for field in ["source_sha256", "expected_hex", "operations_per_sample"]:
            assert before[field] == after[field], (name, field)
        for bm, am in zip(before["measurements"], after["measurements"]):
            for field in ["allocated_bytes", "reclaimed_bytes", "memory"]:
                assert bm[field] == am[field], (name, field)
        bi = statistics.median(m["instructions"] for m in before["measurements"])
        ai = statistics.median(m["instructions"] for m in after["measurements"])
        assert ai <= bi, name
        assert after["wasm_bytes"] - before["wasm_bytes"] == 8416
        rows.append({"name": name, "beforeInstructions": bi, "afterInstructions": ai,
                     "instructionReductionPercent": (bi - ai) / bi * 100})
    report = {
        "status": "PASS", "pairedCases": 30, "freshCanisterMeasurements": 180,
        "unchangedAllocationAndSampledMemory": True,
        "noInstructionRegressions": True, "canisterWasmGrowthBytes": 8416,
        "candidateRuntimeSha256": abuild["frozen_inputs_sha256"]["dist/p256/runtime.wasm"],
        "candidateSourceSha256": abuild["frozen_inputs_sha256"]["plugins/p256/runtime/src/lib.rs"],
        "frozenInputCounts": [len(bbuild["frozen_inputs_sha256"]), len(abuild["frozen_inputs_sha256"])],
        "artifacts": {str(path / file): digest((path / file).read_bytes())
                      for path in paths for file in ["build.json", "results.json", "sources.tar.gz"]},
        "rows": rows,
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: 30 paired cases, 180 correct measurements, all frozen hashes and candidate parity verified")


if __name__ == "__main__":
    main()
