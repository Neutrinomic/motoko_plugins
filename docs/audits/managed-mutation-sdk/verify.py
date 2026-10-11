"""Verify actual successful stages, not only test-runner's expectation status."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
for name in ("captured-field", "subtype"):
    out = root / "run/_out"
    for stage in ("tc", "comp", "valid", "run", "run-ir", "run-low", "wasm-run"):
        path = out / f"{name}.{stage}"
        assert path.is_file(), path
        assert not path.read_bytes(), (path, path.read_text())
    assert not list(out.glob(f"{name}.*.ret")), name
actor = root / "run-drun/_out/fragmented-gc.drun-run"
text = actor.read_text()
assert not re.search(r"ingress Err|trapped|assertion failed|Error from Canister", text), text
assert text.count("debug.print: phase ") == 16
assert text.count("debug.print: phase 2") >= 1
assert text.count("debug.print: phase 3") >= 1
assert text.count("debug.print: phase 4") >= 1
assert "managed mutation passed fragmented Mark and Update phases" in text
assert not list((root / "run-drun/_out").glob("fragmented-gc.*.ret"))
print("Independent audit passed: two programs across four execution engines; "
      "16 IC mutation messages including observed Mark, Evacuate, Update, "
      "and actual managed-array forwarding.")
