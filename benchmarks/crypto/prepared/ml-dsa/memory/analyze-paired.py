#!/usr/bin/env python3
"""Validate and describe a pinned memory run; never execute or rewrite it."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import statistics


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked_file(path, expected):
    data = Path(path).read_bytes()
    require(sha(data) == expected, f"SHA-256 mismatch: {path}")
    return data


def integer(value, label):
    require(type(value) is int and value >= 0, f"Nonnegative integer required: {label}")
    return value


def summary(values):
    require(bool(values), "Empty paired series")
    return {"min": min(values), "median": statistics.median(values), "max": max(values)}


def analyze(report_path, evidence_path):
    evidence_bytes = evidence_path.read_bytes()
    evidence = json.loads(evidence_bytes)
    raw = checked_file(report_path, evidence["original_report_sha256"])
    report = json.loads(raw)
    provenance = report["provenance"]
    require(report["format"] == "ml-dsa-prepared-memory-v1", "Unexpected raw report format")
    require(report["complete"] is False and report["executionComplete"] is True
            and report["status"] == "incomplete-needs-investigation" and report["errors"] == [],
            "Require the original completed execution with failed absolute qualification")
    require(evidence["compiler_sha256"] == provenance["compilerSha256"], "Compiler source evidence mismatch")
    require(evidence["rts_release_sha256"] == provenance["rts"]["mo-rts.wasm"]["sha256"], "RTS source evidence mismatch")
    count = integer(evidence["expected_keys"], "expected_keys")
    trials = integer(evidence["expected_trials"], "expected_trials")
    expected_step = integer(evidence["expected_gc_allocation_increment_bytes"], "expected GC allocation")
    require((count, trials) == (32, 3), "This post-hoc analysis is scoped to 32 keys and three trials")
    require(report["options"]["keys"] == count and report["options"]["trials"] == trials, "Run size mismatch")
    protocol = report["protocol"]
    require(protocol["modes"] == ["baseline", "public", "secret"]
            and protocol["pressureCallsPerStage"] == 4 and protocol["gcTriggerCallsPerStage"] == 24
            and protocol["tailSamples"] == 8 and protocol["pressurePayloadBytesPerCall"] == 32 * 1024 * 1024
            and protocol["minimumReclaimedBytesPerStage"] == 64 * 1024 * 1024
            and protocol["maximumTailHeapSpreadBytes"] == 4096
            and protocol["requireZeroEvacuationCopiesInTail"] is True
            and protocol["preparedPayloadBytes"] == [0, 20576, 28800], "Original protocol changed")

    # Validate the actual archived inputs, not just their recorded hash strings.
    artifacts = report["artifacts"]
    for name, pin in evidence["original_provenance"].items():
        require(provenance[name] == pin, f"Source evidence provenance mismatch: {name}")
    for name, pin in evidence["original_artifact_sha256"].items():
        require(artifacts[name]["sha256"] == pin, f"Source evidence artifact mismatch: {name}")
    verified_artifacts = {}
    artifact_bytes = {}
    for name in ["sourceArchive", "wasm", "fullBuildSourceArchive", "transportTrace", "serverLog"]:
        item = artifacts[name]
        # Committed sibling files take precedence over machine-specific paths.
        sibling = report_path.parent / Path(item["path"]).name
        path = sibling if sibling.is_file() else Path(item["path"])
        if name == "sourceArchive":
            path = sibling
        if not path.is_file():
            require(name != "sourceArchive", "Missing committed source archive")
            verified_artifacts[name] = {"status": "not-available", "recordedSha256": item["sha256"]}
            continue
        data = checked_file(path, item["sha256"])
        artifact_bytes[name] = data
        verified_artifacts[name] = {"status": "verified-present-file", "path": str(path), "sha256": sha(data), "bytes": len(data)}
    require(artifacts["wasm"]["sha256"] == provenance["wasmSha256"], "Wasm provenance pin mismatch")
    if "wasm" in artifact_bytes:
        require(len(artifact_bytes["wasm"]) == provenance["wasmBytes"], "Wasm size mismatch")
    compressed_trace = report_path.parent / (Path(artifacts["transportTrace"]["path"]).name + ".gz")
    if compressed_trace.is_file():
        compressed = compressed_trace.read_bytes()
        require(sha(gzip.decompress(compressed)) == artifacts["transportTrace"]["sha256"], "Compressed transport trace content mismatch")
        verified_artifacts["compressedTransportTrace"] = {"status": "verified-present-file", "path": str(compressed_trace),
            "compressedSha256": sha(compressed), "uncompressedSha256": artifacts["transportTrace"]["sha256"]}
    archive = json.loads(gzip.decompress(artifact_bytes["sourceArchive"]))
    require(archive["format"] == "base64-file-map-v1", "Unexpected source archive format")
    sources = {}
    archived_index = []
    for item in archive["files"]:
        require(item["path"] not in sources, "Duplicate archived source name")
        data = base64.b64decode(item["contentBase64"], validate=True)
        require(sha(data) == item["sha256"] and len(data) == item["bytes"], "Archived source hash/size mismatch")
        sources[item["path"]] = data
        archived_index.append({key: item[key] for key in ["path", "sha256", "bytes"]})
    require(archived_index == artifacts["sourceArchive"]["files"], "Source archive index mismatch")
    for name, pin in [("actor.mo", "actorSha256"), ("runner.mjs", "runnerSha256"),
                      ("build.json", "buildManifestSha256"), ("fixtures.json", "fixturesSha256")]:
        require(sha(sources[name]) == provenance[pin], f"Archived provenance mismatch: {name}")
    build_path = report_path.parent / "build.json"
    build_bytes = checked_file(build_path, provenance["buildManifestSha256"])
    require(build_bytes == sources["build.json"], "Archived and actual build manifests differ")
    build = json.loads(build_bytes)
    require(build["complete"] is True and build["expected_case_count"] == 1 and len(build["cases"]) == 1,
            "Require one completed standard build case")
    case = build["cases"][0]
    require(case["returncode"] == 0 and case["source"] == "prepared/ml-dsa/memory/main.mo"
            and case["plugins"] == ["ml-dsa"], "Unexpected built actor")
    require(case["wasm_sha256"] == provenance["wasmSha256"]
            and case["source_sha256"] == provenance["actorSha256"]
            and build["compiler_sha256"] == provenance["compilerSha256"], "Build pins differ from run")
    verified_artifacts["buildManifest"] = {"status": "verified-present-file", "path": str(build_path), "sha256": sha(build_bytes)}
    fixtures = json.loads(sources["fixtures.json"])
    selected = [item for item in fixtures["sigGen"] if item["tcId"] == provenance["fixtureTcId"]]
    require(len(selected) == 1 and selected[0]["deterministic"] is True
            and sha(bytes.fromhex(selected[0]["signature"])) == provenance["expectedSignatureSha256"],
            "External signature fixture mismatch")

    samples = report["samples"]
    require(len(samples) == 9 and len({s["canisterId"] for s in samples}) == 9, "Require nine distinct canisters")
    indexed = {}
    absolute_failures = []
    expected_oracles = ["configured", "retained-after-gc", "dropped", "dropped-after-gc"]
    counters = ["heapOccupiedBytes", "totalAllocationBytes", "reclaimedBytes", "maxObservedPostGcHeapBytes",
                "wasmMemoryBytes", "collectorInstructions", "mutatorInstructions", "rootCount", "configuredCount",
                "mode", "phase", "allocationMinusReclaimedBytes", "evacuationCopiesBytes"]
    for sample in samples:
        trial, mode = integer(sample["trial"], "trial"), integer(sample["mode"], "mode")
        require(trial < trials and mode < 3 and (trial, mode) not in indexed, "Duplicate or invalid trial/mode")
        indexed[trial, mode] = sample
        require(sample["name"] == protocol["modes"][mode] and sample["executionComplete"] is True
                and sample["qualified"] is False and sample["status"] == "incomplete-needs-investigation"
                and "error" not in sample and "cleanupError" not in sample, "Sample incomplete or failed")
        require(sample["verifications"] == [{"label": label, "correct": True} for label in expected_oracles],
                "Missing or unsuccessful correctness oracle")
        expected_labels = ["installed", "configured"]
        for stage in ["retained", "dropped"]:
            if stage == "dropped":
                expected_labels.append("dropped")
            expected_labels.extend(f"{stage}/pressure/{i}" for i in range(1, 5))
            expected_labels.extend(f"{stage}/gc/{i}" for i in range(1, 25))
        require([x["label"] for x in sample["snapshots"]] == expected_labels, "Snapshot schedule mismatch")
        points = {point["label"]: point for point in sample["snapshots"]}
        for label, point in points.items():
            for field in counters:
                integer(point[field], f"{trial}/{mode}/{label}/{field}")
            require(point["allocationMinusReclaimedBytes"] == point["totalAllocationBytes"] - point["reclaimedBytes"]
                    and point["evacuationCopiesBytes"] == point["heapOccupiedBytes"] - point["allocationMinusReclaimedBytes"],
                    "Derived counter mismatch")
            phase = 0 if label == "installed" else 2 if label.startswith("dropped") else 1
            require(point["phase"] == phase and point["mode"] == (0 if phase == 0 else mode)
                    and point["configuredCount"] == (0 if phase == 0 else count)
                    and point["rootCount"] == (count if phase == 1 and mode else 0), "Root/phase/mode mismatch")
        configured_allocation = points["configured"]["totalAllocationBytes"] - points["installed"]["totalAllocationBytes"]
        require(configured_allocation == sample["configureAllocatedBytes"]
                and sample["minimumPreparedPayloadAllocationBytes"] == count * protocol["preparedPayloadBytes"][mode]
                and configured_allocation >= sample["minimumPreparedPayloadAllocationBytes"], "Configuration allocation mismatch")
        require([stage["name"] for stage in sample["stages"]] == ["retained", "dropped"], "Stage order mismatch")
        for stage in sample["stages"]:
            name = stage["name"]
            require(stage["beforeLabel"] == ("configured" if name == "retained" else "dropped"), "Stage starting point mismatch")
            for kind, length in [("pressure", 4), ("gc", 24)]:
                require(stage[kind] == [points[f"{name}/{kind}/{i}"] for i in range(1, length + 1)], "Duplicated stage snapshots disagree")
            reclaimed = stage["gc"][-1]["reclaimedBytes"] - points[stage["beforeLabel"]]["reclaimedBytes"]
            require(reclaimed == stage["reclaimedDuringStageBytes"] and reclaimed >= 64 * 1024 * 1024, "Insufficient stage reclamation")
            require(all(point["evacuationCopiesBytes"] == 0 for point in stage["gc"]), "Active evacuation copies in GC series")
            previous = stage["pressure"][-1]
            for point in stage["gc"]:
                require(point["totalAllocationBytes"] - previous["totalAllocationBytes"] == expected_step,
                        "GC allocation increment disagrees with source-derived fixed cost")
                previous = point
            tail = stage["gc"][-8:]
            require(max(x["heapOccupiedBytes"] for x in tail) - min(x["heapOccupiedBytes"] for x in tail) > 4096,
                    "Original absolute protocol failure changed")
            require(stage["criteria"] == {"meaningfulReclamation": True, "boundedTailHeapSpread": False,
                                          "zeroEvacuationCopiesInTail": True} and stage["qualified"] is False,
                    "Unexpected original stage qualification")
            absolute_failures.append({"trial": trial, "mode": mode, "stage": name,
                                      "originalCriteria": stage["criteria"], "rawTail": stage["tail"]})

    comparisons = []
    for trial in range(trials):
        baseline = indexed[trial, 0]
        for mode in [1, 2]:
            sample = indexed[trial, mode]
            stages = []
            for stage, control in zip(sample["stages"], baseline["stages"]):
                deltas = []
                prior, prior_control = stage["pressure"][-1], control["pressure"][-1]
                for point, other in zip(stage["gc"], control["gc"]):
                    require(point["label"] == other["label"], "Pairing label mismatch")
                    require(point["totalAllocationBytes"] - prior["totalAllocationBytes"]
                            == other["totalAllocationBytes"] - prior_control["totalAllocationBytes"], "Unmatched GC allocation step")
                    delta = point["heapOccupiedBytes"] - other["heapOccupiedBytes"]
                    require(delta == point["allocationMinusReclaimedBytes"] - other["allocationMinusReclaimedBytes"],
                            "Paired allocation/reclamation identity failed")
                    deltas.append({"label": point["label"], "heapOverheadBytes": delta})
                    prior, prior_control = point, other
                values = [item["heapOverheadBytes"] for item in deltas]
                require(len(set(values)) == 1, "Paired heap overhead is not constant over all 24 indices")
                if stage["name"] == "dropped":
                    require(max(abs(value) for value in values) == 0, "Nonzero observed residual after drop")
                else:
                    require(values[0] > 0, "Missing retained prepared-key overhead")
                before = next(x for x in sample["snapshots"] if x["label"] == stage["beforeLabel"])
                control_before = next(x for x in baseline["snapshots"] if x["label"] == control["beforeLabel"])
                start_excess = before["heapOccupiedBytes"] - control_before["heapOccupiedBytes"]
                allocation_excess = ((stage["gc"][-1]["totalAllocationBytes"] - before["totalAllocationBytes"])
                                     - (control["gc"][-1]["totalAllocationBytes"] - control_before["totalAllocationBytes"]))
                reclaim_excess = stage["reclaimedDuringStageBytes"] - control["reclaimedDuringStageBytes"]
                require(start_excess + allocation_excess - reclaim_excess == values[-1], "Stage conservation check failed")
                stages.append({"name": stage["name"], "pairedPoints": deltas, "heapOverheadBytes": summary(values),
                               "allocationConservation": {"startingHeapExcessBytes": start_excess,
                                  "stageAllocationExcessBytes": allocation_excess, "stageReclamationExcessBytes": reclaim_excess,
                                  "endingHeapExcessBytes": values[-1]}})
            retained, dropped = [stage["heapOverheadBytes"]["min"] for stage in stages]
            allocation_changes, reclamation_changes, heap_changes = [], [], []
            for index in range(24):
                retained_point, dropped_point = [stage["gc"][index] for stage in sample["stages"]]
                control_retained, control_dropped = [stage["gc"][index] for stage in baseline["stages"]]
                allocation_change = ((dropped_point["totalAllocationBytes"] - retained_point["totalAllocationBytes"])
                                     - (control_dropped["totalAllocationBytes"] - control_retained["totalAllocationBytes"]))
                reclamation_change = ((dropped_point["reclaimedBytes"] - retained_point["reclaimedBytes"])
                                      - (control_dropped["reclaimedBytes"] - control_retained["reclaimedBytes"]))
                heap_change = ((dropped_point["heapOccupiedBytes"] - control_dropped["heapOccupiedBytes"])
                               - (retained_point["heapOccupiedBytes"] - control_retained["heapOccupiedBytes"]))
                require(allocation_change - reclamation_change == heap_change,
                        "Matched retained-to-dropped allocation/reclamation identity failed")
                allocation_changes.append(allocation_change)
                reclamation_changes.append(reclamation_change)
                heap_changes.append(heap_change)
            comparisons.append({"trial": trial, "mode": mode, "name": protocol["modes"][mode], "stages": stages,
                                "retainedHeapOverheadBytes": retained, "dropResidualBytes": dropped,
                                "recoveredHeapOverheadBytes": retained - dropped,
                                "observedHeapOverheadBytesPerKey": retained / count,
                                "retainedToDroppedConservation": {"matchingIndicesChecked": 24,
                                    "allocationExcessChangeBytes": summary(allocation_changes),
                                    "reclamationExcessChangeBytes": summary(reclamation_changes),
                                    "heapOverheadChangeBytes": summary(heap_changes)}})
    for mode in [1, 2]:
        require(len({c["retainedHeapOverheadBytes"] for c in comparisons if c["mode"] == mode}) == 1,
                "Paired overhead differs across deterministic trials")
    return {
        "format": "ml-dsa-paired-memory-analysis-v1", "status": "post-hoc-observed-paired-heap-overhead",
        "postHoc": True, "pairedChecksPassed": True, "originalProtocolPassed": False,
        "interpretation": "Observed paired heap overhead under the fixed allocation/GC schedule. "
            "All 24 matching indices are checked before computing summaries; no absolute-heap threshold is relaxed. "
            "Source-derived common allocation is verified against measured increments, not fitted or subtracted as a trend. "
            "Present artifacts are hash-verified; missing optional Wasm/full-build artifacts are explicitly recorded, not claimed verified. "
            "This is not exact live memory, proof of completed GC, or proof of secure erasure. "
            "Samples within each trial are correlated; three deterministic trials show reproducibility, not statistical confidence.",
        "inputs": {"report": {"path": str(report_path), "sha256": sha(raw)},
                   "sourceEvidence": {"path": str(evidence_path), "sha256": sha(evidence_bytes)},
                   "analyzer": {"path": str(Path(__file__).resolve()), "sha256": sha(Path(__file__).read_bytes())},
                   "runProvenance": provenance, "verifiedArtifacts": verified_artifacts},
        "checks": {"distinctCanisters": 9, "correctnessOracles": 36, "snapshots": 531,
                   "gcPointsPerStage": 24, "minimumStageReclaimedBytes": 64 * 1024 * 1024,
                   "gcAllocationIncrementBytes": expected_step, "zeroCopyBytesAtEveryGcPoint": True,
                   "constantPairedOverheadAtEveryGcPoint": True, "maximumAbsoluteDropResidualBytes": 0},
        "originalAbsoluteQualification": {"complete": report["complete"], "status": report["status"],
                                          "stageFailures": absolute_failures},
        "comparisons": comparisons,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--source-evidence", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    result = analyze(args.report.resolve(), args.source_evidence.resolve())
    # Exclusive creation preserves both the original report and earlier analyses.
    with args.out.open("x") as output:
        json.dump(result, output, indent=2)
        output.write("\n")


if __name__ == "__main__":
    main()
