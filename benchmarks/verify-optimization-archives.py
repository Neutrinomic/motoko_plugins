#!/usr/bin/env python3
"""Check saved optimization evidence without rebuilding or measuring anything."""

import csv
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "benchmarks/results/optimization-round"
ROUND2 = ROOT / "benchmarks/results/optimization-round-2"


def read_json(path):
    return json.loads(path.read_text())


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_sdk(folder):
    manifest = read_json(folder / "artifact-manifest.json")
    names = manifest["archive_files"]
    assert len(names) == len(set(names))
    assert set(names) == set(manifest["files"]) | {"artifact-manifest.json"}
    for name in names:
        path = folder / name
        assert path.is_file(), path
        # The manifest cannot contain its own hash.
        if name != "artifact-manifest.json":
            expected = manifest["files"][name]
            assert sha256(path) == expected["sha256"], path
            assert path.stat().st_size == expected["bytes"], path
    print(f"Validated {len(names) - 1} SDK archive hashes.")


def check_sha256():
    folder = ARCHIVE / "sha256"
    provenance = read_json(folder / "provenance.json")
    cases = read_json(folder / "cases.json")["cases"]
    before, after = [read_json(folder / f"{label}.json")
                     for label in ("baseline", "final")]
    assert len(cases) == 18
    for report, label in ((before, "baseline"), (after, "final")):
        assert report["trials"] == 3 and report["failed_measurements"] == 0
        assert not report.get("fatal_error")
        assert report["source_sha256"] == sha256(folder / "main.mo")
        assert report["source_sha256"] == provenance["actor_source_sha256"]
        assert report["cases_sha256"] == sha256(folder / "cases.json")
        assert report["cases_sha256"] == provenance["cases_sha256"]
        assert report["runner_sha256"] == provenance["runner_sha256"]
        # The identical historical runner is archived with the SDK evidence.
        assert report["runner_sha256"] == sha256(ARCHIVE / "sdk/run.mjs")
        artifact = provenance["artifacts"][label]
        assert report["wasm_sha256"] == artifact["actor_sha256"]
        build = read_json(folder / f"{label}-build.json")
        assert build["moc_sha256"] == provenance["compiler_executable_sha256"]
        assert build["sha256"]["runtime.wasm"] == artifact["runtime_sha256"]
        assert build["sha256"]["plugin.cmxs"] == artifact["compiler_plugin_sha256"]
    for key in ("pocket_ic_version", "measurement_protocol", "wasm_sha256"):
        assert before[key] == after[key], key
    assert (provenance["artifacts"]["baseline"]["runtime_sha256"] ==
            provenance["artifacts"]["final"]["runtime_sha256"])
    assert [c["name"] for c in before["cases"]] == [c["name"] for c in cases]
    assert before["cases"] == after["cases"], "SHA paired measurements changed"
    rows = []
    for case, expected in zip(before["cases"], cases):
        assert case["phases"] == expected["phases"]
        samples = {(m["trial"], m["phase"]): m for m in case["measurements"]}
        assert len(samples) == len(case["measurements"]) == 6
        assert samples.keys() == {(trial, phase) for trial in range(3)
                                  for phase in ("plugin", "native")}
        digest = hashlib.sha256(bytes.fromhex(expected["expected_sha256_hex"])).hexdigest()
        for sample in samples.values():
            assert "error" not in sample, (case["name"], sample)
            assert sample["output_bytes"] == 32 and sample["output_sha256"] == digest
        for phase in ("plugin", "native"):
            for key in ("instructions", "allocated_bytes", "reclaimed_bytes"):
                assert len({samples[trial, phase][key] for trial in range(3)}) == 1
        plugin, native = samples[0, "plugin"], samples[0, "native"]
        assert plugin["reclaimed_bytes"] == 0
        rows.append([
            expected["input_bytes"], plugin["instructions"], plugin["instructions"],
            native["instructions"], plugin["allocated_bytes"], plugin["allocated_bytes"],
            native["allocated_bytes"], plugin["reclaimed_bytes"], native["reclaimed_bytes"],
            f'{native["instructions"] / plugin["instructions"]:.6f}',
        ])
    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow([
        "input_bytes", "baseline_instructions", "final_instructions", "mops_instructions",
        "baseline_allocated_bytes", "final_allocated_bytes", "mops_allocated_bytes",
        "final_reclaimed_bytes", "mops_reclaimed_bytes", "mops_over_final_instructions",
    ])
    writer.writerows(rows)
    assert output.getvalue().encode() == (folder / "summary.csv").read_bytes(), "SHA summary drift"
    print("Validated 216 SHA measurements and summary.csv.")


def main():
    check_sdk(ARCHIVE / "sdk")
    check_sdk(ROUND2 / "sdk")
    check_sha256()
    # The component scripts regenerate summaries in place. Preserve the archive.
    with tempfile.TemporaryDirectory(prefix="optimization-archives-") as temporary:
        copied = shutil.copytree(ARCHIVE, Path(temporary) / "optimization-round")
        copied2 = shutil.copytree(ROUND2, Path(temporary) / "optimization-round-2")
        for component, script in (("candidx", "verify-summary.py"),
                                  ("json", "summarize.py"), ("cbor", "summarize.py")):
            subprocess.run([sys.executable, str(copied / component / script)], check=True)
            assert ((copied / component / "summary.csv").read_bytes() ==
                    (ARCHIVE / component / "summary.csv").read_bytes()), component
        for archive, script, suites in (
            (ARCHIVE, ROOT / "benchmarks/compare-map-optimization.py", ("functions", "bulk", "point")),
            (ROUND2, ROUND2 / "pure-map/harness/compare-map-optimization.py", ("functions", "small", "empty")),
        ):
            for suite in suites:
                saved = archive / "pure-map" / suite
                generated = Path(temporary) / archive.name / "generated-map" / suite
                subprocess.run([
                    sys.executable, str(script),
                    "--before", str(saved / "before"), "--after", str(saved / "after"),
                    "--out", str(generated),
                ], check=True)
                for name in ("before.csv", "after.csv", "comparison.csv", "costs.md", "validation.json"):
                    assert (generated / name).read_bytes() == (saved / name).read_bytes(), (saved, name)
        for component, script in (("candidx", "verify-summary.py"), ("json", "summarize.py"),
                                  ("cbor", "summarize.py"), ("sdk", "summarize.py")):
            subprocess.run([sys.executable, str(copied2 / component / script)], check=True)
            assert ((copied2 / component / "summary.csv").read_bytes() ==
                    (ROUND2 / component / "summary.csv").read_bytes()), component
        subprocess.run([sys.executable, str(copied2 / "sha256/verify.py")], check=True)
        for component in ("json", "cbor"):
            relative = Path("integrated") / component
            subprocess.run([sys.executable, str(copied / relative / "summarize.py")], check=True)
            assert ((copied / relative / "comparison.csv").read_bytes() ==
                    (ARCHIVE / relative / "comparison.csv").read_bytes()), relative
        saved = ARCHIVE / "integrated/candidx-sha256"
        generated = Path(temporary) / "candidx-sha256.csv"
        subprocess.run([
            sys.executable, str(ROOT / "benchmarks/summarize-comparison.py"),
            str(saved / "results.json"), "--expected-cases", "7", "--expected-trials", "3",
            "--out", str(generated),
        ], check=True)
        assert generated.read_bytes() == (saved / "summary.csv").read_bytes(), saved
    print("Optimization archive validation passed.")


if __name__ == "__main__":
    main()
