#!/usr/bin/env python3
"""Build standalone native Motoko plugins against one compiler checkout."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WARNINGS = "+a-4-23-27-30-32-42-44-45-58-60-69-70"


def run(command, *, cwd=ROOT, env=None, capture=False, label=None):
    if label:
        print(label, flush=True)
    return subprocess.run(
        [str(part) for part in command], cwd=cwd, env=env, check=True,
        text=True, stdout=subprocess.PIPE if capture else None,
    ).stdout


def fail(message):
    raise ValueError(message)


def discover(names):
    available = {}
    for path in sorted((ROOT / "plugins").glob("*/plugin.json")):
        manifest = json.loads(path.read_text())
        if not isinstance(manifest, dict):
            fail(f"{path}: expected a JSON object")
        name = manifest.get("name", "")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or name != path.parent.name:
            fail(f"{path}: name must match its directory and use lowercase identifiers")
        crate = manifest.get("runtime_crate", "")
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", crate):
            fail(f"{path}: invalid runtime_crate")
        packages = manifest.get("ocaml_packages", [])
        if not isinstance(packages, list) or not all(
            isinstance(package, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", package)
            for package in packages
        ):
            fail(f"{path}: ocaml_packages must be a list of findlib package names")
        manifest["ocaml_packages"] = packages
        available[name] = manifest
    if not available:
        fail("No plugins/*/plugin.json manifests found")
    for name in names:
        if name not in available:
            fail(f"Unknown plugin {name!r}; available: {', '.join(available)}")
    return [available[name] for name in dict.fromkeys(names or available)]


def build_environment():
    env = os.environ.copy()
    for command in ("ocamlc", "ocamlfind", "dune", "cargo", "rustc", "wasm-validate"):
        if not shutil.which(command):
            fail(f"Missing {command}; run this script in the Motoko checkout's Nix development shell")
    version = run(["ocamlc", "-version"], capture=True).strip()
    major, minor = (int(part) for part in version.split(".")[:2])
    ocaml_lib = Path(run(["ocamlc", "-where"], capture=True).strip())
    # OCaml 5.4 absorbed Bigarray, but the pinned Nix findlib metadata still
    # refers to its removed archive. Override metadata only, outside Motoko.
    if (major, minor) >= (5, 4) and not (ocaml_lib / "bigarray.cmxa").exists():
        compat = ROOT / "_build/ocaml-compat"
        (compat / "bigarray").mkdir(parents=True, exist_ok=True)
        (compat / "bigarray/META").write_text(
            f'version = "{version}"\n'
            'description = "Bigarray is in the standard library"\nrequires = ""\n'
        )
        env["OCAMLPATH"] = str(compat) + (
            os.pathsep + env["OCAMLPATH"] if env.get("OCAMLPATH") else ""
        )
    return env, version


def prepare_host(motoko, env, skip_build):
    if not (motoko / "src/codegen/plugin_codegen.mli").is_file():
        fail(f"{motoko} does not contain a Motoko compiler with the plugin API")
    if not skip_build:
        run(["bash", "src/source_id/gen.sh"], cwd=motoko, env=env)
        run(
            ["dune", "build", "--root", "src", "--profile=release", "exes/moc.exe"],
            cwd=motoko, env=env, label="Building the dynamically linked Motoko compiler",
        )
    host_build = motoko / "src/_build/default"
    moc = host_build / "exes/moc.exe"
    if not moc.is_file():
        fail(f"Missing {moc}; omit --skip-motoko-build to build the compiler")
    # Dune places each host library's interfaces and native optimization
    # information in these directories. Do not link its archives into plugins:
    # all host modules must be resolved from the already-running moc process.
    includes = sorted(host_build.glob("*/.*.objs/byte"))
    includes += sorted(host_build.glob("*/.*.objs/native"))
    if not any((path / "codegen__Plugin_codegen.cmi").is_file() for path in includes):
        fail("Missing compiler plugin interfaces; rebuild the matching Motoko checkout")
    return moc, includes


def compiler_plugin(manifest, includes, work, env):
    name = manifest["name"]
    source = ROOT / "plugins" / name / "compiler"
    sources = sorted(source.glob("*.mli")) + sorted(source.glob("*.ml"))
    if not any(path.suffix == ".ml" for path in sources):
        fail(f"{source}: expected OCaml source files")
    pack = "Motoko_plugin_" + name
    common = []
    if manifest["ocaml_packages"]:
        common += ["-package", ",".join(manifest["ocaml_packages"])]
    common += ["-I", str(work)]
    for include in includes:
        common += ["-I", str(include)]
    # ocamldep's text output is ambiguous for paths with spaces. Run it on
    # relative basenames instead, so source checkouts may live anywhere.
    ordered = run(
        ["ocamlfind", "ocamldep", *common, "-sort", *(path.name for path in sources)],
        cwd=source, env=env, capture=True,
    ).split()
    objects = []
    for filename in ordered:
        path = source / filename
        target = work / (path.stem + (".cmi" if path.suffix == ".mli" else ".cmx"))
        run(
            ["ocamlfind", "ocamlopt", *common, "-w", WARNINGS,
             "-warn-error", "+a", "-for-pack", pack, "-c", "-o", target, path],
            env=env, label=f"[{name}] compiling {filename}",
        )
        if path.suffix == ".ml":
            objects.append(target)
    packed = work / (pack + ".cmx")
    run(["ocamlfind", "ocamlopt", *common, "-pack", "-o", packed, *objects], env=env)
    output = work / "plugin.cmxs"
    run(
        ["ocamlfind", "ocamlopt", *common, "-shared", "-linkall", "-o", output, packed],
        env=env,
    )
    return output


def runtimes(manifests, motoko, env):
    runtime_env = env.copy()
    flags = [f"--remap-path-prefix={ROOT}=.", "-C", "link-arg=--import-memory"]
    # Keep caller flags, including profiling/debug options, while ensuring the
    # shared-memory ABI is used. This matches the compiler's own RTS target.
    caller_flags = (
        env["CARGO_ENCODED_RUSTFLAGS"].split("\x1f")
        if env.get("CARGO_ENCODED_RUSTFLAGS") else shlex.split(env.get("RUSTFLAGS", ""))
    )
    runtime_env["CARGO_ENCODED_RUSTFLAGS"] = "\x1f".join(flags + caller_flags)
    cargo_target = ROOT / "_build/cargo"
    target = motoko / "rts/motoko-rts/wasm64-none-shared.json"
    if not target.is_file():
        fail(f"Missing compiler runtime target {target}")
    command = [
        "cargo", "build", "--manifest-path", ROOT / "Cargo.toml", "--locked",
        "--release", "--target", target, "--target-dir", cargo_target,
        "-Zjson-target-spec", "-Zbuild-std=core,alloc",
    ]
    for manifest in manifests:
        command += ["--package", manifest["runtime_crate"]]
    run(command, env=runtime_env, label="Building Wasm runtimes")
    outputs = {}
    for manifest in manifests:
        wasm = cargo_target / target.stem / "release" / (
            manifest["runtime_crate"].replace("-", "_") + ".wasm"
        )
        run(["wasm-validate", "--enable-memory64", wasm], env=env)
        outputs[manifest["name"]] = wasm
    return outputs


def git_revision(path):
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=path, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def git_dirty(path):
    result = subprocess.run(
        ["git", "status", "--porcelain"], cwd=path, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return bool(result.stdout.strip()) if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko", type=Path, required=True, help="Motoko source checkout")
    parser.add_argument(
        "--skip-motoko-build", action="store_true",
        help="use an already-built dynamic release moc and its matching interfaces",
    )
    parser.add_argument("plugins", nargs="*", help="plugin names; defaults to all manifests")
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    manifests = discover(args.plugins)
    env, ocaml_version = build_environment()
    moc, includes = prepare_host(motoko, env, args.skip_motoko_build)
    runtime_outputs = runtimes(manifests, motoko, env)
    metadata = {
        "motoko_revision": git_revision(motoko),
        "motoko_dirty": git_dirty(motoko),
        "motoko_version": run([moc, "--version"], env=env, capture=True).strip(),
        "ocaml_version": ocaml_version,
        "rustc_version": run(["rustc", "--version"], env=env, capture=True).strip(),
        "plugins_revision": git_revision(ROOT),
        "plugins_dirty": git_dirty(ROOT),
        "platform": sys.platform,
        "architecture": platform.machine(),
    }
    (ROOT / "_build/compiler").mkdir(parents=True, exist_ok=True)
    for manifest in manifests:
        name = manifest["name"]
        # Fresh intermediates prevent old interfaces or another compiler's
        # artifacts from leaking into a newly packaged plugin.
        with tempfile.TemporaryDirectory(prefix=name + "-", dir=ROOT / "_build/compiler") as temp:
            work = Path(temp)
            compiled = compiler_plugin(manifest, includes, work, env)
            staged = work / "package"
            staged.mkdir()
            shutil.copy2(compiled, staged / "plugin.cmxs")
            shutil.copy2(runtime_outputs[name], staged / "runtime.wasm")
            probe = work / "check.mo"
            probe.write_text("()\n")
            run(
                [moc, "--plugin", staged, "--check", probe], env=env,
                label=f"[{name}] checking compatibility with the selected compiler",
            )
            hashes = {
                path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in (staged / "plugin.cmxs", staged / "runtime.wasm")
            }
            (staged / "build.json").write_text(json.dumps(
                {"name": name, **metadata, "sha256": hashes}, indent=2,
            ) + "\n")
            destination = ROOT / "dist" / name
            destination.parent.mkdir(exist_ok=True)
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(staged, destination)
            print(f"[{name}] {destination}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Plugin build failed: {error}", file=sys.stderr)
        print(
            "Build moc and plugins together in the selected Motoko checkout's Nix "
            "development shell. Native plugins require a matching, dynamically linked compiler.",
            file=sys.stderr,
        )
        sys.exit(1)
