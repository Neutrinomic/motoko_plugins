#!/usr/bin/env python3
"""Conservative Wasm stack check, including LLVM's leaf red-zone form."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
BASE = HERE.parents[1] / "round3/ml-dsa/stack/analyze.py"
spec = importlib.util.spec_from_file_location("base_stack_audit", BASE)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
original = base.inspect_frame
red_zones = {}


def inspect_frame(name, body):
    try:
        return original(name, body)
    except ValueError:
        # LLVM emits small leaf temporaries below the current stack pointer
        # without changing the global. Accept only the explicit fixed-size
        # form, with no nested calls, mutations of the base, or other access
        # to the stack-pointer global. Its conservative bound is the full
        # red-zone reservation, counted exactly like a normal leaf frame.
        text = re.sub(r"\(;.*?;\)", "", body, flags=re.S)
        lines = [line.strip().rstrip(")").strip() for line in text.splitlines()[1:]]
        lines = [line for line in lines if line and not line.startswith("(")]
        frame = re.fullmatch(r"i64.const ([0-9]+)", lines[1]) if len(lines) > 3 else None
        local = re.fullmatch(r"local.tee ([0-9]+)", lines[3]) if len(lines) > 3 else None
        valid = (frame is not None and local is not None
                 and lines[0] == "global.get $__stack_pointer" and lines[2] == "i64.sub"
                 and [i for i, line in enumerate(lines) if "__stack_pointer" in line] == [0]
                 and int(frame[1]) > 0
                 and not any(re.fullmatch(rf"local\.(?:set|tee) {local[1]}", line) for line in lines[4:])
                 and not any(re.match(r"(?:return_call|call)(?:\s|_)", line) for line in lines))
        if not valid:
            raise
        red_zones[name] = int(frame[1])
        return int(frame[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--expect-sha256", required=True)
    args = parser.parse_args()
    base.inspect_frame = inspect_frame
    report = base.analyze(args.runtime, "wasm2wat")
    assert report["runtimeSha256"] == args.expect_sha256
    report["baseAnalyzerSha256"] = hashlib.sha256(BASE.read_bytes()).hexdigest()
    report["leafRedZones"] = red_zones
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
