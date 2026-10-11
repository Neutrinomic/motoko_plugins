#!/usr/bin/env python3
"""Validate the unchanged SHA result and the two rejected, one-trial pilots."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent


def read(name):
    return json.loads((HERE / name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def csv_text(header, rows):
    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
    return output.getvalue()


def main():
    assert sys.argv[1:] in ([], ["--write"])
    provenance = read("provenance.json")
    for name, expected in provenance["archive_sha256"].items():
        assert sha(HERE / name) == expected, name
    cases = read("cases.json")["cases"]
    assert len(cases) == 18
    expected_cases = {case["name"]: case for case in cases}
    for case in cases:
        state = 0x9e3779b9
        payload = bytearray()
        for _ in range(case["input_bytes"]):
            state = (state ^ (state << 13)) & 0xffffffff
            state ^= state >> 17
            state = (state ^ (state << 5)) & 0xffffffff
            payload.append(state & 255)
        assert hashlib.sha256(payload).hexdigest() == case["expected_sha256_hex"]

    reports = {label: read(f"{label}.json") for label in ("baseline", "final")}
    reports.update({label: read(f"rejected/{label}.json")
                    for label in ("paired-loads", "counted-blocks")})
    for label, report in reports.items():
        trials = 3 if label in ("baseline", "final") else 1
        assert report["trials"] == trials and report["failed_measurements"] == 0
        assert not report.get("fatal_error")
        for key, name in (("source_sha256", "main.mo"), ("cases_sha256", "cases.json"),
                          ("runner_sha256", "run.mjs")):
            assert report[key] == sha(HERE / name)
        assert report["wasm_sha256"] == provenance["artifacts"][label]["actor_sha256"]
        assert report["pocket_ic_version"] == reports["baseline"]["pocket_ic_version"]
        assert report["measurement_protocol"] == reports["baseline"]["measurement_protocol"]
        names = [case["name"] for case in report["cases"]]
        assert len(names) == len(set(names))
        if trials == 3:
            assert names == list(expected_cases)
            build = read(f"{label}-build.json")
            assert build["motoko_revision"] == provenance["compiler_commit"]
            assert build["moc_sha256"] == provenance["compiler_executable_sha256"]
            assert not build["motoko_dirty"]
            artifact = provenance["artifacts"][label]
            for filename, key in (("runtime.wasm", "runtime_sha256"),
                                  ("plugin.cmxs", "compiler_plugin_sha256")):
                assert build["sha256"][filename] == artifact[key]
            assert build["source_sha256"]["plugins/sha256/runtime/src/lib.rs"] == artifact["source_sha256"]
        for case in report["cases"]:
            expected = expected_cases[case["name"]]
            assert case["phases"] == expected["phases"]
            samples = {(m["trial"], m["phase"]): m for m in case["measurements"]}
            assert len(samples) == len(case["measurements"]) == 2 * trials
            assert samples.keys() == {(trial, phase) for trial in range(trials)
                                      for phase in ("native", "plugin")}
            digest = hashlib.sha256(bytes.fromhex(expected["expected_sha256_hex"])).hexdigest()
            for sample in samples.values():
                assert "error" not in sample
                assert sample["output_bytes"] == 32 and sample["output_sha256"] == digest
                assert sample["reclaimed_bytes"] == 0
                assert sample["allocated_bytes"] == (56 if sample["phase"] == "plugin" else 1008)
            for phase in ("native", "plugin"):
                assert len({samples[trial, phase]["instructions"] for trial in range(trials)}) == 1

    before, after = reports["baseline"], reports["final"]
    assert before["cases"] == after["cases"]
    for key in ("source_sha256", "runtime_sha256", "actor_sha256"):
        assert provenance["artifacts"]["baseline"][key] == provenance["artifacts"]["final"][key]
    baseline = {case["name"]: {m["phase"]: m for m in case["measurements"] if m["trial"] == 0}
                for case in before["cases"]}
    summary_rows, experiment_rows = [], []
    for case in cases:
        plugin, native = [baseline[case["name"]][phase] for phase in ("plugin", "native")]
        summary_rows.append([case["input_bytes"], plugin["instructions"], plugin["instructions"],
                             native["instructions"], 56, 56, 1008, 0, 0,
                             f'{native["instructions"] / plugin["instructions"]:.6f}'])
    for label in ("paired-loads", "counted-blocks"):
        for case in reports[label]["cases"]:
            samples = {m["phase"]: m for m in case["measurements"]}
            assert samples["native"] == baseline[case["name"]]["native"]
            old, new = baseline[case["name"]]["plugin"]["instructions"], samples["plugin"]["instructions"]
            experiment_rows.append([label, expected_cases[case["name"]]["input_bytes"], old, new,
                                    new - old, f"{(new / old - 1) * 100:.6f}", 56, 56, 0])
    outputs = {
        "summary.csv": csv_text([
            "input_bytes", "baseline_instructions", "final_instructions", "mops_instructions",
            "baseline_allocated_bytes", "final_allocated_bytes", "mops_allocated_bytes",
            "final_reclaimed_bytes", "mops_reclaimed_bytes", "mops_over_final_instructions",
        ], summary_rows),
        "experiments.csv": csv_text([
            "experiment", "input_bytes", "baseline_instructions", "experiment_instructions",
            "instruction_delta", "instruction_change_percent", "baseline_allocated_bytes",
            "experiment_allocated_bytes", "experiment_reclaimed_bytes",
        ], experiment_rows),
    }
    for name, value in outputs.items():
        if sys.argv[1:]:
            (HERE / name).write_text(value)
        else:
            assert (HERE / name).read_text() == value, f"{name} drift"
    print("Validated 216 paired measurements, 28 rejected pilot measurements, oracle hashes and summaries.")


if __name__ == "__main__":
    main()
