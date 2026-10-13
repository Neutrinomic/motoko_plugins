#!/usr/bin/env python3
"""Read a built runtime and print conservative static shadow-stack evidence.

Requires WABT wasm2wat. Rejects unfamiliar call/stack patterns instead of
silently treating them as zero. Does not build or modify any input file.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def require(condition, message):
    if not condition:
        raise ValueError(message)


def uleb(data, offset):
    value = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7
        require(shift < 70, "Invalid LEB128")


def binary_function_count(data):
    require(data[:8] == b"\0asm\1\0\0\0", "Expected Wasm version 1")
    offset = 8
    counts = {}
    while offset < len(data):
        section = data[offset]
        size, start = uleb(data, offset + 1)
        offset = start + size
        require(offset <= len(data), "Truncated section")
        if section in (3, 10):
            require(section not in counts, "Duplicate function/code section")
            counts[section] = uleb(data, start)[0]
    require(counts.get(3) == counts.get(10), "Function/code counts disagree")
    return counts.get(3, 0)


def inspect_frame(name, body):
    # WABT's unfolded text puts each instruction on its own line. Remove
    # index/label comments and declaration lines, preserving instruction order.
    body = re.sub(r"\(;.*?;\)", "", body, flags=re.S)
    lines = [line.strip().rstrip(")").strip() for line in body.splitlines()[1:]]
    lines = [line for line in lines if line and not line.startswith("(")]
    accesses = [i for i, line in enumerate(lines) if "__stack_pointer" in line]
    if not accesses:
        return 0
    require(len(lines) >= 5, f"{name}: short stack prologue")
    frame = re.fullmatch(r"i64.const ([0-9]+)", lines[1])
    local = re.fullmatch(r"local.tee ([0-9]+)", lines[3])
    require(lines[0] == "global.get $__stack_pointer" and frame and local
            and lines[2] == "i64.sub" and lines[4] == "global.set $__stack_pointer",
            f"{name}: unfamiliar stack prologue")
    size, base = int(frame[1]), local[1]
    require(size > 0, f"{name}: nonpositive frame")
    # The frame-base local must remain unchanged throughout the function.
    require(not any(re.fullmatch(rf"local\.(?:set|tee) {base}", line)
                    for line in lines[4:]), f"{name}: frame-base local changes")
    restore = [f"local.get {base}", f"i64.const {size}", "i64.add",
               "global.set $__stack_pointer"]
    require(len(accesses) >= 3, f"{name}: no stack restoration")
    for index in accesses:
        if index in (0, 4):
            continue
        require(index >= 3 and lines[index - 3:index + 1] == restore,
                f"{name}: unfamiliar stack access at instruction {index}")
    return size


def analyze(runtime, wasm2wat):
    data = runtime.read_bytes()
    wat = subprocess.check_output([wasm2wat, "--enable-all", str(runtime)], text=True)
    require(not re.search(r"^  \(import .*\(func\b", wat, re.M),
            "Function imports require an external stack bound")
    require(not re.search(r"^\s+(?:return_call|call_indirect|return_call_indirect|call_ref|return_call_ref)\b",
                          wat, re.M), "Unsupported indirect/tail/reference call")
    # Split at every top-level module field in canonical WABT output. Confirm
    # complete defined-function coverage against both binary section counts.
    fields = re.split(r"(?=^  \()", wat, flags=re.M)
    bodies = {}
    for field in fields:
        if not field.startswith("  (func "):
            continue
        match = re.match(r"  \(func (\$[^\s()]+)(?:\s|\))", field)
        require(match is not None, "Unnamed/unrecognized function")
        name = match[1]
        require(name not in bodies, f"Duplicate function {name}")
        bodies[name] = field
    require(len(bodies) == binary_function_count(data),
            "Parsed WAT does not cover every binary-defined function")
    frames = {name: inspect_frame(name, body) for name, body in bodies.items()}
    calls = {name: sorted(set(re.findall(r"^\s+call (\$[^\s()]+)", body, re.M)))
             for name, body in bodies.items()}
    call_count = len(re.findall(r"^\s+call\b", wat, re.M))
    named_call_count = sum(len(re.findall(r"^\s+call (\$[^\s()]+)", body, re.M))
                           for body in bodies.values())
    require(call_count == named_call_count, "Unparsed direct call")
    require(all(child in bodies for children in calls.values() for child in children),
            "Direct call target outside parsed module")
    completed, active = {}, set()

    def visit(name):
        require(name not in active, f"Recursive direct-call cycle at {name}")
        if name in completed:
            return completed[name]
        active.add(name)
        children = [visit(child) for child in calls[name]]
        suffix = max(children, key=lambda item: item[0]) if children else (0, [])
        completed[name] = frames[name] + suffix[0], [name, *suffix[1]]
        active.remove(name)
        return completed[name]

    # Check all functions, including functions unreachable from public exports.
    for name in bodies:
        visit(name)
    exports = re.findall(r'^  \(export "([^"]+)" \(func (\$[^\s()]+)\)\)', wat, re.M)
    require(exports, "No function exports found")
    return {
        "schema": 1,
        "runtimeSha256": hashlib.sha256(data).hexdigest(),
        "runtimeBytes": len(data),
        "wasm2watVersion": subprocess.check_output([wasm2wat, "--version"], text=True).strip(),
        "definedFunctions": len(bodies),
        "functionsWithFrames": sum(value != 0 for value in frames.values()),
        "directCallSites": call_count,
        "allFunctionsCovered": True,
        "allDirectCallsResolved": True,
        "directCallGraphAcyclic": True,
        "indirectOrTailCalls": 0,
        "functionImports": 0,
        "exports": {label: {"frameBytes": frames[name],
                             "conservativeAdditionalShadowStackBytes": completed[name][0],
                             "maximumPath": completed[name][1]} for label, name in exports},
        "functions": {name: {"frameBytes": frames[name], "calls": calls[name],
                              "maximumPathBytes": completed[name][0]}
                      for name in sorted(bodies)},
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--wasm2wat", default="wasm2wat")
    parser.add_argument("--expect-sha256", help="Fail if the runtime differs from this evidence")
    args = parser.parse_args()
    report = analyze(args.runtime, args.wasm2wat)
    require(args.expect_sha256 is None or report["runtimeSha256"] == args.expect_sha256,
            "Runtime hash differs from expected audit input")
    print(json.dumps(report, indent=2, sort_keys=True))
