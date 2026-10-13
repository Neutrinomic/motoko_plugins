#!/usr/bin/env python3
"""Rehash paired evidence and independently recompute all published BLS deltas."""
import argparse
import hashlib
import json
import math
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
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stages", type=Path, required=True)
    p.add_argument("--comparison", type=Path, action="append", required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    args.stages = args.stages.resolve()
    here = Path(__file__).resolve().parent
    audit = read(here / "report.json")
    stages = {}
    reviews = []

    def load_stage(info):
        name = info["stage"]
        if name in stages:
            assert info == stages[name]["info"]
            return stages[name]
        path = args.stages / name
        build, result = read(path / "build.json"), read(path / "results.json")
        assert sha(path / "build.json") == info["build_sha256"] == result["build_sha256"]
        assert sha(path / "results.json") == info["results_sha256"]
        assert build["complete"] and result["complete"] and result["failed_measurements"] == 0
        assert result["trials"] == 3 and "fatal_error" not in result
        pins = build["frozen_inputs_sha256"]
        frozen = path / "inputs"
        for rel, expected in pins.items():
            assert sha(frozen / rel) == expected, (name, rel)
        env = info["environment"]
        assert env["compiler_sha256"] == build["compiler_sha256"] == audit["compiler_sha256"] == pins["toolchain/moc"]
        assert env["runner_sha256"] == build["runner_sha256"] == result["runner_sha256"] == pins["benchmarks/crypto/prepared/run.mjs"]
        assert env["pocket_ic_sha256"] == result["pocket_ic_sha256"] == "6303d3418bb20eb3b67e21cecbe68cc450b08dcbf2ec0896d831da4ccca6a990"
        assert env["runner_dependencies_sha256"] == result["runner_dependencies_sha256"] == digest(result["runner_dependencies"])
        for prefix, key in [("benchmarks/crypto/dependencies/", "motoko_dependencies_sha256"),
                            ("packages/fast/src/", "fast_package_sha256")]:
            assert digest({k: v for k, v in pins.items() if k.startswith(prefix)}) == env[key]
        assert env["dependency_aliases"] == build["dependency_aliases"]
        for filename, key, expected in [
            ("mo-rts.wasm", "MOC_RELEASE_RTS", "8456e47e527bbd584ee2d5d867b0c93f5596d2bcdaa87bba53c04281562c820f"),
            ("mo-rts-debug.wasm", "MOC_DEBUG_RTS", "f87c1f4a8b15e6e5949f618195cd303bd0d07fc85f1f73e9f0a244eacecb24c9")]:
            assert pins["toolchain/" + filename] == env["rts_sha256"][key] == expected
        plugin_path = frozen / "dist/bls12-381"
        plugin = read(plugin_path / "build.json")
        plugin_info = info["plugins"]["bls12-381"]
        assert sha(plugin_path / "build.json") == plugin_info["build_sha256"]
        assert plugin_info["pins"] == {"artifacts": plugin["sha256"], "sources": plugin["source_sha256"]}
        for rel, expected in plugin["source_sha256"].items():
            assert pins["plugin-build-inputs/bls12-381/" + rel] == expected
        for rel, expected in plugin["sha256"].items():
            assert pins["dist/bls12-381/" + rel] == expected
        final_artifact = plugin["sha256"]["runtime.wasm"] == audit["artifacts_sha256"]["runtime.wasm"]
        if final_artifact:
            for rel, expected in audit["artifacts_sha256"].items():
                assert sha(plugin_path / rel) == expected
            assert pins["packages/fast/src/BLS12381.mo"] == sha(here.parents[3] / "packages/fast/src/BLS12381.mo")
        cases = {c["name"]: c for c in result["cases"]}
        assert len(cases) == len(build["cases"]) == build["expected_case_count"] == result["expected_case_count"]
        summaries = {}
        for b in build["cases"]:
            c = cases[b["name"]]
            assert {k: v for k, v in b.items() if k != "command"} == {k: v for k, v in c.items() if k != "measurements"}
            assert c["returncode"] == 0 and c["operations_per_sample"] == 1
            assert sha(path / c["wasm"]) == c["wasm_sha256"]
            assert (path / c["wasm"]).stat().st_size == c["wasm_bytes"]
            assert sha(frozen / "benchmarks/crypto" / c["source"]) == c["source_sha256"]
            assert sha(frozen / "benchmarks/crypto" / c["prepared"]["fixture_source"]) == c["prepared"]["fixture_sha256"]
            assert c["expected_hex"] == "01"
            samples = c["measurements"]
            assert len(samples) == 3 and sorted(m["trial"] for m in samples) == [0, 1, 2]
            for m in samples:
                assert m["correct"] is True and "error" not in m
                assert m["output_bytes"] == 1 and m["output_sha256"] == hashlib.sha256(b"\x01").hexdigest()
                assert m["reclaimed_bytes"] == 0
                for snap in m["memory"].values():
                    assert snap["reclaimed_bytes"] == 0 and snap["wasm_capacity_bytes"] == 134217728
            computed = {k: stats([m[k] for m in samples]) for k in ("instructions", "allocated_bytes", "reclaimed_bytes")}
            computed["memory"] = {phase: {key: stats([m["memory"][phase][key] for m in samples])
                                         for key in samples[0]["memory"][phase]}
                                  for phase in samples[0]["memory"]}
            assert all(computed[key]["range"][0] == computed[key]["range"][1] for key in ("instructions", "allocated_bytes"))
            computed.update({key: c[key] for key in ("source", "source_sha256", "wasm_sha256", "wasm_bytes")})
            computed["payload_bytes"] = c["prepared"]["payload_bytes"]
            computed["runtime_wasm_bytes"] = {"bls12-381": (plugin_path / "runtime.wasm").stat().st_size}
            summaries[c["name"]] = computed
        checked = {"name": name, "path": str(path), "info": info, "build": build,
                   "cases": cases, "summaries": summaries, "frozen_files": len(pins),
                   "observations": len(cases) * 3, "final_artifact": final_artifact}
        stages[name] = checked
        return checked

    for comparison_path in args.comparison:
        comparison = read(comparison_path)
        assert comparison["target_plugin"] == "bls12-381" and comparison["trials_per_case_per_revision"] == 3
        baseline, candidate = [load_stage(comparison[side]) for side in ("baseline", "candidate")]
        assert baseline["info"]["environment"] == candidate["info"]["environment"]
        assert baseline["info"]["actor_sources"] == candidate["info"]["actor_sources"]
        assert baseline["info"]["builder_sha256"] == candidate["info"]["builder_sha256"]
        assert baseline["cases"].keys() == candidate["cases"].keys()
        assert len(comparison["cases"]) == comparison["case_count"] == len(baseline["cases"])
        rows = []
        for row in comparison["cases"]:
            name = row["name"]
            a, b = baseline["cases"][name], candidate["cases"][name]
            for key in ("source_sha256", "prepared", "expected_hex", "operations_per_sample"):
                assert a[key] == b[key], (name, key)
            for side, checked in (("baseline", baseline), ("candidate", candidate)):
                command = next(c["command"] for c in checked["build"]["cases"] if c["name"] == name)
                normalized = ["<moc>"] + [arg.replace(checked["path"], "<stage>") for arg in command[1:]]
                assert row["normalized_command"] == normalized
                for key, expected in checked["summaries"][name].items():
                    assert row[side][key] == expected, (name, side, key)
            changes = {}
            for key in ("instructions", "allocated_bytes", "reclaimed_bytes", "wasm_bytes", "payload_bytes"):
                values = [row[side][key]["median"] if isinstance(row[side][key], dict) else row[side][key]
                          for side in ("baseline", "candidate")]
                old, new = values
                change = row["change"][key]
                assert change["delta"] == new - old
                saving = 100 * (old - new) / old if old else None
                assert (change["saving_percent"] is None if saving is None else math.isclose(change["saving_percent"], saving, abs_tol=1e-12))
                if "speedup" in change:
                    assert math.isclose(change["speedup"], old / new)
                changes[key] = {"baseline": old, "candidate": new, "delta": new - old,
                                "saving_percent": None if saving is None else round(saving, 6)}
            rows.append({"name": name, "mode": a["prepared"]["mode"], "changes": changes})
        reviews.append({"comparison": str(comparison_path), "sha256": sha(comparison_path),
                        "baseline": baseline["name"], "candidate": candidate["name"], "rows": rows})
    owner = args.comparison[0].parent
    final_manifest = read(owner / "validation/final.json")
    assert final_manifest["production_commit"] == audit["production_commit"]
    assert final_manifest["runtime_sha256"] == audit["artifacts_sha256"]["runtime.wasm"]
    assert final_manifest["compiler_sha256"] == audit["compiler_sha256"]
    assert set(final_manifest["stages"]) == set(stages)
    for stage_name, files in final_manifest["stages"].items():
        for rel, expected in files.items():
            assert sha(args.stages / stage_name / rel) == expected
    for key in ("comparison_sha256", "incremental_sha256", "manifest_sha256", "final_log_sha256"):
        directory = owner / "validation" if key == "final_log_sha256" else owner
        for rel, expected in final_manifest[key].items():
            assert sha(directory / rel) == expected
    observations = sum(s["observations"] for s in stages.values())
    final_paired = 2 * sum(s["observations"] for s in stages.values() if s["final_artifact"])
    assert final_manifest["total_observations"] == observations == 144
    assert final_manifest["final_paired_observations"] == final_paired == 90
    report = {"status": "pass", "production_commit": audit["production_commit"],
              "owner_readme_sha256": sha(owner / "README.md"),
              "owner_final_manifest_sha256": sha(owner / "validation/final.json"),
              "comparisons": reviews,
              "stages": [{"name": s["name"], "frozen_files": s["frozen_files"],
                          "wasm_artifacts": len(s["cases"]), "observations": s["observations"],
                          "matches_audited_final_artifact": s["final_artifact"]} for s in stages.values()],
              "observations_verified": observations, "final_paired_observations": final_paired,
              "frozen_files_rehashed": sum(s["frozen_files"] for s in stages.values()),
              "wasm_artifacts_rehashed": sum(len(s["cases"]) for s in stages.values()),
              "limitations": ["All reclaimed-byte counters are zero; snapshots describe occupied heap, not retained live heap or peaks.",
                              "Prepared payload sizes are unchanged and exclude managed headers. Reduced temporary allocation is not a reduction in retained key payload.",
                              "Preparation rows execute their declared number of factories, including required PoP verification. Hot prepared rows exclude separately measured setup."]}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(stages)} stages, {report['observations_verified']} observations, {report['wasm_artifacts_rehashed']} Wasms; all paired statistics and deltas match.")


if __name__ == "__main__":
    main()
