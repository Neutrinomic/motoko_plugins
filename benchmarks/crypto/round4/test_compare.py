"""Small synthetic revision comparisons; no compiler or PocketIC required."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).parent
REPORT = load("round4_compare", HERE / "compare.py")
FIXTURE = load("prepared_test_fixture", HERE.parent / "prepared/test_summarize.py")


def pin(directory, build, name, content):
    path = directory / "inputs" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    digest = REPORT.PREPARED.sha(path)
    build["frozen_inputs_sha256"][name] = digest
    return digest


def fixture(directory, stage):
    build, result = FIXTURE.fixture(directory, ("direct", "prepare", "prepared", "cold"), stage)
    pin(directory, build, REPORT.BUILDER, "same frozen builder")
    pin(directory, build, "benchmarks/crypto/prepared/Helper.mo", "module {}")
    build["rts_environment"] = {key: str(directory / "inputs/toolchain" / name)
                                for key, name in zip(REPORT.PREPARED.RTS, ("mo-rts.wasm", "mo-rts-debug.wasm"))}
    moc = "/original/bin/moc"
    build["inputs_sha256"] = {moc: build["compiler_sha256"]}
    for case in build["cases"]:
        case["command"] = [moc, "--package", "fast", str(directory / "inputs/packages/fast/src"),
                           "--plugin", str(directory / "inputs/dist/test"),
                           str(directory / "inputs/benchmarks/crypto" / case["source"]),
                           "-o", str(directory / case["wasm"])]
    FIXTURE.save(directory, build, result)
    return build, result


def plugin(directory, build, name, text):
    metadata = {"moc_sha256": build["compiler_sha256"], "sha256": {}, "source_sha256": {}}
    for artifact in ("runtime.wasm", "plugin.cmxs"):
        metadata["sha256"][artifact] = pin(directory, build, f"dist/{name}/{artifact}", text + artifact)
    source = f"plugins/{name}/runtime.rs"
    metadata["source_sha256"][source] = pin(directory, build, f"plugin-build-inputs/{name}/{source}", text)
    pin(directory, build, f"dist/{name}/build.json", json.dumps(metadata))


class CompareTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.left, self.right = self.root / "baseline", self.root / "candidate"
        self.a, self.ar = fixture(self.left, "prepared-round4-baseline")
        self.b, self.br = fixture(self.right, "prepared-round4-candidate")

    def compare(self):
        FIXTURE.save(self.left, self.a, self.ar)
        FIXTURE.save(self.right, self.b, self.br)
        return REPORT.compare(self.left, self.right, "test")

    def test_changed_target_artifacts_sources_and_payload_allowed(self):
        plugin(self.right, self.b, "test", "optimized implementation")
        for cases in (self.b["cases"], self.br["cases"]):
            cases[2]["prepared"]["payload_bytes"] = 24
        for measurement in self.br["cases"][2]["measurements"]:
            measurement["instructions"] -= 10
        report = self.compare()
        hot = next(row for row in report["cases"] if row["name"] == "prepared")
        self.assertEqual(hot["baseline"]["instructions"], {"median": 40, "range": [39, 41]})
        self.assertEqual(hot["candidate"]["instructions"], {"median": 30, "range": [29, 31]})
        self.assertEqual(hot["change"]["instructions"], {"delta": -10, "saving_percent": 25, "speedup": 40 / 30})
        self.assertEqual(hot["change"]["payload_bytes"]["delta"], -8)
        self.assertEqual(hot["candidate"]["runtime_wasm_bytes"]["test"], len("optimized implementationruntime.wasm"))
        self.assertIn("cold includes one factory plus N calls", REPORT.markdown(report))
        self.assertIn("neither peak memory nor retained live data", REPORT.markdown(report))
        self.assertNotIn("models", report)

    def test_source_local_import_change_rejected(self):
        pin(self.right, self.b, "benchmarks/crypto/prepared/Helper.mo", "different helper")
        with self.assertRaisesRegex(ValueError, "Different actor_sources"):
            self.compare()

    def test_actor_change_rejected_even_with_updated_hashes(self):
        digest = pin(self.right, self.b, "benchmarks/crypto/prepared/direct.mo", "different actor")
        for case in (self.b["cases"][0], self.br["cases"][0]):
            case["source_sha256"] = digest
        with self.assertRaisesRegex(ValueError, "Different actor_sources"):
            self.compare()

    def test_same_environment_required(self):
        self.br["pocket_ic_sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "Different environment"):
            self.compare()

    def test_whole_fast_wrapper_closure_required(self):
        pin(self.right, self.b, "packages/fast/src/Test.mo", "different wrapper")
        with self.assertRaisesRegex(ValueError, "Different environment"):
            self.compare()

    def test_same_builder_required(self):
        pin(self.right, self.b, REPORT.BUILDER, "different builder")
        with self.assertRaisesRegex(ValueError, "Different builder_sha256"):
            self.compare()

    def test_relocated_commands_match_but_flags_do_not(self):
        self.compare()  # Different stage roots normalize without changing flags.
        self.b["cases"][0]["command"].insert(1, "--debug")
        with self.assertRaisesRegex(ValueError, "Different normalized_command"):
            self.compare()

    def test_command_normalization_preserves_external_path_and_pins_moc(self):
        case = copy.deepcopy(self.b["cases"][0])
        neighbor = str(self.right) + "-other/input.mo"
        case["command"].insert(1, neighbor)
        self.assertIn(neighbor, REPORT.normalized_command(self.b, case))
        case["command"][0] = "/unrecorded/moc"
        with self.assertRaisesRegex(ValueError, "Unpinned compiler executable"):
            REPORT.normalized_command(self.b, case)

    def test_workload_metadata_mode_reuse_and_fixture_required(self):
        for field, value in (("fixture", "other"), ("mode", "prepared"), ("reuse", 2), ("profile", "lenient")):
            with self.subTest(field=field):
                original = copy.deepcopy(self.b["cases"][0]["prepared"])
                for case in (self.b["cases"][0], self.br["cases"][0]):
                    case["prepared"][field] = value
                with self.assertRaisesRegex(ValueError, "Different prepared metadata"):
                    self.compare()
                for case in (self.b["cases"][0], self.br["cases"][0]):
                    case["prepared"] = copy.deepcopy(original)

    def test_oracle_difference_rejected_even_when_observations_match_it(self):
        for case in (self.b["cases"][0], self.br["cases"][0]):
            case["expected_hex"] = "abcd"
        for sample in self.br["cases"][0]["measurements"]:
            sample["output_sha256"] = REPORT.PREPARED.hashlib.sha256(bytes.fromhex("abcd")).hexdigest()
        with self.assertRaisesRegex(ValueError, "Different expected_hex"):
            self.compare()

    def test_non_target_artifact_changes_rejected(self):
        for directory, build, result in ((self.left, self.a, self.ar), (self.right, self.b, self.br)):
            plugin(directory, build, "other", "same other plugin")
            for case in build["cases"] + result["cases"]:
                case["plugins"].append("other")
        self.compare()
        plugin(self.right, self.b, "other", "changed other plugin")
        with self.assertRaisesRegex(ValueError, "Different non-target plugin"):
            self.compare()

    def test_missing_or_duplicate_case_rejected(self):
        self.b["cases"].pop()
        self.br["cases"].pop()
        self.b["expected_case_count"] = self.br["expected_case_count"] = 3
        with self.assertRaisesRegex(ValueError, "Different case sets"):
            self.compare()
        self.b["cases"][1] = copy.deepcopy(self.b["cases"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate build case"):
            self.compare()

    def test_failed_measurements_rejected(self):
        self.br["failed_measurements"] = 1
        with self.assertRaisesRegex(ValueError, "Failed measurements"):
            self.compare()

    def test_unknown_target_rejected(self):
        with self.assertRaisesRegex(ValueError, "Target plugin absent"):
            REPORT.compare(self.left, self.right, "absent")

    def test_zero_allocation_and_large_integer_delta(self):
        large = 2**80 + 7
        for samples, cost in ((self.ar["cases"][0]["measurements"], large), (self.br["cases"][0]["measurements"], large - 1)):
            for sample in samples:
                sample.update(instructions=str(cost), allocated_bytes=0)
        row = next(row for row in self.compare()["cases"] if row["name"] == "direct")
        self.assertEqual(row["change"]["instructions"]["delta"], -1)
        self.assertIsNone(row["change"]["allocated_bytes"]["saving_percent"])

    def test_reports_never_overwrite(self):
        report = self.compare()
        json_path, markdown_path = self.root / "report.json", self.root / "report.md"
        REPORT.write_reports(report, json_path, markdown_path)
        original = json_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            REPORT.write_reports(report, json_path, self.root / "new.md")
        self.assertEqual(json_path.read_bytes(), original)
        self.assertFalse((self.root / "new.md").exists())


if __name__ == "__main__":
    unittest.main()
