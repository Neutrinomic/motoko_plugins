#!/usr/bin/env python3
"""Verify packed snapshots, declared plugin sources, and retained stage metadata."""
import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('round3_sources', HERE/'pack-sources.py')
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


def verify(here=HERE, bench=HERE.parent, restored=None, restored_stage=None):
    assert (restored is None) == (restored_stage is None), 'Use --restored and --stage together'
    index, blobs, maps = sources.load_store(here, bench)
    if restored_stage is not None:
        assert restored_stage in maps, 'Restored stage absent from source store'
    stages = {}
    for name, entry in index['stages'].items():
        directory = bench/'results'/name
        mapping = maps[name]
        for path, pin in entry['metadata_sha256'].items():
            assert sources.sha(directory/sources.relative(path)) == pin, 'Stage metadata changed: '+name+'/'+path
        original = directory/'sources.tar.gz'
        if original.exists():
            assert sources.sha(original) == entry['original_archive_sha256'], 'Original source archive changed: '+name
        build = json.loads((directory/'build.json').read_text())
        assert build.get('complete') is True and build['stage'] == name
        files = dict(mapping['files'])
        plugins = sources.plugin_sources(build, files, {pin['sha256']: blobs[pin['sha256']] for pin in files.values()})
        assert files == mapping['files'], 'Packed stage missing canonical plugin source aliases'
        assert plugins == mapping['plugins'], 'Plugin list differs from build'
        sources.verify_source_pins(build, files, blobs, mapping['excluded_native_executables_sha256'])
        binaries_checked = 0
        for case in build['cases']:
            if 'wasm' not in case:
                continue
            wasm = directory/sources.relative(case['wasm'])
            if wasm.exists():
                assert sources.sha(wasm) == case['wasm_sha256'], 'Canister Wasm changed: '+str(wasm)
                assert wasm.stat().st_size == case['wasm_bytes'], 'Canister Wasm length changed'
                binaries_checked += 1
        for plugin in plugins:
            metadata = json.loads(blobs[files['dist/'+plugin+'/build.json']['sha256']])
            for path, pin in metadata['sha256'].items():
                artifact = directory/'inputs/dist'/plugin/sources.relative(path)
                if artifact.exists():
                    assert sources.sha(artifact) == pin, 'Plugin artifact changed: '+str(artifact)
                    binaries_checked += 1
        if restored_stage == name:
            expected = set(files)
            actual = {path.relative_to(restored).as_posix() for path in restored.rglob('*') if path.is_file()}
            assert actual == expected, 'Restored snapshot file set differs'
            for path, pin in files.items():
                target = restored/path
                assert sources.sha(target) == pin['sha256'], 'Restored source changed: '+path
                assert target.stat().st_mode & 0o777 == pin['mode'], 'Restored source mode changed: '+path
        result_path = directory/'results.json'
        result_summary = None
        if result_path.exists():
            result = json.loads(result_path.read_text())
            assert result['build_sha256'] == mapping['build_sha256'], 'Result/build identity differs: '+name
            result_summary = {key: result.get(key) for key in ['complete', 'trials', 'expected_case_count', 'failed_measurements']}
        stages[name] = {'source_files': len(files), 'declared_plugins': plugins,
                        'local_binary_artifacts_checked': binaries_checked, 'measurement_status': result_summary}
    return {'status': 'pass', 'scope': 'Source/archive/metadata integrity; retained failed measurements are reported, not treated as successful trials.',
            'stage_count': len(stages), 'unique_source_contents': len(blobs), 'stages': stages,
            'restored_stage': restored_stage,
            'source_store_sha256': index['sha256'], 'source_index_sha256': sources.sha(here/'source-store.json')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restored', type=Path, help='Optional reconstructed source directory')
    parser.add_argument('--stage', help='Stage reconstructed under --restored')
    parser.add_argument('--out', type=Path, help='Optional new integrity report; never overwrites')
    args = parser.parse_args()
    report = verify(restored=args.restored, restored_stage=args.stage)
    if args.out:
        with args.out.open('xb') as output:
            output.write(sources.encoded(report))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
