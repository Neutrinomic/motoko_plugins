#!/usr/bin/env python3
"""Run generated Ash set benchmarks serially and retain checked raw evidence."""
import argparse
import hashlib
import json
import shutil
import statistics
import subprocess
from pathlib import Path


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def git(directory, *arguments):
    return subprocess.check_output(['git', '-C', str(directory), *arguments], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path, help='Generated comparison directory')
    parser.add_argument('--archive', required=True, type=Path, help='New evidence directory')
    parser.add_argument('--motoko', required=True, type=Path)
    parser.add_argument('--ash', required=True, type=Path, help='Ash repository root')
    parser.add_argument('--ash-moc-binary', required=True, type=Path,
                        help='Actual moc executable selected by Ash, behind any wrapper')
    parser.add_argument('--deps', required=True, type=Path, help='Locked core@2.5.0 Mops dependencies')
    parser.add_argument('--trials', default=3, type=int)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error('trials must be positive')
    root = Path(__file__).resolve().parents[2]
    out, archive, motoko, ash, deps = [getattr(args, name).resolve()
        for name in ('out', 'archive', 'motoko', 'ash', 'deps')]
    if archive.exists():
        parser.error('archive already exists; choose a new directory')
    cases = json.loads((out / 'cases.json').read_text())
    if not cases:
        parser.error('empty benchmark matrix')
    configs = sorted({case['config'] for case in cases})
    source_files = [out / 'cases.json']
    source_files += [out / name for config in configs for name in (config, str(Path(config).with_name('main.mo')))]
    source_files += [root / 'benchmarks/generate-set-comparison.py', Path(__file__).resolve(),
                     root / 'benchmarks/set-comparison/summarize.py',
                     root / 'packages/fast/src/Set.mo', root / 'packages/fast/src/pure/Set.mo']
    for family in {case['family'] for case in cases if case['variant'] != 'core'}:
        name = family + '-set'
        source_files += [path for path in sorted((root / 'plugins' / name / 'compiler').iterdir())
                         if path.suffix in {'.ml', '.mli'}]
        source_files += [root / 'plugins' / name / 'plugin.json']
        build = json.loads((root / 'dist' / name / 'build.json').read_text())
        if build['moc_sha256'] != sha(motoko / 'src/moc'):
            raise ValueError(f'{name} compiler binary is stale')
        for relative, digest in build['sha256'].items():
            if sha(root / 'dist' / name / relative) != digest:
                raise ValueError(f'{name} artifact differs from build manifest: {relative}')
        for relative, digest in build['source_sha256'].items():
            if sha(root / relative) != digest:
                raise ValueError(f'{name} source is newer than the native artifact: {relative}')
        for relative, digest in build['motoko_source_sha256'].items():
            if sha(motoko / relative) != digest:
                raise ValueError(f'{name} compiler source changed since build: {relative}')
        source_files += [root / 'dist' / name / 'build.json', root / 'dist' / name / 'plugin.cmxs']

    lock = json.loads((deps / 'mops.lock').read_text())
    if lock['deps'].get('core') != '2.5.0':
        raise ValueError('comparison requires locked Core2.5.0')
    core = deps / '.mops/core@2.5.0/src'
    for path in core.rglob('*.mo'):
        name = path.relative_to(deps / '.mops').as_posix()
        if lock['hashes']['core@2.5.0'].get(name) != sha(path):
            raise ValueError(f'Core source differs from dependency lock: {name}')
        source_files.append(path)
    for config in configs:
        data = json.loads((out / config).read_text())
        directory = (out / config).parent
        if directory.joinpath(data['mo']['core']).resolve() != core.resolve():
            raise ValueError('generated configuration must use the supplied dependency root')
        if directory.joinpath(data['mo']['fast']).resolve() != (root / 'packages/fast/src').resolve():
            raise ValueError('generated configuration uses another fast package')
        matching = [case for case in cases if case['config'] == config]
        if len(matching) != 1 or len(data['canisters']) != 1:
            raise ValueError('each benchmark operation must have its own fresh canister/configuration')
        case, canister = matching[0], data['canisters'][0]
        expected_flags = ([] if case['variant'] == 'core' else
                          ['--plugin', str((root / 'dist' / (case['family'] + '-set')).resolve())])
        actual_flags = canister['mocArgs']
        if len(actual_flags) == 2:
            actual_flags = [actual_flags[0], str(directory.joinpath(actual_flags[1]).resolve())]
        if actual_flags != expected_flags:
            raise ValueError(f'configuration plugin flags differ from benchmark case: {config}')
    if sha(args.ash_moc_binary) != sha(motoko / 'src/moc'):
        raise ValueError('Ash moc executable must match the native plugin compiler')
    resolve_script = ('import {resolveBinary} from ' + json.dumps(str(ash / 'src/binaries.ts')) +
                      '; console.log(await resolveBinary("moc", process.argv[1]));')
    ash_wrappers = {Path(subprocess.check_output(['bun', '-e', resolve_script,
                    str((out / config).parent)], text=True).strip()).resolve() for config in configs}
    for wrapper in ash_wrappers:
        if sha(wrapper) == sha(args.ash_moc_binary):
            raise ValueError('use the managed Ash compiler wrapper so its runtime inputs can be verified')
        # The supported installed compiler bundle has a tiny audited wrapper.
        expected_wrapper = '''#!/usr/bin/env bash
set -euo pipefail
moc_bundle="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib/motoko-compute" && pwd)"
export MOC_RELEASE_RTS="$moc_bundle/mo-rts.wasm"
export MOC_DEBUG_RTS="$moc_bundle/mo-rts-debug.wasm"
exec "$moc_bundle/moc" "$@"
'''
        bundle = wrapper.parent.parent / 'lib/motoko-compute'
        if wrapper.read_text() != expected_wrapper or (bundle / 'moc').resolve() != args.ash_moc_binary.resolve():
            raise ValueError(f'Ash resolved an unrecognized compiler wrapper: {wrapper}')
        for name in ('mo-rts.wasm', 'mo-rts-debug.wasm'):
            if sha(bundle / name) != sha(motoko / 'rts' / name):
                raise ValueError(f'Ash runtime differs from compiler checkout: {name}')
            source_files.append(bundle / name)
        source_files.append(wrapper)
    pocket_ic = Path.home() / '.local/bin/pocket-ic'
    pocket_ic_hash = sha(pocket_ic)
    def binary_state(path):
        info = path.stat()
        return (info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)

    pocket_ic_stat = binary_state(pocket_ic)
    source_files += [deps / 'mops.lock', motoko / 'src/moc', motoko / 'rts/mo-rts.wasm',
                     motoko / 'rts/mo-rts-debug.wasm', args.ash_moc_binary.resolve()]
    source_files += list((ash / 'src').rglob('*.ts'))
    source_files += [ash / name for name in ('package.json', 'bun.lock') if (ash / name).exists()]
    source_files = sorted(set(path.resolve() for path in source_files))

    def inputs():
        return {str(path): sha(path) for path in source_files}

    before = inputs()
    archive.mkdir(parents=True)
    provenance = {'status': 'running', 'compiler_revision': git(motoko, 'rev-parse', 'HEAD'),
                  'compiler_dirty': bool(git(motoko, 'status', '--porcelain')),
                  'plugins_revision': git(root, 'rev-parse', 'HEAD'),
                  'plugins_dirty': bool(git(root, 'status', '--porcelain')),
                  'ash_revision': git(ash, 'rev-parse', 'HEAD'),
                  'ash_dirty': bool(git(ash, 'status', '--porcelain')),
                  'ash_reconstruction': 'The exact local Ash CLI requires matching source hashes; only its generated Motoko metrics module is included here, not unrelated local Ash project source.',
                  'ash_moc_wrappers': [str(path) for path in sorted(ash_wrappers)],
                  'pocket_ic': {'path': str(pocket_ic), 'sha256': pocket_ic_hash,
                                'version': subprocess.check_output([str(pocket_ic), '--version'], text=True).strip()},
                  'compiler_version': subprocess.check_output([str(args.ash_moc_binary), '--version'], text=True).strip(),
                  'trials': args.trials, 'case_count': len(cases), 'source_sha256': before,
                  'boundary': 'Each update constructs fresh sets before Test.test; only the measured closure is charged. Point rows contain 32 operations; all other rows one full operation. Validation follows measurement.',
                  'allocation': 'totalAllocatedBytes is the cumulative Motoko allocation delta; heapBytes is the separate nonnegative heap delta, not peak memory. Metrics include common Ash harness overhead and any GC within the closure.',
                  'commands': []}
    (archive / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    samples = {case['metrics_key']: [] for case in cases}
    for trial in range(1, args.trials + 1):
        for config in configs:
            directory = (out / config).parent
            destination = archive / 'raw' / f'trial-{trial}' / directory.name
            destination.mkdir(parents=True)
            command = ['bun', str(ash / 'src/index.ts'), 'test', str(out / config), '--set', '--verbose']
            print(f'Trial {trial}/{args.trials}: {directory.name}', flush=True)
            provenance['commands'].append(command)
            with (destination / 'ash.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            metrics_path = directory / '.ash/test-metrics.json'
            shutil.copy2(metrics_path, destination / 'test-metrics.json')
            payload = json.loads(metrics_path.read_text())
            expected = {case['metrics_key'] for case in cases if case['config'] == config}
            if set(payload['metrics']) != expected:
                raise ValueError(f'measurements differ from expected case list for {config}')
            for key, sample in payload['metrics'].items():
                samples[key].append({name: int(value) for name, value in sample.items()})
            wasm = directory / '.ash/ash/artifacts' / (directory.name + '.wasm')
            artifact = destination / 'wasm.sha256'
            artifact.write_text(sha(wasm) + '\n')
            test_module = directory / '.ash/ash/test/lib.mo'
            module_hash = sha(test_module)
            if 'metrics_module_sha256' not in provenance:
                provenance['metrics_module_sha256'] = module_hash
                (archive / 'harness').mkdir()
                shutil.copy2(test_module, archive / 'harness/Test.mo')
            elif provenance['metrics_module_sha256'] != module_hash:
                raise ValueError('Ash generated different metrics modules during recording')
            if inputs() != before or binary_state(pocket_ic) != pocket_ic_stat:
                raise ValueError('benchmark inputs changed during recording; archive is incomplete')
    if sha(pocket_ic) != pocket_ic_hash:
        raise ValueError('PocketIC binary changed during recording')
    results = []
    for case in cases:
        records = samples[case['metrics_key']]
        results.append({**case, 'samples': records,
                        'instructions': statistics.median(record['instructions'] for record in records),
                        'allocated_bytes': statistics.median(record['totalAllocatedBytes'] for record in records),
                        'stable': len({(record['instructions'], record['totalAllocatedBytes']) for record in records}) == 1})
    (archive / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    for path in source_files:
        if (path.suffix not in {'.mo', '.ml', '.mli', '.json', '.py', '.lock'}
                or path.is_relative_to(deps / '.mops') or path.is_relative_to(ash)):
            continue
        relative = (Path('generated') / path.relative_to(out) if path.is_relative_to(out)
                    else Path('plugins') / path.relative_to(root) if path.is_relative_to(root)
                    else Path('dependencies') / path.name)
        target = archive / 'sources' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    provenance['status'] = 'complete'
    provenance['stable_instructions_and_allocations'] = all(row['stable'] for row in results)
    (archive / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    manifest = {path.relative_to(archive).as_posix(): sha(path) for path in sorted(archive.rglob('*')) if path.is_file()}
    (archive / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Recorded {len(results)} cases x{args.trials} trials at {archive}', flush=True)


if __name__ == '__main__':
    main()
