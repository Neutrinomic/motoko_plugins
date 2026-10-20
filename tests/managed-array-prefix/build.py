#!/usr/bin/env python3
"""Build the test-only SDK client against the explicitly selected compiler."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--motoko", required=True, type=Path)
parser.add_argument("--output", type=Path, default=ROOT / "_build")
args = parser.parse_args()
sdk, output = args.motoko.resolve(), args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
probe = output / "probe"
probe.mkdir(exist_ok=True)
shutil.copyfile(ROOT / "probe.ml", probe / "probe.ml")
includes = []
for kind in ["byte", "native"]:
    for directory in sorted((sdk / "src/_build/default").glob(
            f"*/.*.objs/{kind}")):
        includes.extend(["-I", str(directory)])
subprocess.run(["ocamlfind", "ocamlopt", "-package", "num,wasm", *includes,
                "-shared", "-o", "plugin.cmxs", "probe.ml"],
               cwd=probe, check=True)
env = {**os.environ, "MOC_RELEASE_RTS": str(sdk / "rts/mo-rts.wasm"),
       "MOC_DEBUG_RTS": str(sdk / "rts/mo-rts-debug.wasm")}
compiler = [str(sdk / "bin/moc"), "--plugin", str(probe), "-Werror"]
for mode in [[], ["-iR", "-no-async", "-no-await"], ["-iR"]]:
    subprocess.run([*compiler, "-r", *mode, str(ROOT / "run.mo")],
                   env=env, check=True)
subprocess.run([*compiler, "-wasi-system-api", "-c", str(ROOT / "run.mo"),
                "-o", str(output / "run.wasm")], env=env, check=True)
subprocess.run(["wasm-validate", "--enable-memory64", "--enable-multi-memory",
                str(output / "run.wasm")], env=env, check=True)
subprocess.run(["wasmtime", "run", "-C", "cache=n", "-W",
                "nan-canonicalization=y", "-W", "memory64", "-W",
                "multi-memory", "-W", "bulk-memory", str(output / "run.wasm")],
               env=env, check=True)
subprocess.run([*compiler, "--sanity-checks", "--force-gc",
                "--enhanced-orthogonal-persistence", "-c", str(ROOT / "gc.mo"),
                "-o", str(output / "gc.wasm")], env=env, check=True)
print(f"Built managed array prefix probe and forced-GC actor: {output}")
