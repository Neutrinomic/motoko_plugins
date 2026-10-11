#!/usr/bin/env python3
"""Validate every saved phase/trial before regenerating summary.csv."""

import csv
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
rows = []
for suite in ("main", "static", "repeated", "nested"):
    folder = root / suite
    before, after = [json.loads((folder / f"{label}.json").read_text())
                     for label in ("baseline", "candidate")]
    for report in (before, after):
        assert report["trials"] == 3 and report["failed_measurements"] == 0
        assert not report.get("fatal_error")
        for key, filename in (("source_sha256", "main.mo"), ("cases_sha256", "cases.json")):
            assert report[key] == hashlib.sha256((folder / filename).read_bytes()).hexdigest()
    for key in ("pocket_ic_version", "source_sha256", "cases_sha256", "runner_sha256"):
        assert before[key] == after[key]
    assert [c["name"] for c in before["cases"]] == [c["name"] for c in after["cases"]]
    for old, new in zip(before["cases"], after["cases"]):
        assert old["phases"] == new["phases"]
        for phase in old["phases"]:
            label = phase["label"]
            a, b = [[m for m in case["measurements"] if m["phase"] == label]
                    for case in (old, new)]
            for samples in (a, b):
                assert len(samples) == 3 and len({s["trial"] for s in samples}) == 3
                assert all("error" not in s and s["reclaimed_bytes"] == 0 for s in samples)
                for key in ("instructions", "allocated_bytes", "output_bytes", "output_sha256"):
                    assert len({s[key] for s in samples}) == 1
            for key in ("output_bytes", "output_sha256"):
                assert a[0][key] == b[0][key]
            rows.append({"suite": suite, "workload": old["name"], "phase": label,
                         "baseline_instructions": a[0]["instructions"],
                         "candidate_instructions": b[0]["instructions"],
                         "instruction_reduction_percent":
                         round(100 * (1 - b[0]["instructions"] / a[0]["instructions"]), 4),
                         "baseline_allocated_bytes": a[0]["allocated_bytes"],
                         "candidate_allocated_bytes": b[0]["allocated_bytes"],
                         "output_bytes": b[0]["output_bytes"],
                         "output_sha256": b[0]["output_sha256"]})
with (root / "summary.csv").open("w") as output:
    writer = csv.DictWriter(output, fieldnames=rows[0], lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
print(f"Validated {len(rows)} phases with three trials per baseline and candidate.")
