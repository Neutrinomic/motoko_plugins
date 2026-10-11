#!/usr/bin/env python3
"""Use the CandidX repository's generated compiler probes with this plugin.

Pass this executable as both --moc and --runtime-moc to CandidX's tests/fuzz.py
or tests/verify.py, with --skip-wasm. Set CANDIDX_TEST_ROOT to a directory
containing their --out directory (default: this repo's _build/candidx-tests).

Set MOTOKO_ROOT to the compiler checkout; the adapter loads dist/candidx from
this repository with that checkout's bin/moc. To test a
frozen build, set CANDIDX_TEST_ARTIFACTS to a directory containing moc,
mo-rts.wasm, mo-rts-debug.wasm, and candidx/{plugin.cmxs,runtime.wasm}.

Only generated probes are supported: their unqualified legacy operator calls
are changed to Prim.to_candid_canonical in adjacent .plugin.mo copies and
their Result is unwrapped for the legacy probe API. Expected #err results
become probe traps. Values, assertions, and oracle sources are preserved. This is not a general
Motoko source rewriter. Every translation and its source hashes are logged in
CANDIDX_TEST_ROOT/compiler-invocations.jsonl.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[3]
CALL = re.compile(r"(?<![A-Za-z0-9_.])to_candid_canonical\s*(?=\()")


def translate_probe(source):
    """Wrap generated legacy calls without changing their input expressions."""
    calls = list(CALL.finditer(source))
    for call in reversed(calls):
        start = source.index("(", call.end())
        depth = 0
        quote = None
        position = start
        while position < len(source):
            char = source[position]
            if quote is not None:
                if char == "\\":
                    position += 2
                    continue
                if char == quote:
                    quote = None
            elif char in ("\"", "'"):
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    break
            position += 1
        if depth:
            raise RuntimeError("Unclosed legacy call in generated probe")
        source = (source[:call.start()] + "__candidxExpectOk(Prim.to_candid_canonical" +
                  source[call.end():position + 1] + ")" + source[position + 1:])
    if calls:
        imports = list(re.finditer(r"^import [^\n]+;", source, re.MULTILINE))
        if not imports:
            raise RuntimeError("Generated probe has no imports")
        insert = imports[-1].end()
        source = source[:insert] + """
func __candidxExpectOk(result : { #ok : Blob; #err : Text }) : Blob {
  switch result {
    case (#ok bytes) bytes;
    case (#err message) Prim.trap("CandidX error: " # message);
  }
};
""" + source[insert:]
    return source, len(calls)


def main():
    probe_root = Path(os.environ.get("CANDIDX_TEST_ROOT", ROOT / "_build/candidx-tests")).resolve()
    probe_root.mkdir(parents=True, exist_ok=True)
    arguments = sys.argv[1:]
    rewrites = []
    for i, argument in enumerate(arguments):
        source = Path(argument)
        if source.suffix != ".mo" or not source.is_file():
            continue
        original = source.read_text()
        translated, count = translate_probe(original)
        if not count:
            continue
        source = source.resolve()
        if not source.is_relative_to(probe_root):
            raise RuntimeError(f"Refusing to rewrite a non-probe source: {source}")
        if 'import Prim "mo:⛔";' not in original:
            raise RuntimeError(f"Generated direct probe has no Prim binding: {source}")
        destination = source.with_name(source.stem + ".plugin.mo")
        if not destination.resolve().is_relative_to(probe_root):
            raise RuntimeError(f"Translated probe escapes CANDIDX_TEST_ROOT: {destination}")
        destination.write_text(translated)
        arguments[i] = str(destination)
        rewrites.append({
            "source": str(source), "translated": str(destination), "calls": count,
            "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
            "translated_sha256": hashlib.sha256(translated.encode()).hexdigest(),
        })
    with (probe_root / "compiler-invocations.jsonl").open("a") as log:
        log.write(json.dumps({"arguments": arguments, "rewrites": rewrites}) + "\n")

    environment = dict(os.environ)
    frozen = environment.get("CANDIDX_TEST_ARTIFACTS")
    if frozen:
        artifacts = Path(frozen).resolve()
        compiler = artifacts / "moc"
        plugin = artifacts / "candidx"
        environment["MOC_RELEASE_RTS"] = str(artifacts / "mo-rts.wasm")
        environment["MOC_DEBUG_RTS"] = str(artifacts / "mo-rts-debug.wasm")
    else:
        motoko_root = environment.get("MOTOKO_ROOT")
        if not motoko_root:
            raise RuntimeError("Set MOTOKO_ROOT to the Motoko compiler checkout")
        compiler = Path(motoko_root).resolve() / "bin/moc"
        plugin = ROOT / "dist/candidx"
    os.execve(compiler, [str(compiler), "--plugin", str(plugin), *arguments], environment)


if __name__ == "__main__":
    main()
