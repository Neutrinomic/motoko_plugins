#!/usr/bin/env python3
"""Read-only acceptance of the final prepared P256 benchmark evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stats(values):
    return {"median": statistics.median(values), "range": [min(values), max(values)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    build = json.loads((stage / "build.json").read_text())
    results = json.loads((stage / "results.json").read_text())
    comparison_path = ROOT / "benchmarks/crypto/prepared/p256/final-comparison.json"
    comparison = json.loads(comparison_path.read_text())
    audit = json.loads((HERE / "execution-native.json").read_text())
    assert build["complete"] and results["complete"]
    assert build["expected_case_count"] == results["expected_case_count"] == comparison["case_count"] == 37
    assert results["trials"] == comparison["trials"] == 3 and results["failed_measurements"] == 0
    assert len(comparison["groups"]) == 7 and not comparison["controls"]
    assert results["build_sha256"] == sha(stage / "build.json")
    run, = comparison["runs"]
    assert run["stage"] == stage.name == results["stage"] == build["stage"]
    assert run["build_sha256"] == sha(stage / "build.json")
    assert run["results_sha256"] == sha(stage / "results.json")
    assert build["compiler_sha256"] == audit["compiler_sha256"] == run["toolchain"]["compiler_sha256"]
    for name, digest in build["frozen_inputs_sha256"].items():
        assert sha(stage / "inputs" / name) == digest, name
    for name, digest in audit["artifact_sha256"].items():
        assert sha(stage / "inputs/dist/p256" / name) == digest, name
        assert sha(ROOT / "dist/p256" / name) == digest, name
    for name, digest in audit["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    assert sha(stage / "inputs/packages/fast/src/P256.mo") == audit["source_sha256"]["packages/fast/src/P256.mo"]
    compiled = {case["name"]: case for case in build["cases"]}
    measured = {case["name"]: case for case in results["cases"]}
    assert len(compiled) == len(measured) == 37 and compiled.keys() == measured.keys()
    trial_count = 0
    for name, case in measured.items():
        source = stage / "inputs/benchmarks/crypto" / case["source"]
        wasm = stage / case["wasm"]
        for field in ["returncode", "source_sha256", "wasm_sha256", "wasm_bytes", "expected_hex", "prepared"]:
            assert case[field] == compiled[name][field], (name, field)
        assert case["returncode"] == 0
        assert sha(source) == case["source_sha256"] == sha(ROOT / "benchmarks/crypto" / case["source"])
        assert sha(wasm) == case["wasm_sha256"] and wasm.stat().st_size == case["wasm_bytes"]
        rows = case["measurements"]
        assert sorted(row["trial"] for row in rows) == [0, 1, 2]
        expected = bytes.fromhex(case["expected_hex"])
        for row in rows:
            assert row["correct"] and row["output_bytes"] == len(expected)
            assert row["output_sha256"] == hashlib.sha256(expected).hexdigest()
            assert row["instructions"] > 0 and row["reclaimed_bytes"] == 0
        assert all({k: v for k, v in row.items() if k != "trial"} ==
                   {k: v for k, v in rows[0].items() if k != "trial"} for row in rows)
        mode, reuse = case["prepared"]["mode"], case["prepared"]["reuse"]
        allocation = 16376 if mode == "prepare" else 32 * reuse + (16376 if mode == "cold" else 0)
        assert rows[0]["allocated_bytes"] == allocation
        trial_count += len(rows)
    reported = set()
    for group in comparison["groups"]:
        pins = group["plugin_pins"]["p256"]
        assert pins["artifacts"] == {k: audit["artifact_sha256"][k] for k in ["runtime.wasm", "plugin.cmxs"]}
        assert pins["sources"] == {k: v for k, v in audit["source_sha256"].items() if k != "packages/fast/src/P256.mo"}
        assert group["toolchain"] == run["toolchain"]
        for case in [group["direct"], group["prepare"], group["prepared"], *group["actual_batches"]]:
            assert case["name"] not in reported
            reported.add(case["name"])
            raw = measured[case["name"]]
            assert raw["prepared"]["comparison_group"] == group["comparison_group"]
            assert raw["expected_hex"] == group["expected_hex"]
            for field in ["source_sha256", "wasm_sha256", "wasm_bytes"]:
                assert case[field] == raw[field]
            for field in ["instructions", "allocated_bytes", "reclaimed_bytes"]:
                assert case[field] == stats([row[field] for row in raw["measurements"]])
            for phase, metrics in case["memory"].items():
                for field, value in metrics.items():
                    assert value == stats([row["memory"][phase][field] for row in raw["measurements"]])
        direct, prepare, hot = [group[k]["instructions"]["median"] for k in ["direct", "prepare", "prepared"]]
        assert direct > hot
        assert group["strict_instruction_break_even_reuses"] == prepare // (direct - hot) + 1 == 3
        for row in group["models"]:
            assert row["direct_instructions"] == row["reuse"] * direct
            assert row["prepared_instructions"] == prepare + row["reuse"] * hot
    assert reported == measured.keys() and trial_count == 111
    summary = {"schema": 1, "accepted": True, "stage": stage.name,
               "case_count": 37, "trials": 111, "groups": 7,
               "all_trial_metrics_identical": True,
               "frozen_inputs_checked": len(build["frozen_inputs_sha256"]),
               "audited_artifact_and_source_parity": True,
               "instruction_allocation_memory_summaries_recomputed": True,
               "break_even_is_model_not_measured_three_call_batch": True,
               "build_sha256": sha(stage / "build.json"),
               "results_sha256": sha(stage / "results.json"),
               "comparison_sha256": sha(comparison_path),
               "checker_sha256": sha(Path(__file__)),
               "notes": ["Only the complete final-fixed stage contributes counters.",
                         "Occupied heap samples are not retained live memory or a completed-GC claim."]}
    (HERE / "benchmark-acceptance.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
