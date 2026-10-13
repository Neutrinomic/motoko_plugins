#!/usr/bin/env python3
"""Check manifest backend selection without invoking a compiler."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "plugin_build", Path(__file__).resolve().parents[1] / "scripts/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BackendConfig(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.original_root = build.ROOT
        build.ROOT = Path(self.directory.name)

    def tearDown(self):
        build.ROOT = self.original_root
        self.directory.cleanup()

    def manifest(self, name, **fields):
        path = build.ROOT / "plugins" / name / "plugin.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"name": name, **fields}))

    def test_per_package_flags_do_not_leak(self):
        cfg = ['curve25519_dalek_bits="32"', 'curve25519_dalek_backend="serial"']
        self.manifest("selected", runtime_crate="selected", runtime_cfg=cfg)
        self.manifest("ordinary", runtime_crate="ordinary")
        selected, ordinary = build.discover(["selected", "ordinary"])
        env = {"CARGO_ENCODED_RUSTFLAGS": "-C\x1fopt-level=2"}
        original = dict(env)
        selected_flags = build.runtime_rustflags(selected, env)
        ordinary_flags = build.runtime_rustflags(ordinary, env)
        self.assertEqual(selected_flags, ordinary_flags + ["--cfg", cfg[0], "--cfg", cfg[1]])
        self.assertNotIn("--cfg", ordinary_flags)
        self.assertEqual(env, original)

    def test_rejects_flags_and_malformed_cfg(self):
        for cfg in ["feature", [3], ["-C"], ['feature="x y"'],
                    ["a\x1fb"], ["foo;bar"], ['feature="x" --cfg injected']]:
            with self.subTest(cfg=cfg):
                self.manifest("bad", runtime_crate="bad", runtime_cfg=cfg)
                with self.assertRaisesRegex(ValueError, "runtime_cfg must"):
                    build.discover([])

    def test_cfg_requires_runtime(self):
        self.manifest("compiler_only", runtime_cfg=["feature"])
        with self.assertRaisesRegex(ValueError, "requires runtime_crate"):
            build.discover([])

    def test_encoded_caller_flags_take_precedence(self):
        self.manifest("ordinary", runtime_crate="ordinary")
        manifest = build.discover([])[0]
        flags = build.runtime_rustflags(manifest, {
            "RUSTFLAGS": "--cfg ignored",
            "CARGO_ENCODED_RUSTFLAGS": "--cfg\x1fretained",
        })
        self.assertEqual(flags[-2:], ["--cfg", "retained"])
        self.assertNotIn("ignored", flags)


if __name__ == "__main__":
    unittest.main()
