from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "test/compute-plugins"))
from fixture_tools import compile_plugin
compile_plugin(root / "_build/mutation-sdk-audit/probe", "probe.ml")
