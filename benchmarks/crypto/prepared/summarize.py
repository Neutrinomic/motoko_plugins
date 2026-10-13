#!/usr/bin/env python3
"""Validate prepared-key benchmark evidence and write an immutable JSON/Markdown report."""
import argparse
import hashlib
import json
import re
from pathlib import Path

PROTOCOL = "crypto-prepared-v1"
METRICS = ("instructions", "allocated_bytes", "reclaimed_bytes")
PHASES = ("before_run", "after_run", "after_gc")
MEMORY = ("occupied_heap_bytes", "wasm_capacity_bytes", "total_allocation_bytes", "reclaimed_bytes")
RTS = ("MOC_RELEASE_RTS", "MOC_DEBUG_RTS")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def natural(value):
    # The JS runner serializes counters above Number.MAX_SAFE_INTEGER as decimal strings.
    if isinstance(value, str) and re.fullmatch(r"0|[1-9][0-9]*", value):
        return int(value)
    require(type(value) is int and value >= 0, "Invalid nonnegative integer counter")
    return value


def relative(root, name):
    path = Path(name)
    require(not path.is_absolute() and ".." not in path.parts, "Unsafe evidence path: " + str(name))
    return root / path


def stats(values):
    values = sorted(natural(value) for value in values)
    require(len(values) == 3, "Expected exactly three fresh-canister measurements")
    return {"median": values[1], "range": [values[0], values[2]]}


def key(case):
    return case["name"], case["implementation"]


def read_run(directory):
    directory = Path(directory)
    build_path, result_path = directory / "build.json", directory / "results.json"
    build, result = json.loads(build_path.read_text()), json.loads(result_path.read_text())
    require(build["protocol"] == result["protocol"] == PROTOCOL, "Different measurement protocol")
    require(build["stage"] == result["stage"], "Stage identity mismatch")
    require(build["complete"] is True and result["complete"] is True, "Incomplete run")
    require(result["build_sha256"] == sha(build_path), "Build metadata changed")
    require(result["failed_measurements"] == 0 and "fatal_error" not in result, "Failed measurements")
    require(type(result["trials"]) is int and result["trials"] == 3, "Expected exactly three trials")
    require(build["expected_case_count"] == result["expected_case_count"] == len(build["cases"])
            == len(result["cases"]) > 0, "Incomplete or empty cohort")
    frozen = directory / "inputs"
    pins = build["frozen_inputs_sha256"]
    for name, digest in pins.items():
        require(sha(relative(frozen, name)) == digest, "Frozen input changed: " + name)
    require(build["compiler_sha256"] == pins["toolchain/moc"], "Compiler pin mismatch")
    require(build["runner_sha256"] == result["runner_sha256"]
            == pins["benchmarks/crypto/prepared/run.mjs"], "Runner pin mismatch")
    require(set(build["rts_environment"]) == set(RTS), "Incomplete RTS identity")
    dependencies = {name: digest for name, digest in pins.items()
                    if name.startswith("benchmarks/crypto/dependencies/")}
    require("benchmarks/crypto/dependencies/mops.lock" in dependencies, "Missing dependency lock")
    fast_sources = {name: digest for name, digest in pins.items() if name.startswith("packages/fast/src/")}
    require(fast_sources, "Missing frozen mo:fast sources")
    runner_dependencies = hashlib.sha256(json.dumps(result["runner_dependencies"], sort_keys=True,
                                                    separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
    require(result["runner_dependencies_sha256"] == runner_dependencies, "Runner dependency fingerprint mismatch")
    identity = {
        "compiler_sha256": build["compiler_sha256"],
        "runner_sha256": result["runner_sha256"],
        "pocket_ic_sha256": result["pocket_ic_sha256"],
        "runner_dependencies_sha256": runner_dependencies,
        "motoko_dependencies_sha256": hashlib.sha256(json.dumps(
            dependencies, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "fast_package_sha256": hashlib.sha256(json.dumps(
            fast_sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "dependency_aliases": build["dependency_aliases"],
        "rts_sha256": {name: pins["toolchain/" + Path(build["rts_environment"][name]).name] for name in RTS},
    }
    plugin_pins = {}
    for plugin in sorted({plugin for case in build["cases"] for plugin in case["plugins"]}):
        prefix = "dist/" + plugin + "/"
        plugin_build = json.loads(relative(frozen, prefix + "build.json").read_text())
        require(prefix + "build.json" in pins, "Unpinned plugin build: " + plugin)
        require(plugin_build["moc_sha256"] == build["compiler_sha256"], "Plugin compiler mismatch: " + plugin)
        require({"plugin.cmxs", "runtime.wasm"} <= set(plugin_build["sha256"]), "Incomplete plugin artifacts: " + plugin)
        for name, digest in plugin_build["sha256"].items():
            require(pins[prefix + name] == digest, "Plugin artifact pin mismatch: " + plugin + "/" + name)
        for name, digest in plugin_build["source_sha256"].items():
            require(pins["plugin-build-inputs/" + plugin + "/" + name] == digest, "Plugin source pin mismatch: " + plugin + "/" + name)
        plugin_pins[plugin] = {"artifacts": plugin_build["sha256"], "sources": plugin_build["source_sha256"]}
    builds = {key(case): case for case in build["cases"]}
    require(len(builds) == len(build["cases"]), "Duplicate build case")
    seen, cases = set(), []
    for case in result["cases"]:
        case_key = key(case)
        require(case_key not in seen, "Duplicate result case: " + str(case_key))
        seen.add(case_key)
        require(case_key in builds, "Result case absent from build: " + str(case_key))
        compiled = builds[case_key]
        require(type(case["returncode"]) is int and case["returncode"] == compiled["returncode"] == 0,
                "Failed build: " + str(case_key))
        for field in ("family", "plugins", "source", "source_sha256", "expected_hex", "wasm", "wasm_sha256",
                      "wasm_bytes", "memory_metrics", "prepared"):
            require(case[field] == compiled[field], "Build/result mismatch: " + field)
        require(case["memory_metrics"] is True, "Missing memory instrumentation")
        wasm = relative(directory, case["wasm"])
        require(sha(wasm) == case["wasm_sha256"] and wasm.stat().st_size == case["wasm_bytes"], "Wasm changed")
        source = "benchmarks/crypto/" + case["source"]
        require(case["source_sha256"] == pins[source], "Source pin mismatch")
        meta = case["prepared"]
        for field in ("scheme", "profile", "operation", "fixture", "comparison_group", "fixture_source"):
            require(isinstance(meta[field], str) and bool(meta[field]), "Missing prepared metadata: " + field)
        require(meta["mode"] in ("direct", "prepare", "prepared", "cold", "control"), "Unknown prepared mode")
        reuse = meta.get("reuse", 1)
        require(type(reuse) is int and reuse > 0, "Invalid reuse count")
        require(type(meta["payload_bytes"]) is int and meta["payload_bytes"] >= 0, "Invalid prepared payload size")
        require(meta["mode"] != "prepare" or reuse == 1, "Preparation must be measured once")
        fixture_source = "benchmarks/crypto/" + meta["fixture_source"]
        require(meta["fixture_sha256"] == pins[fixture_source], "Fixture pin mismatch")
        expected = bytes.fromhex(case["expected_hex"])
        oracle = hashlib.sha256(expected).hexdigest()
        measurements = case["measurements"]
        require(len(measurements) == 3, "Incomplete measurement set")
        require(all(type(m["trial"]) is int for m in measurements)
                and sorted(m["trial"] for m in measurements) == [0, 1, 2], "Invalid trial indices")
        for measurement in measurements:
            require(measurement.get("correct") is True and "error" not in measurement, "Failed measurement")
            require(measurement["output_sha256"] == oracle and measurement["output_bytes"] == len(expected),
                    "Independent oracle mismatch")
            for metric in METRICS:
                natural(measurement[metric])
            require(natural(measurement["instructions"]) > 0, "Zero instruction count")
            require(set(measurement["memory"]) == set(PHASES), "Incomplete memory snapshots")
            for snapshot in measurement["memory"].values():
                require(set(snapshot) == set(MEMORY), "Incomplete memory counters")
                for value in snapshot.values():
                    natural(value)
        cases.append({**case, "plugin_pins": {plugin: plugin_pins[plugin] for plugin in case["plugins"]}})
    return {"stage": build["stage"], "build_sha256": sha(build_path), "results_sha256": sha(result_path)}, identity, cases


def measured(case):
    samples = case["measurements"]
    return {
        "name": case["name"], "implementation": case["implementation"],
        "stage": case["stage"], "source": case["source"],
        "mode": case["prepared"]["mode"], "reuse": case["prepared"].get("reuse", 1),
        "payload_bytes": case["prepared"]["payload_bytes"],
        "source_sha256": case["source_sha256"], "wasm_sha256": case["wasm_sha256"], "wasm_bytes": case["wasm_bytes"],
        **{metric: stats(m[metric] for m in samples) for metric in METRICS},
        "memory": {phase: {metric: stats(m["memory"][phase][metric] for m in samples) for metric in MEMORY}
                   for phase in PHASES},
    }


def costs(prepare, direct, hot):
    saving = direct - hot
    return {
        "strict_instruction_break_even_reuses": prepare // saving + 1 if saving > 0 else None,
        "models": [{"reuse": n, "direct_instructions": n * direct,
                    "prepared_instructions": prepare + n * hot} for n in (1, 2, 10, 100)],
    }


def summarize(directories):
    runs, groups, seen_cases, identities = [], {}, set(), {}
    for directory in directories:
        run, identity, cases = read_run(directory)
        require(run["stage"] not in identities, "Duplicate run stage: " + run["stage"])
        identities[run["stage"]] = identity
        runs.append({**run, "toolchain": identity})
        for case in cases:
            require(key(case) not in seen_cases, "Duplicate case across runs: " + str(key(case)))
            seen_cases.add(key(case))
            case = {**case, "stage": run["stage"]}
            groups.setdefault(case["prepared"]["comparison_group"], []).append(case)
    require(groups, "No groups to summarize")
    rows, controls = [], []
    for group, cases in sorted(groups.items()):
        first, modes = cases[0], {}
        meta = first["prepared"]
        for case in cases:
            require(identities[case["stage"]] == identities[first["stage"]], "Toolchain/dependency mismatch: " + group)
            for field in ("scheme", "profile", "operation", "fixture", "fixture_source", "fixture_sha256"):
                require(case["prepared"][field] == meta[field], "Different " + field + ": " + group)
            require(case["expected_hex"] == first["expected_hex"], "Different operation oracle: " + group)
            require(case["family"] == first["family"] and case["plugins"] == first["plugins"],
                    "Different plugin/family: " + group)
            require(case["plugin_pins"] == first["plugin_pins"], "Different plugin artifacts/sources: " + group)
            mode_key = case["prepared"]["mode"], case["prepared"].get("reuse", 1)
            require(mode_key not in modes, "Duplicate mode/reuse: " + group + "/" + str(mode_key))
            modes[mode_key] = case
        if any(mode == "control" for mode, _ in modes):
            require(len(cases) == 1, "Control group must contain exactly one standalone case: " + group)
            controls.append({"comparison_group": group, **{field: meta[field] for field in
                             ("scheme", "profile", "operation", "fixture", "fixture_source", "fixture_sha256")},
                             "expected_hex": first["expected_hex"], "toolchain": identities[first["stage"]],
                             "plugin_pins": first["plugin_pins"], "measurement": measured(first)})
            continue
        require(all((mode, 1) in modes for mode in ("direct", "prepare", "prepared")), "Missing reuse=1 mode: " + group)
        payload = modes[("prepare", 1)]["prepared"]["payload_bytes"]
        require(all(case["prepared"]["payload_bytes"] == payload for (mode, _), case in modes.items()
                    if mode != "direct"), "Different prepared payload sizes: " + group)
        base = {mode: measured(modes[(mode, 1)]) for mode in ("direct", "prepare", "prepared")}
        row = {"comparison_group": group, **{field: meta[field] for field in
               ("scheme", "profile", "operation", "fixture", "fixture_source", "fixture_sha256")},
               "expected_hex": first["expected_hex"], "toolchain": identities[first["stage"]],
               "plugin_pins": first["plugin_pins"], **base,
               "actual_batches": [measured(case) for (mode, reuse), case in sorted(modes.items())
                                  if reuse > 1 or mode == "cold"]}
        row.update(costs(*(base[mode]["instructions"]["median"] for mode in ("prepare", "direct", "prepared"))))
        rows.append(row)
    return {"protocol": PROTOCOL, "trials": 3, "runs": runs, "case_count": len(seen_cases),
            "groups": rows, "controls": controls}


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def value_range(value):
    low, high = value["range"]
    return f'{value["median"]:,} [{low:,}–{high:,}]'


def markdown(report):
    lines = ["Measured medians [minimum–maximum] from three fresh canisters per case.", "",
             "Allocation is cumulative bytes allocated during the measured operation. Payload is the prepared object's declared byte payload."]
    if report["groups"]:
        lines += ["", "Preparation is measured separately; prepared calls reuse a key created outside the timed interval.", "",
                  "| Workload | Mode | Instructions | Allocated bytes | Payload bytes | Canister Wasm bytes |",
                  "|---|---|---:|---:|---:|---:|"]
    for row in report["groups"]:
        for mode in ("direct", "prepare", "prepared"):
            sample = row[mode]
            lines.append(f'| {cell(row["comparison_group"])} | {mode} | {value_range(sample["instructions"])} | '
                         f'{value_range(sample["allocated_bytes"])} | {sample["payload_bytes"]:,} | {sample["wasm_bytes"]:,} |')
    if report["controls"]:
        lines += ["", "Standalone operation controls (no preparation comparison or speedup calculation):", "",
                  "| Control | Operation | Reuse | Instructions | Allocated bytes | Canister Wasm bytes |",
                  "|---|---|---:|---:|---:|---:|"]
        for row in report["controls"]:
            sample = row["measurement"]
            lines.append(f'| {cell(row["comparison_group"])} | {cell(row["operation"])} | {sample["reuse"]} | '
                         f'{value_range(sample["instructions"])} | {value_range(sample["allocated_bytes"])} | {sample["wasm_bytes"]:,} |')
    if report["groups"]:
        lines += ["", "Instruction models below use only the measured reuse=1 medians: direct = N×D; prepared = P+N×H. "
                  "They are arithmetic projections, not measured batch timings. Break-even is the first integer N with a strict saving.", "",
                  "| Workload | First cheaper reuse | N | Direct model | Prepared model |", "|---|---:|---:|---:|---:|"]
    for row in report["groups"]:
        crossover = row["strict_instruction_break_even_reuses"]
        for model in row["models"]:
            lines.append(f'| {cell(row["comparison_group"])} | {crossover if crossover is not None else "Never (H ≥ D)"} | '
                         f'{model["reuse"]} | {model["direct_instructions"]:,} | {model["prepared_instructions"]:,} |')
    batches = [(row["comparison_group"], sample) for row in report["groups"] for sample in row["actual_batches"]]
    if batches:
        lines += ["", "Actual batch observations (whole batch, without dividing by reuse). "
                  "Cold rows include one preparation plus N calls in the timed interval; "
                  "direct/prepared rows exclude preparation. These observations do not feed the model or break-even:", "",
                  "| Workload | Mode | Reuse | Batch instructions | Batch allocated bytes |", "|---|---|---:|---:|---:|"]
        for group, sample in batches:
            lines.append(f'| {cell(group)} | {sample["mode"]} | {sample["reuse"]} | {value_range(sample["instructions"])} | '
                         f'{value_range(sample["allocated_bytes"])} |')
    lines += ["", "Sampled occupied heap and Wasm capacity below are queried before the run, after the run message, "
              "and after four further GC increments. They are neither peak memory nor retained live data. "
              "Message-end GC may occur before after_run; four increments need not finish collection. "
              "Prepared keys and results remain reachable as specified by each fixture.", "",
              "| Workload | Mode/reuse | Before occupied bytes | After occupied bytes | After GC occupied bytes | After GC Wasm capacity bytes |",
              "|---|---|---:|---:|---:|---:|"]
    samples = [(row["comparison_group"], sample) for row in report["groups"]
               for sample in [row[mode] for mode in ("direct", "prepare", "prepared")] + row["actual_batches"]]
    samples += [(row["comparison_group"], row["measurement"]) for row in report["controls"]]
    for group, sample in samples:
        occupied = [value_range(sample["memory"][phase]["occupied_heap_bytes"]) for phase in PHASES]
        capacity = value_range(sample["memory"]["after_gc"]["wasm_capacity_bytes"])
        lines.append(f'| {cell(group)} | {sample["mode"]}/{sample["reuse"]} | '
                     + " | ".join([*occupied, capacity]) + " |")
    lines += ["", "The JSON report retains all three memory phases, cumulative counters, exact source/artifact hashes, "
              "independent operation oracles and build/result provenance.", ""]
    return "\n".join(lines)


def write_reports(report, json_path, markdown_path):
    require(json_path.resolve() != markdown_path.resolve(), "JSON and Markdown output paths must differ")
    for path in (json_path, markdown_path):
        require(not path.exists(), "Report already exists: " + str(path))
    contents = (json.dumps(report, indent=2) + "\n", markdown(report))
    for path, content in zip((json_path, markdown_path), contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("x") as output:
            output.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, action="append", required=True, help="Directory containing build.json/results.json; repeat for disjoint cohorts")
    parser.add_argument("--json", type=Path, required=True, help="New JSON report path")
    parser.add_argument("--markdown", type=Path, required=True, help="New Markdown report path")
    args = parser.parse_args()
    try:
        report = summarize(args.run)
        write_reports(report, args.json, args.markdown)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.error(str(error))
    print(f'{len(report["groups"])} comparison groups; {len(report["controls"])} standalone controls; '
          f'{report["case_count"]} validated cases. Wrote {args.json} and {args.markdown}.')


if __name__ == "__main__":
    main()
