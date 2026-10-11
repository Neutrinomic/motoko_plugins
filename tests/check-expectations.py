#!/usr/bin/env python3
"""Reject accepted failures that prevent a successful runtime fixture executing."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
invalid = []
for tree in (root / "plugins", root / "packages", root / "tests/integration"):
    for category in ("run", "run-drun", "trap"):
        for directory in tree.glob(f"**/{category}/ok"):
            for expected in directory.glob("*.ret.ok"):
                # Trap fixtures must compile successfully, but runtime failure
                # is their intended result. Successful fixtures must do both.
                if category == "trap" and not expected.name.endswith(".tc.ret.ok"):
                    continue
                if expected.read_text().strip() not in ("", "Return code 0"):
                    invalid.append(expected.relative_to(root))
if invalid:
    raise SystemExit("Unexpected accepted failures:\n" + "\n".join(map(str, invalid)))
