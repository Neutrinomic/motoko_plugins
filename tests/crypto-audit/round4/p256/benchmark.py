#!/usr/bin/env python3
"""Independently accept the paired final round4 P256 raw measurements."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def stats(values):
    return {'median': statistics.median(values), 'range': [min(values), max(values)]}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    comparison_file = ROOT / 'benchmarks/crypto/round4/p256/comparison-final.json'
    comparison = json.loads(comparison_file.read_text())
    audit = json.loads((HERE / 'execution-native.json').read_text())
    assert comparison['case_count'] == 28 and comparison['trials_per_case_per_revision'] == 3
    assert comparison['baseline']['environment'] == comparison['candidate']['environment']
    assert comparison['baseline']['builder_sha256'] == comparison['candidate']['builder_sha256']
    assert comparison['baseline']['actor_sources'] == comparison['candidate']['actor_sources']
    reports = {case['name']: case for case in comparison['cases']}
    assert len(reports) == 28
    raw = {}
    summary = {'accepted': True, 'case_count': 28, 'observations': 168, 'stages': {},
               'same_environment_and_compile_flags': True, 'trial_metrics_identical': True,
               'allocation_and_sampled_memory_unchanged': True, 'audited_candidate_parity': True}
    for side in ['baseline', 'candidate']:
        stage = args.results.resolve() / comparison[side]['stage']
        build = json.loads((stage / 'build.json').read_text())
        results = json.loads((stage / 'results.json').read_text())
        assert build['complete'] and results['complete'] and results['failed_measurements'] == 0
        assert build['expected_case_count'] == results['expected_case_count'] == 28
        assert results['trials'] == 3 and build['stage'] == results['stage'] == stage.name
        assert sha(stage / 'build.json') == results['build_sha256'] == comparison[side]['build_sha256']
        assert sha(stage / 'results.json') == comparison[side]['results_sha256']
        assert build['compiler_sha256'] == audit['compiler_sha256']
        assert sha(stage / 'inputs/toolchain/moc') == audit['compiler_sha256']
        for env, (name, digest) in audit['rts_sha256'].items():
            assert sha(stage / 'inputs/toolchain' / name) == digest
            assert comparison[side]['environment']['rts_sha256'][env] == digest
        for name, digest in build['frozen_inputs_sha256'].items():
            assert sha(stage / 'inputs' / name) == digest, (side, name)
        plugin = comparison[side]['plugins']['p256']
        metadata = json.loads((stage / 'inputs/dist/p256/build.json').read_text())
        assert sha(stage / 'inputs/dist/p256/build.json') == plugin['build_sha256']
        assert metadata['source_sha256'] == plugin['pins']['sources']
        assert metadata['sha256'] == plugin['pins']['artifacts']
        for name, digest in metadata['source_sha256'].items():
            # Builder stores the complete source map; all relevant P256 source
            # is independently frozen in the stage's inputs.
            if name.startswith('plugins/p256/'):
                assert sha(stage / 'inputs' / name) == digest, (side, name)
        for name, digest in plugin['pins']['artifacts'].items():
            assert sha(stage / 'inputs/dist/p256' / name) == digest
        if side == 'candidate':
            for name, digest in audit['artifact_sha256'].items():
                assert sha(stage / 'inputs/dist/p256' / name) == digest == sha(ROOT / 'dist/p256' / name)
            for name, digest in audit['source_sha256'].items():
                assert sha(ROOT / name) == digest, name
            assert metadata['source_sha256'] == {k:v for k,v in audit['source_sha256'].items()
                                                 if k != 'packages/fast/src/P256.mo'}
        else:
            assert plugin['pins']['artifacts']['runtime.wasm'] == '0d2fa29baa9ab136ba5bd8a0cb55da5478ff6459fe1e8c02fecdc3e25dde3972'
        assert sha(stage / 'inputs/packages/fast/src/P256.mo') == audit['source_sha256']['packages/fast/src/P256.mo']
        compiled = {case['name']: case for case in build['cases']}
        measured = {case['name']: case for case in results['cases']}
        assert len(compiled) == len(measured) == 28 and compiled.keys() == measured.keys() == reports.keys()
        raw[side] = measured
        for name, case in measured.items():
            report = reports[name]
            described = report[side]
            for field in ['returncode', 'source_sha256', 'wasm_sha256', 'wasm_bytes', 'expected_hex', 'prepared']:
                assert case[field] == compiled[name][field]
            assert case['returncode'] == 0
            for field in ['implementation', 'family', 'plugins', 'expected_hex']:
                assert report[field] == case[field]
            assert report['prepared'] == {k:v for k,v in case['prepared'].items() if k != 'payload_bytes'}
            normalized = ['<moc>'] + [arg.replace(str(stage), '<stage>') for arg in compiled[name]['command'][1:]]
            assert normalized == report['normalized_command']
            source = stage / 'inputs/benchmarks/crypto' / case['source']
            assert sha(source) == case['source_sha256'] == sha(ROOT / 'benchmarks/crypto' / case['source'])
            wasm = stage / case['wasm']
            assert sha(wasm) == case['wasm_sha256'] and wasm.stat().st_size == case['wasm_bytes']
            assert sha(stage / 'inputs/benchmarks/crypto' / case['prepared']['fixture_source']) == case['prepared']['fixture_sha256']
            for field in ['name','source','source_sha256','wasm_sha256','wasm_bytes']:
                assert described[field] == case[field]
            assert described['mode'] == case['prepared']['mode']
            assert described['reuse'] == case['prepared']['reuse']
            assert described['payload_bytes'] == case['prepared'].get('payload_bytes', 0)
            assert described['runtime_wasm_bytes']['p256'] == (stage / 'inputs/dist/p256/runtime.wasm').stat().st_size
            rows = case['measurements']
            assert sorted(row['trial'] for row in rows) == [0,1,2]
            expected = bytes.fromhex(case['expected_hex'])
            for row in rows:
                assert row['correct'] and row['output_bytes'] == len(expected)
                assert row['output_sha256'] == hashlib.sha256(expected).hexdigest()
                assert row['instructions'] > 0 and row['reclaimed_bytes'] == 0
                assert {k:v for k,v in row.items() if k != 'trial'} == {k:v for k,v in rows[0].items() if k != 'trial'}
            for field in ['instructions','allocated_bytes','reclaimed_bytes']:
                assert described[field] == stats([row[field] for row in rows])
            for phase, metrics in described['memory'].items():
                for field, value in metrics.items():
                    assert value == stats([row['memory'][phase][field] for row in rows])
        summary['stages'][side] = {'stage': stage.name, 'build_sha256': sha(stage/'build.json'),
            'results_sha256': sha(stage/'results.json'), 'frozen_inputs_checked': len(build['frozen_inputs_sha256']),
            'runtime_sha256': plugin['pins']['artifacts']['runtime.wasm']}
    for name, report in reports.items():
        old, new = [report[side] for side in ['baseline','candidate']]
        assert old['allocated_bytes'] == new['allocated_bytes']
        assert old['memory'] == new['memory']
        assert old['payload_bytes'] == new['payload_bytes']
        assert new['wasm_bytes'] - old['wasm_bytes'] == 14425
        assert new['runtime_wasm_bytes']['p256'] - old['runtime_wasm_bytes']['p256'] == 14570
        for field, change in report['change'].items():
            a,b = old[field],new[field]
            if isinstance(a,dict): a,b = a['median'], b['median']
            assert change['delta'] == b-a
            assert change['saving_percent'] == ((a-b)*100/a if a else None)
            if 'speedup' in change: assert change['speedup'] == a/b
    summary['instruction_savings'] = {name: report['change']['instructions'] for name,report in reports.items()}
    summary['comparison_sha256'] = sha(comparison_file)
    summary['checker_sha256'] = sha(Path(__file__))
    summary['limits'] = ['28 paired cases, three fresh canisters each; all counters are whole measured intervals.',
        'Memory samples are not peak or retained-live memory; no reclaimed-byte improvement is claimed.',
        'Runtime and linked Wasm grow by14570 and14425 bytes respectively.']
    (HERE/'benchmark-acceptance.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({k:v for k,v in summary.items() if k != 'instruction_savings'},indent=2))

if __name__ == '__main__': main()
