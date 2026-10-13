#!/usr/bin/env python3
"""Assemble the final public signature cohorts, preserving their exact oracles."""
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
spec = importlib.util.spec_from_file_location("controls", HERE / "generate-controls.py")
controls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controls)


def main():
    sources = [
        ("control-cases.json", "secp256k1"),
        ("p256/cases.json", None),
        ("bls12-381/cohort.json", None),
        ("ed25519/cases.json", None),
        ("ml-dsa/cases.json", None),
        ("rsa/cases.json", None),
    ]
    cases = []
    manifests = {}
    for name, family in sources:
        manifest = HERE / name
        manifests[name] = hashlib.sha256(manifest.read_bytes()).hexdigest()
        data = json.loads(manifest.read_text())
        for original in data["cases"]:
            if family and original["family"] != family:
                continue
            case = dict(original)
            assert case.get("plugins"), "Final signature cohort must use plugins"
            case.setdefault("family", name.split("/")[0])
            # Old screening manifests called the Wasm plugin 'native'. Human
            # reports reserve Motoko/native for the separate library adapter.
            case["implementation"] = "fast"
            if not case.get("memory_metrics", False):
                source = BENCH / case["source"]
                text = source.read_text()
                assert "public query func memory(" not in text
                end = text.rfind("}")
                assert end >= 0 and not text[end + 1:].strip()
                target = HERE / "final-cases" / case["name"] / "main.mo"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text[:end] + controls.MEMORY + text[end:])
                case.update(source=target.relative_to(BENCH).as_posix(),
                            memory_metrics=True,
                            original_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            cases.append(case)
    assert len({(c["name"], c["implementation"]) for c in cases}) == len(cases)
    (HERE / "final-cases.json").write_text(json.dumps({
        "source_manifests_sha256": manifests,
        "methodology": "Final public plugin calls with independently pinned expected outputs and untimed memory snapshots. New algorithms are absolute costs, not optimization speedups against a different scheme.",
        "cases": cases,
    }, indent=2) + "\n")
    print(f"Assembled {len(cases)} final signature cases")


if __name__ == "__main__":
    main()
