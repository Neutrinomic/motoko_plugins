#!/usr/bin/env python3
"""Copy delivered curve workloads, adding untimed memory observation only."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
MANIFEST = BENCH / "round2/api-plugin-cases.json"
MEMORY = """  // Round three: queried outside the measured operation.
  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
     totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
"""


def copy_case(case):
    original = BENCH / case["source"]
    source = original.read_text()
    assert "public query func memory(" not in source
    closing = source.rfind("}")
    assert closing >= 0 and not source[closing + 1:].strip()
    output = HERE / "controls" / case["name"] / "main.mo"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(source[:closing] + MEMORY + source[closing:])
    return {**case, "source": output.relative_to(BENCH).as_posix(),
            "memory_metrics": True, "control_source": case["source"],
            "control_source_sha256": hashlib.sha256(original.read_bytes()).hexdigest()}


def main():
    cases = [copy_case(case) for case in json.loads(MANIFEST.read_text())["cases"]
             if case["family"] in {"secp256k1", "p256", "bls12-381"}]
    (HERE / "control-cases.json").write_text(json.dumps({
        "methodology": "Delivered round-two curve fixtures and exact oracles; the only actor change is an untimed memory query.",
        "source_manifest_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        "cases": cases,
    }, indent=2) + "\n")
    pure_manifest = BENCH / "round2/api-pure-cases.json"
    pure_cases = [copy_case(case) for case in json.loads(pure_manifest.read_text())["cases"]
                  if case.get("api") in {"Secp256k1.verifyPrehash", "P256.verifyPrehash"}]
    assert len(pure_cases) == 2
    (HERE / "motoko-control-cases.json").write_text(json.dumps({
        "methodology": "Pinned Motoko ECDSA 8.0.1 adapters for the exact same valid compact low-S signature, compressed key and 32-byte digest as the corresponding plugin controls. Decoding and validation remain timed.",
        "source_manifest_sha256": hashlib.sha256(pure_manifest.read_bytes()).hexdigest(),
        "cases": pure_cases,
    }, indent=2) + "\n")
    print(f"Generated {len(cases)} delivered-plugin controls")


if __name__ == "__main__":
    main()
