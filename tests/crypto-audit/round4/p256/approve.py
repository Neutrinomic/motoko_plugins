#!/usr/bin/env python3
"""Package this completed manual audit's final evidence and consistency checks."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASELINE = '0e1e96a4c325bdfebc627f0c16d546cb39c16a70'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def original(path):
    return subprocess.check_output(['git','show',BASELINE+':'+str(path)],cwd=ROOT)

def main():
    build = json.loads((ROOT/'dist/p256/build.json').read_text())
    for name,digest in build['source_sha256'].items():
        assert sha(ROOT/name) == digest, name
    assert build['sha256']['runtime.wasm'] == 'b4b1f17afd54c3928bf037da4f1ddea0f3bc44d7e5bcde19f61c22e32ad0f378'
    checks = {}
    paths = sorted((ROOT/'plugins/p256/compiler').rglob('*')) + [ROOT/'packages/fast/src/P256.mo', ROOT/'plugins/p256/runtime/src/generated_table.rs']
    for path in paths:
        if not path.is_file(): continue
        rel = path.relative_to(ROOT)
        if path.is_symlink():
            assert original(rel) == str(path.readlink()).encode()
            target = path.resolve().relative_to(ROOT.resolve())
            assert original(target) == path.read_bytes()
        else:
            assert original(rel) == path.read_bytes(), str(rel)
        checks[str(rel)] = sha(path)
    gates = {}
    for phase in ['native','motoko','public','ash','stack']:
        file = HERE/f'execution-{phase}.json'
        report = json.loads(file.read_text())
        assert report['passed']
        assert report['artifact_sha256']['runtime.wasm'] == build['sha256']['runtime.wasm']
        for command in report['commands']:
            artifact = HERE/command['stored_log']
            assert sha(artifact) == command['stored_log_sha256']
            assert hashlib.sha256(gzip.decompress(artifact.read_bytes())).hexdigest() == command['log_sha256']
        for name,digest in report.get('public_fixture_sha256',{}).items():
            assert sha(ROOT/name) == digest
        gates[phase] = {'report':file.name, 'report_sha256':sha(file), 'passed':True}
    approval = {'approved':True,
        'scope':'P256 round4 selected C5 arithmetic; manual source/emitted-Wasm review, independent native/Motoko/public tests and matched performance evidence',
        'source_checkpoint':subprocess.check_output(['git','rev-parse','989c6c4'],cwd=ROOT,text=True).strip(),
        'baseline':BASELINE,
        'artifacts':{n:sha(ROOT/'dist/p256'/n) for n in ['runtime.wasm','plugin.cmxs','build.json']},
        'source_sha256':build['source_sha256'], 'compiler_sha256':build['moc_sha256'],
        'unchanged_compiler_component_public_api_and_prepared_table':checks,
        'gates':gates, 'native_test_count_each_profile':18, 'ash_tests':19,
        'independent_verification_cases':184, 'independent_scalar_square_inverse_cases':1085,
        'independent_derivations':512, 'independent_exact_signatures':43,
        'motoko_derivation_cases':72, 'public_motoko_fixtures':2,
        'production_findings':[],
        'resolved_test_findings':['Reserved label field renamed by owner to name in new Motoko/Ash boundary fixtures.',
                                 'Missing ignored core dependency linked temporarily for public gates; removed after execution.'],
        'limits':['Source/data-flow review and bounded tests are not a formal whole-library constant-time proof.',
                  'No SDK/API/prepared representation change; earlier nominal/GC audit remains applicable.',
                  'Paired benchmark allocation and sampled memory unchanged; runtime grows 14570 bytes and linked actors 14425 bytes.']}
    for name in ['scalar-chain.json','wasm-review.json','benchmark-acceptance.json','environment.json']:
        approval[name] = sha(HERE/name)
    files = subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard',str(HERE.relative_to(ROOT))],cwd=ROOT,text=True).splitlines()
    approval['evidence_sha256'] = {str((ROOT/name).relative_to(HERE)):sha(ROOT/name) for name in sorted(set(files)) if Path(name).name != 'approval.json'}
    (HERE/'approval.json').write_text(json.dumps(approval,indent=2)+'\n')
    print(json.dumps({'approved':True,'source_pins':len(build['source_sha256']),
                      'evidence_files':len(approval['evidence_sha256']), 'unchanged_files':len(checks)}))

if __name__ == '__main__': main()
