"""Synthetic evidence tests: no compiler, crypto implementation or PocketIC required."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("summarize", Path(__file__).with_name("summarize.py"))
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def fixture(directory, modes=("direct", "prepare", "prepared"), stage="synthetic"):
    directory.mkdir(parents=True)
    frozen = directory / "inputs"
    pins = {}
    for name in ("toolchain/moc", "toolchain/mo-rts.wasm", "toolchain/mo-rts-debug.wasm",
                 "benchmarks/crypto/prepared/run.mjs", "benchmarks/crypto/dependencies/mops.lock",
                 "benchmarks/crypto/prepared/fixture.json", "dist/test/plugin.cmxs", "dist/test/runtime.wasm",
                 "plugin-build-inputs/test/plugins/test/runtime.rs", "packages/fast/src/Test.mo"):
        path = frozen / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(name)
        pins[name] = REPORT.sha(path)
    plugin_build = {"moc_sha256": pins["toolchain/moc"],
                    "sha256": {name: pins["dist/test/" + name] for name in ("plugin.cmxs", "runtime.wasm")},
                    "source_sha256": {"plugins/test/runtime.rs": pins["plugin-build-inputs/test/plugins/test/runtime.rs"]}}
    write_json(frozen / "dist/test/build.json", plugin_build)
    pins["dist/test/build.json"] = REPORT.sha(frozen / "dist/test/build.json")
    cases = []
    for mode in modes:
        source = f"prepared/{mode}.mo"
        path = frozen / "benchmarks/crypto" / source
        path.write_text("different source: " + mode)
        pins["benchmarks/crypto/" + source] = REPORT.sha(path)
        wasm = directory / (mode + ".wasm")
        wasm.write_bytes(("different Wasm: " + mode).encode())
        case = {
            "name": mode, "implementation": "plugin", "family": "signature", "plugins": ["test"],
            "source": source, "source_sha256": REPORT.sha(path), "expected_hex": "0102",
            "wasm": wasm.name, "wasm_sha256": REPORT.sha(wasm), "wasm_bytes": wasm.stat().st_size,
            "returncode": 0, "memory_metrics": True,
            "prepared": {"scheme": "test", "profile": "strict", "operation": "verify", "fixture": "valid",
                         "comparison_group": "test-valid", "mode": mode, "reuse": 1,
                         "payload_bytes": 0 if mode == "direct" else 32,
                         "fixture_source": "prepared/fixture.json", "fixture_sha256": pins["benchmarks/crypto/prepared/fixture.json"]},
        }
        cases.append(case)
    build = {
        "protocol": REPORT.PROTOCOL, "stage": stage, "complete": True, "expected_case_count": len(cases),
        "compiler_sha256": pins["toolchain/moc"], "runner_sha256": pins["benchmarks/crypto/prepared/run.mjs"],
        "rts_environment": {"MOC_RELEASE_RTS": "/original/mo-rts.wasm", "MOC_DEBUG_RTS": "/original/mo-rts-debug.wasm"},
        "dependency_aliases": {"core": "core@1"}, "frozen_inputs_sha256": pins, "cases": cases,
    }
    result = {
        "protocol": REPORT.PROTOCOL, "stage": stage, "complete": True, "expected_case_count": len(cases),
        "trials": 3, "failed_measurements": 0, "runner_sha256": build["runner_sha256"],
        "pocket_ic_sha256": "a" * 64, "cases": copy.deepcopy(cases),
        "runner_dependencies": {"lock_sha256": "c" * 64, "modules": {"node_modules/sdk/index.js": "d" * 64}},
    }
    result["runner_dependencies_sha256"] = REPORT.hashlib.sha256(json.dumps(
        result["runner_dependencies"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    for case in result["cases"]:
        cost = {"direct": 100, "prepare": 60, "prepared": 40, "cold": 200, "control": 55}[case["prepared"]["mode"]]
        case["measurements"] = [
            {"trial": trial, "instructions": cost + delta, "allocated_bytes": 32, "reclaimed_bytes": 0,
             "output_bytes": 2, "output_sha256": REPORT.hashlib.sha256(bytes.fromhex("0102")).hexdigest(), "correct": True,
             "memory": {phase: {metric: 1000 for metric in REPORT.MEMORY} for phase in REPORT.PHASES}}
            for trial, delta in enumerate((1, 0, -1))]
    save(directory, build, result)
    return build, result


def save(directory, build, result):
    write_json(directory / "build.json", build)
    result["build_sha256"] = REPORT.sha(directory / "build.json")
    write_json(directory / "results.json", result)


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.run = self.root / "run"
        self.build, self.result = fixture(self.run)

    def test_valid_different_sources_and_strict_break_even(self):
        report = REPORT.summarize([self.run])
        row = report["groups"][0]
        self.assertEqual(row["direct"]["instructions"], {"median": 100, "range": [99, 101]})
        self.assertEqual(row["strict_instruction_break_even_reuses"], 2)  # N=1 is an exact tie.
        self.assertEqual(row["models"][2], {"reuse": 10, "direct_instructions": 1000, "prepared_instructions": 460})
        self.assertEqual(row["prepared"]["memory"]["after_gc"]["occupied_heap_bytes"]["median"], 1000)
        self.assertIn("neither peak memory nor retained live data", REPORT.markdown(report))

    def test_exact_large_integer_arithmetic_and_no_crossover(self):
        large = 2**80 + 7
        self.assertEqual(REPORT.costs(large, 17, 12)["strict_instruction_break_even_reuses"], large // 5 + 1)
        self.assertIsNone(REPORT.costs(1, 10, 10)["strict_instruction_break_even_reuses"])
        self.assertIsNone(REPORT.costs(1, 10, 11)["strict_instruction_break_even_reuses"])
        self.assertEqual(REPORT.costs(0, 10, 9)["strict_instruction_break_even_reuses"], 1)
        self.assertEqual(REPORT.natural(str(large)), large)
        for invalid in (True, -1, 0.5, "-1", "01", "1e5"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                REPORT.natural(invalid)

    def test_missing_mode_is_not_silently_dropped(self):
        self.build["cases"].pop()
        self.result["cases"].pop()
        self.build["expected_case_count"] = self.result["expected_case_count"] = 2
        save(self.run, self.build, self.result)
        with self.assertRaisesRegex(ValueError, "Missing reuse=1 mode"):
            REPORT.summarize([self.run])

    def test_failed_or_corrupted_run_rejected(self):
        mutations = {
            "Incomplete run": lambda b, r: r.update(complete=False),
            "Failed measurements": lambda b, r: r.update(failed_measurements=1),
            "exactly three trials": lambda b, r: r.update(trials=4),
            "Incomplete or empty cohort": lambda b, r: r.update(expected_case_count=4),
            "Invalid trial indices": lambda b, r: r["cases"][0]["measurements"][1].update(trial=0),
            "Independent oracle mismatch": lambda b, r: r["cases"][0]["measurements"][0].update(output_bytes=1),
            "Failed measurement": lambda b, r: r["cases"][0]["measurements"][0].update(correct=False),
            "Incomplete memory snapshots": lambda b, r: r["cases"][0]["measurements"][0]["memory"].pop("after_gc"),
            "Build/result mismatch": lambda b, r: r["cases"][0].update(expected_hex="ff"),
            "Duplicate result case": lambda b, r: r["cases"].__setitem__(1, copy.deepcopy(r["cases"][0])),
            "Runner dependency fingerprint mismatch": lambda b, r: r.update(runner_dependencies_sha256="0" * 64),
        }
        for message, mutate in mutations.items():
            with self.subTest(message=message):
                build, result = copy.deepcopy(self.build), copy.deepcopy(self.result)
                mutate(build, result)
                save(self.run, build, result)
                with self.assertRaisesRegex(ValueError, message):
                    REPORT.summarize([self.run])

    def test_group_fixture_oracle_payload_and_duplicate_validation(self):
        mutations = {
            "Different fixture": lambda c: c["prepared"].update(fixture="other"),
            "Different operation oracle": lambda c: c.update(expected_hex="010203"),
            "Different prepared payload sizes": lambda c: c["prepared"].update(payload_bytes=33),
            "Duplicate mode/reuse": lambda c: c["prepared"].update(mode="prepare"),
        }
        for message, mutate in mutations.items():
            with self.subTest(message=message):
                build, result = copy.deepcopy(self.build), copy.deepcopy(self.result)
                for case in (build["cases"][-1], result["cases"][-1]):
                    mutate(case)
                for sample in result["cases"][-1]["measurements"]:
                    expected = bytes.fromhex(result["cases"][-1]["expected_hex"])
                    sample.update(output_bytes=len(expected), output_sha256=REPORT.hashlib.sha256(expected).hexdigest())
                save(self.run, build, result)
                with self.assertRaisesRegex(ValueError, message):
                    REPORT.summarize([self.run])

    def test_frozen_source_and_wasm_tampering(self):
        for path in (self.run / "inputs/benchmarks/crypto/prepared/direct.mo", self.run / "direct.wasm"):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(ValueError, "changed"):
                    REPORT.summarize([self.run])
                path.write_bytes(original)

    def test_cross_run_identity_mismatch(self):
        first = self.root / "first"
        second = self.root / "second"
        fixture(first, ("direct",), "first")
        build, result = fixture(second, ("prepare", "prepared"), "second")
        REPORT.summarize([first, second])
        result["pocket_ic_sha256"] = "b" * 64
        save(second, build, result)
        with self.assertRaisesRegex(ValueError, "Toolchain/dependency mismatch"):
            REPORT.summarize([first, second])

    def test_cross_run_plugin_change_rejected(self):
        first, second = self.root / "first", self.root / "second"
        fixture(first, ("direct",), "first")
        build, result = fixture(second, ("prepare", "prepared"), "second")
        runtime = second / "inputs/dist/test/runtime.wasm"
        runtime.write_bytes(b"different plugin build")
        digest = REPORT.sha(runtime)
        plugin_path = second / "inputs/dist/test/build.json"
        plugin_build = json.loads(plugin_path.read_text())
        plugin_build["sha256"]["runtime.wasm"] = digest
        write_json(plugin_path, plugin_build)
        build["frozen_inputs_sha256"]["dist/test/runtime.wasm"] = digest
        build["frozen_inputs_sha256"]["dist/test/build.json"] = REPORT.sha(plugin_path)
        save(second, build, result)
        with self.assertRaisesRegex(ValueError, "Different plugin artifacts/sources"):
            REPORT.summarize([first, second])

    def test_cross_run_fast_wrapper_change_rejected(self):
        first, second = self.root / "first", self.root / "second"
        fixture(first, ("direct",), "first")
        build, result = fixture(second, ("prepare", "prepared"), "second")
        wrapper = second / "inputs/packages/fast/src/Test.mo"
        wrapper.write_text("different wrapper implementation")
        build["frozen_inputs_sha256"]["packages/fast/src/Test.mo"] = REPORT.sha(wrapper)
        save(second, build, result)
        with self.assertRaisesRegex(ValueError, "Toolchain/dependency mismatch"):
            REPORT.summarize([first, second])

    def test_batch_measurement_never_used_for_per_call_models(self):
        build_case, result_case = copy.deepcopy(self.build["cases"][-1]), copy.deepcopy(self.result["cases"][-1])
        for case in (build_case, result_case):
            case["name"] = "prepared-ten"
            case["prepared"]["reuse"] = 10
        for sample in result_case["measurements"]:
            sample["instructions"] = 777
        self.build["cases"].append(build_case)
        self.result["cases"].append(result_case)
        self.build["expected_case_count"] = self.result["expected_case_count"] = 4
        save(self.run, self.build, self.result)
        report = REPORT.summarize([self.run])
        row = report["groups"][0]
        self.assertEqual(row["actual_batches"][0]["instructions"]["median"], 777)
        self.assertEqual(row["models"][2]["prepared_instructions"], 460)
        self.assertIn("whole batch, without dividing by reuse", REPORT.markdown(report))

    def test_reports_never_overwrite(self):
        report = REPORT.summarize([self.run])
        json_path, markdown_path = self.root / "report.json", self.root / "report.md"
        REPORT.write_reports(report, json_path, markdown_path)
        original = json_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            REPORT.write_reports(report, json_path, self.root / "new.md")
        self.assertEqual(json_path.read_bytes(), original)
        self.assertFalse((self.root / "new.md").exists())

    def test_cold_rows_include_setup_and_never_feed_models(self):
        run = self.root / "cold"
        fixture(run, ("direct", "prepare", "prepared", "cold"))
        report = REPORT.summarize([run])
        row = report["groups"][0]
        self.assertEqual(row["actual_batches"][0]["mode"], "cold")
        self.assertEqual(row["actual_batches"][0]["reuse"], 1)
        self.assertEqual(row["actual_batches"][0]["instructions"]["median"], 200)
        self.assertEqual(row["strict_instruction_break_even_reuses"], 2)
        self.assertEqual(row["models"][0]["prepared_instructions"], 100)
        self.assertIn("Cold rows include one preparation plus N calls", REPORT.markdown(report))

    def test_standalone_control_has_no_comparison(self):
        run = self.root / "control"
        fixture(run, ("control",))
        report = REPORT.summarize([run])
        self.assertEqual(report["groups"], [])
        control = report["controls"][0]
        self.assertEqual(control["measurement"]["instructions"]["median"], 55)
        self.assertNotIn("strict_instruction_break_even_reuses", control)
        self.assertNotIn("models", control)
        self.assertIn("no preparation comparison or speedup calculation", REPORT.markdown(report))
        self.assertNotIn("First cheaper reuse", REPORT.markdown(report))

    def test_control_cannot_mingle_with_triplet_or_other_control(self):
        run = self.root / "mixed"
        build, result = fixture(run, ("direct", "prepare", "prepared", "control"))
        with self.assertRaisesRegex(ValueError, "Control group must contain exactly one standalone case"):
            REPORT.summarize([run])
        build["cases"] = [build["cases"][-1]]
        result["cases"] = [result["cases"][-1]]
        for document in (build, result):
            other = copy.deepcopy(document["cases"][0])
            other["name"] = "control-other"
            other["prepared"]["reuse"] = 2
            document["cases"].append(other)
            document["expected_case_count"] = 2
        save(run, build, result)
        with self.assertRaisesRegex(ValueError, "Control group must contain exactly one standalone case"):
            REPORT.summarize([run])


if __name__ == "__main__":
    unittest.main()
