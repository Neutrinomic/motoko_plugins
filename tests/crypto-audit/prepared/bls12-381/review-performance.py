#!/usr/bin/env python3
"""Independently check saved BLS measurements; no compilation or crypto execution."""
import argparse
import hashlib
import json
import re
import statistics
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode()).hexdigest()


def stats(values):
    return {"median": statistics.median(values), "range": [min(values), max(values)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    lane = here.parents[3]
    owner = lane / "benchmarks/crypto/prepared/bls12-381"
    stage = args.stage.resolve()
    frozen = stage / "inputs"
    build, results = read(stage / "build.json"), read(stage / "results.json")
    summary = read(owner / "summary.json")
    validation = read(owner / "validation/benchmark.json")
    audit = read(here / "report.json")
    assert audit["status"] == "pass"
    hashes = {"build.json": sha(stage / "build.json"),
              "results.json": sha(stage / "results.json"),
              "summary.json": sha(owner / "summary.json")}
    for name, value in hashes.items():
        assert value == validation[name.removesuffix(".json") + "_sha256"]
    for name, value in validation["logs_sha256"].items():
        assert sha(owner / "validation" / name) == value
    assert results["build_sha256"] == hashes["build.json"]
    assert build["complete"] is True and results["complete"] is True
    assert build["expected_case_count"] == results["expected_case_count"] == 24
    assert summary["case_count"] == 24 and len(summary["groups"]) == 8
    assert results["trials"] == summary["trials"] == 3
    assert results["failed_measurements"] == 0 and "fatal_error" not in results
    pins = build["frozen_inputs_sha256"]
    for name, value in pins.items():
        assert sha(frozen / name) == value, name
    assert pins["toolchain/moc"] == build["compiler_sha256"] == audit["compiler_sha256"]
    assert sha(Path(build["cases"][0]["command"][0])) == audit["compiler_sha256"]
    for name, value in audit["artifacts_sha256"].items():
        assert pins["dist/bls12-381/" + name] == value
        assert sha(lane / "dist/bls12-381" / name) == value
    for name, value in audit["source_sha256"].items():
        prefix = "" if name.startswith("packages/") else "plugin-build-inputs/bls12-381/"
        assert pins[prefix + name] == value, name
        assert sha(lane / name) == value, name
    plugin = read(frozen / "dist/bls12-381/build.json")
    assert plugin["moc_sha256"] == audit["compiler_sha256"]
    for name, value in plugin["source_sha256"].items():
        assert pins["plugin-build-inputs/bls12-381/" + name] == value
    toolchain = summary["runs"][0]["toolchain"]
    assert len(summary["runs"]) == 1
    assert summary["runs"][0]["build_sha256"] == hashes["build.json"]
    assert summary["runs"][0]["results_sha256"] == hashes["results.json"]
    assert toolchain["compiler_sha256"] == audit["compiler_sha256"]
    assert toolchain["runner_sha256"] == build["runner_sha256"] == results["runner_sha256"]
    assert pins["benchmarks/crypto/prepared/run.mjs"] == results["runner_sha256"]
    assert toolchain["pocket_ic_sha256"] == results["pocket_ic_sha256"]
    assert sha(Path("/home/devbox/.local/bin/pocket-ic")) == results["pocket_ic_sha256"]
    assert digest(results["runner_dependencies"]) == results["runner_dependencies_sha256"]
    assert toolchain["runner_dependencies_sha256"] == results["runner_dependencies_sha256"]
    dependency_root = Path("/srv/shared/code/candidx/ts")
    assert sha(dependency_root / "package-lock.json") == results["runner_dependencies"]["package_lock_sha256"]
    for name, value in results["runner_dependencies"]["modules_sha256"].items():
        assert sha(dependency_root / name) == value
    for prefix, key in [("benchmarks/crypto/dependencies/", "motoko_dependencies_sha256"),
                        ("packages/fast/src/", "fast_package_sha256")]:
        assert digest({k: v for k, v in pins.items() if k.startswith(prefix)}) == toolchain[key]
    assert toolchain["dependency_aliases"] == build["dependency_aliases"]
    for name, path in build["rts_environment"].items():
        assert sha(Path(path)) == toolchain["rts_sha256"][name]
    fixtures_path = frozen / "benchmarks/crypto/prepared/bls12-381/fixtures.json"
    fixtures = {f["id"]: f for f in read(fixtures_path)["fixtures"]}
    assert len(fixtures) == 8
    cases = {c["name"]: c for c in results["cases"]}
    assert len(cases) == len(results["cases"]) == len(build["cases"]) == 24
    case_stats = {}
    for b in build["cases"]:
        c = cases[b["name"]]
        assert {k: v for k, v in b.items() if k != "command"} == {
            k: v for k, v in c.items() if k != "measurements"}
        assert b["command"][:-3] == build["cases"][0]["command"][:-3]
        assert b["command"][-3] == str(frozen / "benchmarks/crypto" / b["source"])
        assert b["command"][-2:] == ["-o", str(stage / b["wasm"])]
        assert b["returncode"] == 0 and b["operations_per_sample"] == 1
        assert sha(stage / b["wasm"]) == b["wasm_sha256"]
        assert (stage / b["wasm"]).stat().st_size == b["wasm_bytes"]
        source = frozen / "benchmarks/crypto" / b["source"]
        assert sha(source) == b["source_sha256"]
        assert sha(lane / "benchmarks/crypto" / b["source"]) == b["source_sha256"]
        meta = b["prepared"]
        assert meta["fixture_sha256"] == sha(fixtures_path)
        fixture = fixtures[meta["fixture"]]
        assert fixture["expected"] == {"ok_bool": True} and b["expected_hex"] == "01"
        assert fixture["operation"] == meta["operation"] and fixture["profile"] == meta["profile"]
        # Independently inspect actual actor inputs and placement of factories/calls.
        source_text = source.read_text()
        for name, value in fixture["inputs"].items():
            values = value if isinstance(value, list) else [value]
            blobs = ['"' + ''.join('\\%02x' % byte for byte in bytes.fromhex(x)) + '"' for x in values]
            declaration = ("[Blob] = [" + ", ".join(blobs) + "];" if isinstance(value, list)
                           else "Blob = " + blobs[0] + ";")
            assert "transient let " + name + " : " + declaration in source_text
        timed = source_text.split("let start = Prim.performanceCounter(0);", 1)[1].split("let stop =", 1)[0]
        setup = source_text.split("public func configure()", 1)[1].split("public func run()", 1)[0]
        oracle = source_text.split("public query func bytesResult()", 1)[1]
        count = len(fixture["inputs"].get("keys", [None]))
        created = 1 if fixture.get("share_repeated_key", False) else count
        factory_pattern = r"B\.prepare(?:ICPublicKey|EthereumPublicKey|EthereumPoPKey)\("
        actual_factory_count = len(re.findall(factory_pattern, source_text))
        if meta["mode"] == "direct":
            assert actual_factory_count == meta["prepared_key_count"] == meta["payload_bytes"] == 0
            assert "B." + fixture["operation"] + "(" in timed
        else:
            assert actual_factory_count == meta["prepared_key_count"] == created
            assert meta["payload_bytes"] == created * (19680 if meta["profile"] == "IC" else 144)
            factory_body = timed if meta["mode"] == "prepare" else setup
            assert len(re.findall(factory_pattern, factory_body)) == created
            verify_body = oracle if meta["mode"] == "prepare" else timed
            assert "B." + fixture["operation"] + "Prepared(" in verify_body
            if count > 1:
                references = ["key0"] * count if fixture.get("share_repeated_key", False) else ["key" + str(i) for i in range(count)]
                assert "preparedKeys := [" + ", ".join(references) + "];" in factory_body
        assert meta["key_references"] == count
        samples = c["measurements"]
        assert len(samples) == 3 and sorted(m["trial"] for m in samples) == [0, 1, 2]
        for m in samples:
            assert m["correct"] is True and "error" not in m
            assert m["output_bytes"] == 1 and m["output_sha256"] == hashlib.sha256(b"\x01").hexdigest()
            assert m["reclaimed_bytes"] == 0
            for snap in m["memory"].values():
                assert snap["reclaimed_bytes"] == 0 and snap["wasm_capacity_bytes"] == 134217728
        measured = {k: stats([m[k] for m in samples]) for k in ("instructions", "allocated_bytes", "reclaimed_bytes")}
        measured["memory"] = {phase: {key: stats([m["memory"][phase][key] for m in samples])
                                     for key in samples[0]["memory"][phase]}
                              for phase in samples[0]["memory"]}
        for key in ("instructions", "allocated_bytes"):
            assert measured[key]["range"][0] == measured[key]["range"][1]
        case_stats[c["name"]] = measured
    rows = []
    for group in summary["groups"]:
        assert group["toolchain"] == toolchain
        assert group["plugin_pins"] == {"bls12-381": {"artifacts": plugin["sha256"], "sources": plugin["source_sha256"]}}
        assert group["actual_batches"] == []
        for mode in ("direct", "prepare", "prepared"):
            entry = group[mode]
            c = cases[entry["name"]]
            assert c["prepared"]["comparison_group"] == group["comparison_group"]
            for key in ("source", "source_sha256", "wasm_sha256", "wasm_bytes"):
                assert entry[key] == c[key]
            for key, value in case_stats[entry["name"]].items():
                assert entry[key] == value
        d, p, h = [group[mode]["instructions"]["median"] for mode in ("direct", "prepare", "prepared")]
        assert d > h
        first = p // (d - h) + 1
        assert group["strict_instruction_break_even_reuses"] == first
        assert [m["reuse"] for m in group["models"]] == [1, 2, 10, 100]
        for model in group["models"]:
            assert model["direct_instructions"] == model["reuse"] * d
            assert model["prepared_instructions"] == p + model["reuse"] * h
        meta = cases[group["prepared"]["name"]]["prepared"]
        rows.append({"group": group["comparison_group"], "direct_instructions": d,
                     "preparation_instructions": p, "prepared_instructions": h,
                     "reduction_percent": round(100 * (d - h) / d, 2),
                     "first_cheaper_use_modeled": first,
                     "direct_allocated_bytes": group["direct"]["allocated_bytes"]["median"],
                     "prepared_allocated_bytes": group["prepared"]["allocated_bytes"]["median"],
                     "created_values": meta["prepared_key_count"], "key_references": meta["key_references"],
                     "payload_bytes": meta["payload_bytes"],
                     "prepared_minus_direct_wasm_bytes": group["prepared"]["wasm_bytes"] - group["direct"]["wasm_bytes"]})
    shared, separate = [fixtures["aggregate-ethereum-repeated-n8" + suffix] for suffix in ("", "-separate")]
    assert shared["inputs"] == separate["inputs"]
    assert shared["share_repeated_key"] is True and separate["share_repeated_key"] is False
    review = {"status": "pass", "production_commit": audit["production_commit"],
              "stage": str(stage), "evidence_sha256": hashes,
              "compiler_sha256": audit["compiler_sha256"], "artifacts_sha256": audit["artifacts_sha256"],
              "frozen_files_rehashed": len(pins), "production_sources_matched": len(audit["source_sha256"]),
              "wasm_files_rehashed": 24, "observations_verified": 72, "comparison_groups": rows,
              "interpretation": [
                  "Direct and prepared controls share the exact audited runtime, compiler, module, RTS and dependencies, including the improved direct generator table.",
                  "Preparation includes its mandatory PoP work; only the output oracle is untimed. Prepared verification excludes setup, which has its own measured row.",
                  "One prepared token referenced eight times and eight separately prepared equal tokens have identical cryptographic inputs but different factory and retained payload counts.",
                  "Break-even and N=1/2/10/100 figures are arithmetic projections, not executed multi-use batches.",
                  "All benchmark reclamation counters are zero. Sampled heap is occupied heap, not live or peak; payload excludes managed overhead.",
                  "Actual collection is proved separately by the retained-key Ash test, with reclamation greater than 4 MiB; exact delta was not logged.",
                  "The frozen cohort metadata has an obsolete seven-fixture/shared-only sentence; the owner corrected current prose without altering measured actors or this immutable stage."],
              "approval": "Correctness-gated prepared BLS performance and report interpretation approved; no production findings."}
    args.output.write_text(json.dumps(review, indent=2) + "\n")
    print(f"PASS: {len(pins)} frozen files, 24 Wasm artifacts, 72 observations, 8 groups; all statistics and models match.")


if __name__ == "__main__":
    main()
