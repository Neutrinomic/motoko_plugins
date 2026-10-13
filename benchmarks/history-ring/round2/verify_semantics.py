#!/usr/bin/env python3
"""Check complete benchmark evidence against closed-form sequence semantics.

This verifies measured counters/checksums and the final harness's recorded
post-measurement order/retention checks. Returned page/pop order still requires
the independent model tests.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("results", nargs="+", type=Path, help="results.json files or stage directories")
args = parser.parse_args()
names = {
    "append", "overwrite", "get_middle", "drop_zero", "drop_quarter",
    "drop_half", "drop_all", "drop_wrapped_half", "drop_wrapped_all", "pop_all",
    *(f"page_{kind}_{length}" for kind in ("tail", "wrapped") for length in (1, 32, 64, 1024)),
}


def payload_checksum(finish, count, payload_bytes):
    """Sum expected byte values for the final count sequence-numbered Blobs."""
    def prefix(length):
        cycles, remainder = divmod(length, 251)
        return cycles * (250 * 251 // 2) + remainder * (remainder - 1) // 2
    return sum(prefix(sequence + payload_bytes) - prefix(sequence)
               for sequence in range(finish - count, finish))


def check_storage(storage, count):
    assert int(storage["slots"]) == count
    assert int(storage["bytes"]) == count * 1024
    assert 0 <= int(storage["chunks"]) <= int(storage["directory"]) <= 16


for path in args.results:
    if path.is_dir():
        path = path / "results.json"
    report = json.loads(path.read_text())
    build = json.loads((path.parent / "build.json").read_text())
    assert report["build"] == build, "Result/build manifest mismatch"
    for relative, evidence in build["archive"].items():
        actual = hashlib.sha256((path.parent / relative).read_bytes()).hexdigest()
        assert actual == evidence["sha256"] == build["sha256"][evidence["source"]], relative
    actor = (path.parent / "harness/main.mo").read_text()
    has_verify = bool(re.search(r"public\s+query\s+func\s+verify\s*\(", actor))
    selected = report["arguments"]["operations"]
    selected = names if selected == "all" else set(selected.split(","))
    assert selected <= names, f"Unknown operations: {selected - names}"
    capacities = {int(size) for size in report["arguments"]["sizes"].split(",") if size}
    expected_cases = {(capacity, name) for capacity in capacities for name in selected}
    actual_cases = {(row["capacity"], row["operation"]) for row in report["cases"]}
    assert actual_cases == expected_cases, "Missing or unexpected cases"
    assert len(actual_cases) == len(report["cases"]), "Duplicate cases"
    trials = int(report["arguments"]["trials"])
    assert trials > 0 and trials == report["trials"]
    checked = 0
    for row in report["cases"]:
        capacity, name, reps = row["capacity"], row["operation"], row["repetitions"]
        size = finish = 0 if name == "append" else capacity
        if row["wrapped"]:
            finish += 2 * capacity + 3
            size = capacity
        operations = reps
        if name in ("append", "overwrite"):
            checksum = reps * (2 * finish + reps - 1) // 2
            finish += reps
            size = min(capacity, size + reps)
        elif name == "get_middle":
            checksum = (finish - size // 2 - 1) * reps if size else 0
        elif name.startswith("page_"):
            count = min(size, row["pageLength"])
            checksum = count * (2 * finish - count - 1) // 2 * reps
        elif name.startswith("drop_"):
            operations = min(size, reps)
            checksum = operations
            size -= operations
        elif name == "pop_all":
            count = min(size, reps)
            checksum = count * (2 * (finish - size) + count - 1) // 2
            size -= count
        else:
            raise AssertionError(name)
        expected = dict(checksum=checksum % (2 ** 32), size=size,
                        first=finish - size, next=finish, operations=operations)
        assert len(row["samples"]) == trials, (capacity, name, "Incomplete trials")
        assert {sample["trial"] for sample in row["samples"]} == set(range(trials))
        for sample in row["samples"]:
            for implementation in ("core", "plugin"):
                for field, value in expected.items():
                    actual = int(sample[implementation][field])
                    assert actual == value, (capacity, name, implementation, field, actual, value)
                assert int(sample[implementation]["reclaimed"]) == 0
                if has_verify:
                    verified = sample[implementation]["verified"]
                    for field, value in dict(count=size, first=finish - size, next=finish,
                                             slots=size if implementation == "plugin" else 0).items():
                        assert int(verified[field]) == value, (capacity, name, implementation, "verified", field)
            checked += 1
    if report["arguments"]["churn"] == "yes":
        churn = report["churn"]
        assert len(churn) == 2 and {row["implementation"] for row in churn} == {"core", "plugin"}
        for row in churn:
            assert (row["capacity"], row["payload_bytes"], row["batch"]) == (1024, 1024, 1024)
            assert [point["batches"] for point in row["checkpoints"]] == [0, 1, 2, 4, 8, 16, 32, 64]
            for point in row["checkpoints"]:
                batches = point["batches"]
                assert int(point["memory"]["size"]) == (1024 if batches else 0)
                if batches:
                    assert int(point["checksum"]) == payload_checksum(batches * 1024, 1024, 1024)
                    if row["implementation"] == "plugin":
                        check_storage(point["storage"], 1024)
            partial = row["partial_drop"]
            assert int(partial["removed"]) == 512 and int(partial["memory"]["size"]) == 512
            assert int(partial["checksum"]) == payload_checksum(64 * 1024, 512, 1024)
            assert int(row["cleared"]["size"]) == 0
            if row["implementation"] == "plugin":
                check_storage(partial["storage"], 512)
                assert all(int(row["cleared_storage"][field]) == 0
                           for field in ("directory", "chunks", "slots", "bytes"))
    else:
        assert report["arguments"]["churn"] == "no" and not report["churn"]
    print(f"{path}: archives verified; {len(actual_cases)} cases / {checked} paired samples match independent sequence formulas; "
          f"exact-state evidence={'required' if has_verify else 'older harness'}; churn={report['arguments']['churn']}")
