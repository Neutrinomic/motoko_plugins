#!/usr/bin/env python3
"""Compare two frozen cohorts differing only in the selected plugin implementation."""
import argparse
import importlib.util
import json
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("prepared_summary", Path(__file__).parent.parent / "prepared/summarize.py")
PREPARED = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARED)
require = PREPARED.require
BUILDER = "benchmarks/crypto/prepared/build.py"


def normalized_command(build, case):
    command = case["command"]
    require(isinstance(command, list) and command and all(isinstance(x, str) for x in command),
            "Invalid recorded compiler command")
    require(build["inputs_sha256"].get(command[0]) == build["compiler_sha256"], "Unpinned compiler executable")
    release = Path(build["rts_environment"]["MOC_RELEASE_RTS"])
    stage = release.parents[2]
    require(release == stage / "inputs/toolchain/mo-rts.wasm"
            and Path(build["rts_environment"]["MOC_DEBUG_RTS"]) == stage / "inputs/toolchain/mo-rts-debug.wasm",
            "Unexpected recorded RTS paths")
    return ["<moc>"] + ["<stage>/" + Path(arg).relative_to(stage).as_posix()
                        if Path(arg).is_absolute() and Path(arg).is_relative_to(stage) else arg
                        for arg in command[1:]]


def read_side(directory):
    directory = Path(directory)
    provenance, environment, cases = PREPARED.read_run(directory)
    build = json.loads((directory / "build.json").read_text())
    require(PREPARED.sha(directory / "build.json") == provenance["build_sha256"], "Build changed during comparison")
    pins = build["frozen_inputs_sha256"]
    require(BUILDER in pins, "Missing frozen builder")
    # Includes source-local imports, not merely each actor's main.mo. Dependency
    # and mo:fast closures are independently covered by the shared environment.
    actors = {name: pin for name, pin in pins.items() if name.startswith("benchmarks/crypto/")
              and not name.startswith("benchmarks/crypto/dependencies/") and name.endswith(".mo")}
    plugins = {}
    for case in cases:
        for plugin, plugin_pins in case["plugin_pins"].items():
            if plugin in plugins:
                continue
            prefix = "dist/" + plugin + "/"
            metadata = json.loads((directory / "inputs" / prefix / "build.json").read_text())
            plugins[plugin] = {
                "build_sha256": pins[prefix + "build.json"], "pins": plugin_pins,
                "runtime_wasm_bytes": (directory / "inputs" / prefix / "runtime.wasm").stat().st_size,
                "build_metadata": {k: v for k, v in metadata.items() if k not in ("sha256", "source_sha256")},
            }
    info = {**provenance, "plugins": plugins, "environment": environment,
            "builder_sha256": pins[BUILDER], "actor_sources": actors}
    compiled = {PREPARED.key(case): case for case in build["cases"]}
    rows = {PREPARED.key(case): {**case, "stage": provenance["stage"],
                                "normalized_command": normalized_command(build, compiled[PREPARED.key(case)])} for case in cases}
    return info, rows


def change(baseline, candidate):
    return {"delta": candidate - baseline,
            "saving_percent": (baseline - candidate) * 100 / baseline if baseline else None}


def compare(baseline_directory, candidate_directory, target_plugin):
    baseline, left = read_side(baseline_directory)
    candidate, right = read_side(candidate_directory)
    require(baseline["stage"] != candidate["stage"], "Baseline and candidate must be distinct stages")
    for field in ("environment", "builder_sha256", "actor_sources"):
        require(baseline[field] == candidate[field], "Different " + field)
    require(left.keys() == right.keys(), "Different case sets; missing cases cannot be dropped")
    require(baseline["plugins"].keys() == candidate["plugins"].keys(), "Different plugin sets")
    require(target_plugin in baseline["plugins"], "Target plugin absent from cohort: " + target_plugin)
    for plugin in baseline["plugins"]:
        if plugin != target_plugin:
            require(baseline["plugins"][plugin]["pins"] == candidate["plugins"][plugin]["pins"],
                    "Different non-target plugin: " + plugin)
    rows = []
    for case_key in sorted(left):
        a, b = left[case_key], right[case_key]
        for field in ("family", "plugins", "source", "source_sha256", "expected_hex", "memory_metrics", "normalized_command"):
            require(a[field] == b[field], "Different " + field + ": " + str(case_key))
        metadata = [{k: v for k, v in case["prepared"].items() if k != "payload_bytes"} for case in (a, b)]
        for meta in metadata:
            meta.setdefault("reuse", 1)
        require(metadata[0] == metadata[1], "Different prepared metadata: " + str(case_key))
        samples = [dict(PREPARED.measured(case), runtime_wasm_bytes={
            plugin: side["plugins"][plugin]["runtime_wasm_bytes"] for plugin in case["plugins"]})
            for side, case in ((baseline, a), (candidate, b))]
        differences = {metric: change(samples[0][metric]["median"], samples[1][metric]["median"])
                       for metric in ("instructions", "allocated_bytes", "reclaimed_bytes")}
        differences["instructions"]["speedup"] = samples[0]["instructions"]["median"] / samples[1]["instructions"]["median"]
        differences.update({metric: change(samples[0][metric], samples[1][metric])
                            for metric in ("wasm_bytes", "payload_bytes")})
        rows.append({"name": a["name"], "implementation": a["implementation"], "family": a["family"],
                     "plugins": a["plugins"], "prepared": metadata[0], "expected_hex": a["expected_hex"],
                     "normalized_command": a["normalized_command"], "baseline": samples[0], "candidate": samples[1],
                     "change": differences})
    return {"protocol": "crypto-revision-comparison-v1", "measurement_protocol": PREPARED.PROTOCOL,
            "target_plugin": target_plugin, "trials_per_case_per_revision": 3, "case_count": len(rows),
            "baseline": baseline, "candidate": candidate, "cases": rows}


def markdown(report):
    lines = ["# Plugin revision comparison", "",
             f'Target: `{PREPARED.cell(report["target_plugin"])}`. Baseline: `{PREPARED.cell(report["baseline"]["stage"])}`; '
             f'candidate: `{PREPARED.cell(report["candidate"]["stage"])}`.', "",
             "Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. "
             "Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, "
             "and cold includes one factory plus N calls. No modeled costs or per-call division are used.", "",
             "| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |",
             "|---|---|---:|---:|---:|---:|"]
    for row in report["cases"]:
        a, b, delta = row["baseline"], row["candidate"], row["change"]["instructions"]
        lines.append(f'| {PREPARED.cell(row["name"])} | {a["mode"]}/{a["reuse"]} | '
                     f'{PREPARED.value_range(a["instructions"])} | {PREPARED.value_range(b["instructions"])} | '
                     f'{delta["saving_percent"]:.2f}% | {delta["speedup"]:.3f}× |')
    lines += ["", "Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. "
              "Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.", "",
              "| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |",
              "|---|---:|---:|---:|---:|"]
    for row in report["cases"]:
        a, b = row["baseline"], row["candidate"]
        runtime = [str(sample["runtime_wasm_bytes"].get(report["target_plugin"], "—")) for sample in (a, b)]
        lines.append(f'| {PREPARED.cell(row["name"])} | {PREPARED.value_range(a["allocated_bytes"])} → '
                     f'{PREPARED.value_range(b["allocated_bytes"])} | {a["payload_bytes"]:,} → {b["payload_bytes"]:,} | '
                     f'{a["wasm_bytes"]:,} → {b["wasm_bytes"]:,} | {runtime[0]} → {runtime[1]} |')
    lines += ["", "JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, "
              "all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.", ""]
    return "\n".join(lines)


def write_reports(report, json_path, markdown_path):
    require(json_path.resolve() != markdown_path.resolve(), "Report paths must differ")
    for path in (json_path, markdown_path):
        require(not path.exists(), "Report already exists: " + str(path))
    for path, content in ((json_path, json.dumps(report, indent=2, allow_nan=False) + "\n"), (markdown_path, markdown(report))):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("x") as output:
            output.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "json", "markdown"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--target-plugin", required=True)
    args = parser.parse_args()
    try:
        report = compare(args.baseline, args.candidate, args.target_plugin)
        write_reports(report, args.json, args.markdown)
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        parser.error(str(error))
    print(f'{report["case_count"]} matched cases, three observations per case per revision. Wrote {args.json} and {args.markdown}.')


if __name__ == "__main__":
    main()
