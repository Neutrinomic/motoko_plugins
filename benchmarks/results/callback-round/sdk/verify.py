#!/usr/bin/env python3
"""Verify archived callback dispatch counts and portable artifact provenance."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
provenance = json.loads((root / "provenance.json").read_text())
assert provenance["abi"] == 1
for name in ("main.mo", "cases.json", "run.mjs", "fixture_callbacks.ml"):
    assert sha(root / name) == provenance[name + "_sha256"], name
cases = json.loads((root / "cases.json").read_text())["cases"]
assert [case["name"] for case in cases] == ["callbacks-0", "callbacks-1", "callbacks-4096"]
reports = {}
for label in ("baseline", "candidate"):
    report = json.loads((root / (label + ".json")).read_text())
    assert report["label"] == label
    assert report["trials"] == 3 and report["failed_measurements"] == 0
    assert not report.get("fatal_error")
    protocol = report["measurement_protocol"]
    assert protocol["fresh_canister"] == "per workload/trial"
    assert protocol["forced_gc_calls_before_phase"] == 4
    assert protocol["canister_cleanup"] == "stop and delete after each completed trial"
    assert report["source_sha256"] == provenance["main.mo_sha256"]
    assert report["cases_sha256"] == provenance["cases.json_sha256"]
    assert report["runner_sha256"] == provenance["run.mjs_sha256"]
    assert report["wasm_sha256"] == provenance["compilers"][label]["wasm_sha256"]
    assert [case["name"] for case in report["cases"]] == [case["name"] for case in cases]
    indexed = {}
    for case in report["cases"]:
        assert len(case["measurements"]) == 9
        keys = {(row["trial"], row["phase"]) for row in case["measurements"]}
        assert keys == {(trial, f"callback{arity}") for trial in range(3) for arity in range(3)}
        for row in case["measurements"]:
            assert "error" not in row
            assert row["allocated_bytes"] == row["reclaimed_bytes"] == 0
            assert row["output_bytes"] == 2
            assert row["output_sha256"] == hashlib.sha256(b"ok").hexdigest()
            indexed[(case["name"], row["trial"], row["phase"])] = row["instructions"]
    reports[label] = indexed
for case, count in zip(cases, (0, 1, 4096)):
    for arity, saved in enumerate((0, 3, 5)):
        for trial in range(3):
            key = (case["name"], trial, f"callback{arity}")
            assert reports["baseline"][key] - reports["candidate"][key] == count * saved
            if count == 0:
                assert reports["baseline"][key] == reports["candidate"][key] == 317
        for label in reports:
            assert len({reports[label][(case["name"], trial, f"callback{arity}")] for trial in range(3)}) == 1
print("54 callback samples, provenance, 0/3/5 per-call savings and zero allocation/reclamation verified")
