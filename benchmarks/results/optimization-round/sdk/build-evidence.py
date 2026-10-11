from pathlib import Path
import hashlib
import json
import shutil
import subprocess

candidate = Path(__file__).resolve().parents[2]
baseline = Path('/srv/shared/code/motoko_experiments/motoko_sha')
out = Path(__file__).resolve().parent
fixture = candidate / 'test/compute-plugins/fixtures/callbacks/fixture_callbacks.ml'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
provenance = {'source': sha(out / 'main.mo'), 'fixture_source': sha(fixture),
              'compilers': {}}
for label, root in [('baseline', baseline), ('candidate', candidate)]:
    package = out / label
    package.mkdir(exist_ok=True)
    shutil.copy2(fixture, package / fixture.name)
    includes = []
    for kind in ('byte', 'native'):
        for directory in sorted((root / 'src/_build/default').glob(f'*/.*.objs/{kind}')):
            includes += ['-I', str(directory)]
    subprocess.run(['ocamlfind', 'ocamlopt', '-package', 'num,wasm', *includes,
                    '-shared', '-o', 'plugin.cmxs', fixture.name], cwd=package, check=True)
    subprocess.run([str(root / 'bin/moc'), '--plugin', str(package),
                    str(out / 'main.mo'), '-o', str(package / 'main.wasm')], check=True)
    provenance['compilers'][label] = {
        'revision': subprocess.check_output(['git', '-C', root, 'rev-parse', 'HEAD'], text=True).strip(),
        'diff': subprocess.check_output(['git', '-C', root, 'diff'], text=True),
        'moc': sha(root / 'src/moc'),
        'release_rts': sha(root / 'rts/mo-rts.wasm'),
        'debug_rts': sha(root / 'rts/mo-rts-debug.wasm'),
        'fixture': sha(package / 'plugin.cmxs'),
        'wasm': sha(package / 'main.wasm'),
    }
(out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
(out / 'cases.json').write_text(json.dumps({
    'cases': [{'name': f'tabulate-{size}', 'index': index, 'family': 'SDK array construction',
               'phases': [{'label': kind, 'method': kind, 'kind': 'checked_decode',
                           'require_no_gc': True} for kind in ['scalar', 'nested']]}
              for index, size in enumerate([0, 1, 257, 4096])],
    'correctness': 'Each retained array element and nested record/array is checked outside the timed region.',
}, indent=2) + '\n')
