#!/usr/bin/env python3
"""Record isolated comparator-dispatch Ash cases using an explicitly frozen toolchain."""
import argparse
import hashlib
import json
import shutil
import statistics
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def git(directory, *arguments):
    return subprocess.check_output(['git', '-C', str(directory), *arguments], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('out', 'archive', 'ash', 'toolchain', 'dist', 'fast', 'deps'):
        parser.add_argument('--' + option, required=True, type=Path)
    parser.add_argument('--phase', required=True, choices=('baseline', 'candidate'))
    parser.add_argument('--trials', default=3, type=int)
    parser.add_argument('--jobs', default=1, type=int, help='Independent configurations in parallel within each trial')
    parser.add_argument('--plugin-source-revision', help='Source commit for a preserved baseline; hashes must match its build manifests')
    args = parser.parse_args()
    if args.trials < 1 or args.jobs < 1:
        parser.error('trials and jobs must be positive')
    root = Path(__file__).resolve().parents[2]
    out, archive, ash, toolchain, dist, fast, deps = [getattr(args, name).resolve()
        for name in ('out', 'archive', 'ash', 'toolchain', 'dist', 'fast', 'deps')]
    if archive.exists():
        parser.error('archive already exists; choose a fresh directory')
    cases = json.loads((out / 'cases.json').read_text())
    if not cases or len({case['metrics_key'] for case in cases}) != len(cases):
        parser.error('cases must be nonempty and unique')
    configs = sorted({case['config'] for case in cases})
    if len(configs) != len(cases) or len({(out / config).parent.resolve() for config in configs}) != len(cases):
        parser.error('each case must have its own configuration directory')
    files = [out / 'cases.json', deps / 'mops.lock']
    files += [Path(__file__).parent / name for name in ('generate.py', 'generate-mixed.py', 'run.py', 'summarize.py')]
    files += list(fast.rglob('*.mo'))
    files += [toolchain / name for name in ('moc', 'mo-rts.wasm', 'mo-rts-debug.wasm')]
    source_snapshots = {}
    for family in sorted({case['family'] for case in cases if case['variant'] != 'core'}):
        build_path = dist / family / 'build.json'
        build = json.loads(build_path.read_text())
        if build['moc_sha256'] != sha(toolchain / 'moc'):
            raise ValueError(f'{family}: artifact compiler does not match the selected toolchain')
        files.append(build_path)
        for name, digest in build['sha256'].items():
            path = dist / family / name
            if sha(path) != digest:
                raise ValueError(f'{family}: native artifact differs from manifest: {name}')
            files.append(path)
        for name, digest in build['source_sha256'].items():
            if args.plugin_source_revision:
                content = subprocess.check_output(['git', '-C', str(root), 'show', f'{args.plugin_source_revision}:{name}'])
            else:
                path = root / name
                files.append(path)
                content = path.read_bytes()
            if hashlib.sha256(content).hexdigest() != digest:
                raise ValueError(f'{family}: plugin source differs from manifest: {name}')
            source_snapshots[name] = content
    lock = json.loads((deps / 'mops.lock').read_text())
    if lock['deps'].get('core') != '2.5.0':
        raise ValueError('requires locked Core 2.5.0')
    core = deps / '.mops/core@2.5.0/src'
    for path in core.rglob('*.mo'):
        name = path.relative_to(deps / '.mops').as_posix()
        if lock['hashes']['core@2.5.0'].get(name) != sha(path):
            raise ValueError(f'Core source differs from dependency lock: {name}')
        files.append(path)
    for case in cases:
        config = out / case['config']
        directory = config.parent
        data = json.loads(config.read_text())
        if len(data['canisters']) != 1:
            raise ValueError('one operation/canister per configuration required')
        if (directory / data['mo']['core']).resolve() != core or (directory / data['mo']['fast']).resolve() != fast:
            raise ValueError('configuration dependencies differ from selected frozen sources')
        expected_flags = [] if case['variant'] == 'core' else ['--plugin', str(dist / case['family'])]
        actual_flags = data['canisters'][0]['mocArgs']
        if len(actual_flags) == 2:
            actual_flags = [actual_flags[0], str((directory / actual_flags[1]).resolve())]
        if actual_flags != expected_flags:
            raise ValueError(f'configuration native flags differ from case: {case["config"]}')
        files += [config, directory / 'main.mo']
    # Ash chooses its global managed wrapper before project-local executables.
    # Merely prepending PATH is not sufficient; verify the actual resolved bundle.
    resolve_script = ('import {resolveBinary} from ' + json.dumps(str(ash / 'src/binaries.ts')) +
                      '; console.log(await resolveBinary(process.argv[1], process.argv[2]));')
    def resolve(binary):
        return Path(subprocess.check_output(['bun', '-e', resolve_script, binary, str(out)], text=True).strip()).resolve()
    wrapper = resolve('moc')
    expected_wrapper = '''#!/usr/bin/env bash
set -euo pipefail
moc_bundle="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib/motoko-compute" && pwd)"
export MOC_RELEASE_RTS="$moc_bundle/mo-rts.wasm"
export MOC_DEBUG_RTS="$moc_bundle/mo-rts-debug.wasm"
exec "$moc_bundle/moc" "$@"
'''
    if wrapper.read_text() != expected_wrapper:
        raise ValueError(f'Ash resolved an unrecognized compiler wrapper: {wrapper}')
    bundle = wrapper.parent.parent / 'lib/motoko-compute'
    for name in ('moc', 'mo-rts.wasm', 'mo-rts-debug.wasm'):
        if sha(bundle / name) != sha(toolchain / name):
            raise ValueError(f'Ash installed {name} differs from the selected frozen toolchain; coordinate installation before recording')
        files.append(bundle / name)
    files += [wrapper]
    files += list((ash / 'src').rglob('*.ts'))
    files += [ash / name for name in ('package.json', 'bun.lock') if (ash / name).exists()]
    pocket_ic, didc = resolve('pocket-ic'), resolve('didc')
    # PocketIC is large; stat it after each case and rehash it at completion.
    binaries = [pocket_ic, didc]
    binary_hashes = {str(path): sha(path) for path in binaries}
    def stat(path):
        s = path.stat()
        # Ash reapplies executable permissions to didc; chmod changes ctime
        # without changing its bytes. Inode/size/mtime detect replacement/writes,
        # and the complete binaries are rehashed at the end.
        return s.st_ino, s.st_size, s.st_mtime_ns
    binary_stats = {str(path): stat(path) for path in binaries}
    files = sorted(set(path.resolve() for path in files))
    def inputs():
        return {str(path): sha(path) for path in files}
    before = inputs()
    archive.mkdir(parents=True)
    provenance = {'status': 'running', 'phase': args.phase, 'plugins_revision': git(root, 'rev-parse', 'HEAD'),
        'plugins_dirty': bool(git(root, 'status', '--porcelain')), 'plugin_source_revision': args.plugin_source_revision,
        'ash_revision': git(ash, 'rev-parse', 'HEAD'), 'ash_dirty': bool(git(ash, 'status', '--porcelain')),
        'ash_reconstruction': 'Ash source hashes identify the exact local CLI; only its generated Motoko metrics module is copied, not unrelated local Ash source.',
        'compiler_version': subprocess.check_output([str(toolchain / 'moc'), '--version'], text=True).strip(),
        'pocket_ic_version': subprocess.check_output([str(pocket_ic), '--version'], text=True).strip(),
        'compiler_sha256': sha(toolchain / 'moc'), 'binary_sha256': binary_hashes,
        'comparison_inputs': {
            'execution_binaries': {path.name: sha(path) for path in binaries},
            'rts': {name: sha(toolchain / name) for name in ('mo-rts.wasm', 'mo-rts-debug.wasm')},
            'core_lock_sha256': sha(deps / 'mops.lock'),
            'core_sources': {str(path.relative_to(core)): sha(path) for path in core.rglob('*.mo')},
            'ash_sources': {str(path.relative_to(ash)): sha(path) for path in files if path.is_relative_to(ash)},
        },
        'trials': args.trials, 'jobs': args.jobs, 'case_count': len(cases), 'source_sha256': before,
        'boundary': 'One freshly installed canister per operation, size, comparator variant and trial. Setup and validation outside Test.test; build measures the whole shuffled build. Ordinary point rows measure 32 probes; empty/singleton rows one.',
        'allocation': 'totalAllocatedBytes is cumulative Motoko allocation, including garbage; heapBytes is a nonnegative heap delta, not peak/live memory. Common Ash overhead and collection within the closure are included.',
        'wasm': 'wasm_bytes is the byte length of the complete emitted canister Wasm, including RTS, validation and Ash harness; not the size of a standalone plugin.',
        'commands': []}
    provenance_path = archive / 'provenance.json'
    provenance_path.write_text(json.dumps(provenance, indent=2) + '\n')
    # Snapshot inputs before recording so even an interrupted archive retains its sources.
    for path in files:
        if path.is_relative_to(ash) or path.is_relative_to(core) or path.suffix not in {'.mo', '.ml', '.mli', '.json', '.py', '.lock'}:
            continue
        relative = (Path('generated') / path.relative_to(out) if path.is_relative_to(out)
                    else Path('fast') / path.relative_to(fast) if path.is_relative_to(fast)
                    else Path('dist') / path.relative_to(dist) if path.is_relative_to(dist)
                    else Path('plugins') / path.relative_to(root) if path.is_relative_to(root)
                    else Path('dependencies') / path.name)
        target = archive / 'sources' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    for relative, content in source_snapshots.items():
        target = archive / 'sources/plugin-build' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    samples, artifacts = {case['metrics_key']: [] for case in cases}, {case['metrics_key']: [] for case in cases}
    def run_case(trial, case):
        directory = (out / case['config']).parent
        destination = archive / 'raw' / f'trial-{trial}' / directory.name
        destination.mkdir(parents=True)
        command = ['bun', str(ash / 'src/index.ts'), 'test', str(out / case['config']), '--set', '--verbose']
        print(f'Trial {trial}/{args.trials}: {directory.name}', flush=True)
        with (destination / 'ash.log').open('w') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        metrics_path = directory / '.ash/test-metrics.json'
        shutil.copy2(metrics_path, destination / 'test-metrics.json')
        payload = json.loads(metrics_path.read_text())
        if set(payload['metrics']) != {case['metrics_key']}:
            raise ValueError(f'measurements differ from expected case: {case["config"]}')
        sample = {name: int(value) for name, value in payload['metrics'][case['metrics_key']].items()}
        wasm = directory / '.ash/ash/artifacts' / (directory.name + '.wasm')
        artifact = {'sha256': sha(wasm), 'bytes': wasm.stat().st_size}
        (destination / 'wasm.json').write_text(json.dumps(artifact, indent=2) + '\n')
        module = (directory / '.ash/ash/test/lib.mo').read_bytes()
        if inputs() != before or {str(path): stat(path) for path in binaries} != binary_stats:
            raise ValueError('benchmark inputs changed during recording; archive is incomplete')
        return command, sample, artifact, module

    ordered_cases = sorted(cases, key=lambda item: item['config'])
    for trial in range(1, args.trials + 1):
        # Each task owns a distinct configuration/artifact directory. A complete
        # trial barrier prevents another trial from using that directory early.
        executor = ThreadPoolExecutor(max_workers=args.jobs)
        completed = {}
        try:
            futures = {executor.submit(run_case, trial, case): case for case in ordered_cases}
            for future in as_completed(futures):
                completed[futures[future]['metrics_key']] = future.result()
        except BaseException:
            executor.shutdown(wait=True, cancel_futures=True)
            raise
        else:
            executor.shutdown(wait=True)
        # Collection order is deterministic even when execution order is not.
        for case in ordered_cases:
            key = case['metrics_key']
            command, sample, artifact, module = completed[key]
            provenance['commands'].append(command)
            samples[key].append(sample)
            artifacts[key].append(artifact)
            module_hash = hashlib.sha256(module).hexdigest()
            if 'metrics_module_sha256' not in provenance:
                provenance['metrics_module_sha256'] = module_hash
                (archive / 'harness').mkdir()
                (archive / 'harness/Test.mo').write_bytes(module)
            elif provenance['metrics_module_sha256'] != module_hash:
                raise ValueError('Ash metrics module changed during recording')
    if {str(path): sha(path) for path in binaries} != binary_hashes:
        raise ValueError('PocketIC/didc changed during recording')
    results = []
    for case in cases:
        records, emitted = samples[case['metrics_key']], artifacts[case['metrics_key']]
        results.append({**case, 'samples': records, 'wasm_samples': emitted,
            'instructions': statistics.median(record['instructions'] for record in records),
            'allocated_bytes': statistics.median(record['totalAllocatedBytes'] for record in records),
            'wasm_bytes': statistics.median(record['bytes'] for record in emitted),
            'stable': len({(record['instructions'], record['totalAllocatedBytes']) for record in records}) == 1,
            'wasm_stable': len({(record['sha256'], record['bytes']) for record in emitted}) == 1})
    (archive / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    provenance['status'] = 'complete'
    provenance['stable_instructions_and_allocations'] = all(row['stable'] for row in results)
    provenance['stable_wasm'] = all(row['wasm_stable'] for row in results)
    provenance_path.write_text(json.dumps(provenance, indent=2) + '\n')
    manifest = {path.relative_to(archive).as_posix(): sha(path) for path in sorted(archive.rglob('*')) if path.is_file()}
    (archive / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Recorded {len(results)} cases x {args.trials} trials at {archive}', flush=True)


if __name__ == '__main__':
    main()
