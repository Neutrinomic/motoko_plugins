#!/usr/bin/env python3
"""Build selected plugins from a private source snapshot during parallel work.

Run from the Motoko checkout's Nix shell. The normal builder still checks all
source hashes and uses --locked; only the snapshot's lockfile is resolved here.
Shared dist/ and Cargo.lock are never changed by this development helper.
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True)
    parser.add_argument("--offline", action="store_true", help="resolve cached dependencies only")
    parser.add_argument("plugins", nargs="+", help="plugin names to build together")
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    names = list(dict.fromkeys(args.plugins))
    for name in names:
        manifest = ROOT / "plugins" / name / "plugin.json"
        if not manifest.is_file() or json.loads(manifest.read_text()).get("name") != name:
            parser.error(f"not a plugin: {name}")

    parent = ROOT / "_build/crypto-stage"
    parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix="-".join(names) + "-", dir=parent))
    print(f"Source snapshot: {stage}", flush=True)
    for filename in ("Cargo.toml", "Cargo.lock"):
        shutil.copy2(ROOT / filename, stage / filename)
    (stage / "scripts").mkdir()
    for filename in ("build.py", "build.sh"):
        shutil.copy2(ROOT / "scripts" / filename, stage / "scripts" / filename)
    # The production builder hashes every workspace runtime, including local
    # sibling dependencies. Preserve that contract in the snapshot as well.
    for runtime in sorted((ROOT / "plugins").glob("*/runtime")):
        cargo = runtime / "Cargo.toml"
        if not cargo.is_file():
            if runtime.parent.name in names:
                parser.error(f"selected runtime is incomplete: {runtime}")
            continue
        package = tomllib.loads(cargo.read_text())
        entry = runtime / package.get("lib", {}).get("path", "src/lib.rs")
        if not entry.is_file():
            if runtime.parent.name in names:
                parser.error(f"selected runtime is incomplete: {entry}")
            print(f"Skipping unfinished peer runtime: {runtime.parent.name}", flush=True)
            continue
        shutil.copytree(runtime, stage / "plugins" / runtime.parent.name / "runtime")
    for name in names:
        source = ROOT / "plugins" / name
        target = stage / "plugins" / name
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / "plugin.json", target / "plugin.json")
        shutil.copytree(source / "compiler", target / "compiler")
        if (source / "tests").is_dir():
            shutil.copytree(source / "tests", target / "tests")
    # Public fixtures use paths relative to packages/fast, and may compose more
    # than one selected plugin. Keep their source tree with the build snapshot.
    shutil.copytree(ROOT / "packages/fast", stage / "packages/fast",
                    ignore=shutil.ignore_patterns("_out", ".ash", "node_modules", "*.wasm"))
    shutil.copytree(ROOT / "tests/integration", stage / "tests/integration",
                    ignore=shutil.ignore_patterns("_out", "*.wasm"))
    command = ["cargo", "generate-lockfile", "--manifest-path", str(stage / "Cargo.toml")]
    if args.offline:
        command.append("--offline")
    subprocess.run(command, check=True, cwd=stage)
    subprocess.run(["python3", str(stage / "scripts/build.py"), "--motoko", str(motoko),
                    "--skip-motoko-build", *names], check=True, cwd=stage)
    print(f"Isolated artifacts: {stage / 'dist'}", flush=True)
    print("Keep this snapshot for fixtures and benchmark provenance; shared dist/ was not changed.",
          flush=True)


if __name__ == "__main__":
    main()
