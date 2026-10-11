#!/usr/bin/env bash
# Prepared before readiness. Run only after the root agent confirms canonical
# compiler c320bf90d and all canonical plugin packages have been rebuilt.
set -euo pipefail
test "${1:-}" = --ready
cd /srv/shared/code/motoko_experiments/plugins
cb_int_compiler=/srv/shared/code/motoko_experiments/motoko_sha
cb_int_scratch=_build/opt-cbor-integrated
cb_int_report=benchmarks/results/optimization-round/integrated/cbor
cb_int_archive=benchmarks/results/optimization-round/cbor
python3 - <<'PY'
from pathlib import Path
import hashlib,json,subprocess
root=Path.cwd()
snapshot=root/'_build/opt-cbor-integrated/pre-ready-sha256.json'
if not snapshot.exists():
    snapshot=root/'benchmarks/results/optimization-round/integrated/cbor/pre-ready-sha256.json'
snap=json.loads(snapshot.read_text())
for name, expected in snap.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected, name
compiler=Path('/srv/shared/code/motoko_experiments/motoko_sha')
revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=compiler,text=True).strip()
assert revision.startswith('c320bf90d'), revision
build=json.loads((root/'dist/cbor/build.json').read_text())
assert build['motoko_revision']==revision and not build['motoko_dirty']
candidate=json.loads((root/'benchmarks/results/optimization-round/cbor/final-build.json').read_text())
for name, expected in candidate['source_sha256'].items():
    if name.startswith('plugins/cbor/'):
        assert build['source_sha256'][name]==expected,name
        assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
assert hashlib.sha256((compiler/'src/_build/default/exes/moc.exe').read_bytes()).hexdigest()==build['moc_sha256']
for name, expected in build['sha256'].items():
    assert hashlib.sha256((root/'dist/cbor'/name).read_bytes()).hexdigest()==expected,name
PY
mkdir -p "$cb_int_scratch"/{core,edges,errors,package} "$cb_int_report"
cp benchmarks/results/codec-comparison/cbor/main.mo benchmarks/results/codec-comparison/cbor/cases.json "$cb_int_scratch/core/"
cp "$cb_int_archive/edges/main.mo" "$cb_int_archive/edges/cases.json" "$cb_int_scratch/edges/"
cp "$cb_int_archive/errors/main.mo" "$cb_int_archive/errors/cases.json" "$cb_int_scratch/errors/"
cp dist/cbor/plugin.cmxs dist/cbor/runtime.wasm dist/cbor/build.json "$cb_int_scratch/package/"
cp dist/cbor/build.json "$cb_int_report/build.json"
python3 benchmarks/build-codec-comparison.py --motoko "$cb_int_compiler" \
  --deps /srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/deps \
  --out "$cb_int_scratch/core" --codec cbor
"$cb_int_compiler/bin/moc" --plugin dist/cbor "$cb_int_scratch/edges/main.mo" -o "$cb_int_scratch/edges/main.wasm"
"$cb_int_compiler/bin/moc" --plugin dist/cbor "$cb_int_scratch/errors/main.mo" -o "$cb_int_scratch/errors/main.wasm"
for cb_int_suite in core edges errors; do
  node benchmarks/run.mjs --wasm "$cb_int_scratch/$cb_int_suite/main.wasm" \
    --cases "$cb_int_scratch/$cb_int_suite/cases.json" \
    --out "$cb_int_report/$cb_int_suite.json" --label "integrated-cbor-$cb_int_suite" --trials 3 \
    --sdk-package /srv/shared/code/candidx/ts/package.json \
    --canonicalizer /srv/shared/code/candidx/ts/dist/index.js \
    --cbor-python /srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/oracle/bin/python
done
