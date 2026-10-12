#!/usr/bin/env python3
"""Run independent Bitcoin audit fixtures using the matching compiler/plugins.

Invoke in ../motoko_sha's Nix shell, which provides Wasmtime. Optional --plugin
name=directory overrides allow development artifacts from isolated snapshots.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PLUGIN_NAMES = ['sha256', 'base58', 'bech32', 'ripemd160', 'secp256k1']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moc', type=Path, default=ROOT.parent / 'motoko_sha/bin/moc')
    parser.add_argument('--wasmtime', default='wasmtime')
    parser.add_argument('--plugin', action='append', default=[], metavar='NAME=DIR')
    parser.add_argument('--report', type=Path, default=HERE / 'validation.json')
    args = parser.parse_args()
    plugins = {name: ROOT / 'dist' / name for name in PLUGIN_NAMES}
    for override in args.plugin:
        name, directory = override.split('=', 1)
        if name not in plugins:
            parser.error(f'Unknown plugin {name}')
        plugins[name] = Path(directory).resolve()
    moc = args.moc.absolute() # Preserve bin/moc symlink: wrapper dispatch uses argv[0].
    common = [str(moc), '--package', 'fast', str(ROOT / 'packages/fast/src'),
              '--package', 'core', str(ROOT / 'packages/fast/.mops/core@2.5.0/src')]
    report = {'compiler': str(moc), 'compiler_version': subprocess.check_output([moc, '--version'], text=True).strip(),
              'plugins': {}, 'fixtures': {}, 'source_hashes': {}}
    for name, directory in plugins.items():
        report['plugins'][name] = {'path': str(directory), 'cmxs_sha256': digest(directory / 'plugin.cmxs'),
                                   'runtime_sha256': digest(directory / 'runtime.wasm')}
    for module in ['Hash', 'Address', 'Bip32', 'Script', 'Transaction']:
        path = ROOT / 'packages/fast/src/Bitcoin' / (module + '.mo')
        report['source_hashes']['Bitcoin/' + module + '.mo'] = digest(path)
    for module in ['SHA256','RIPEMD160','Secp256k1','Bech32','Segwit','Base58','Base58Check']:
        path = ROOT / 'packages/fast/src' / (module + '.mo')
        report['source_hashes'][module + '.mo'] = digest(path)
    with tempfile.TemporaryDirectory(prefix='bitcoin-composition-audit-') as directory:
        for fixture in ['oracle', 'negative', 'wallet']:
            source = HERE / (fixture + '.mo')
            flags = []
            for name in (PLUGIN_NAMES if fixture == 'wallet' else ['sha256']):
                flags += ['--plugin', str(plugins[name])]
            wasm = Path(directory) / (fixture + '.wasm')
            for command in [common + flags + ['-r', str(source)],
                            common + flags + ['-wasi-system-api', '--sanity-checks', '-o', str(wasm), str(source)],
                            [args.wasmtime, '-W', 'memory64=y', str(wasm)]]:
                result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                if result.returncode:
                    raise SystemExit(f'Failed: {command}\n{result.stdout}')
                if result.stdout:
                    print(result.stdout, end='')
            report['fixtures'][fixture] = {'source_sha256': digest(source), 'wasm_sha256': digest(wasm),
                                           'interpreter': 'pass', 'wasm_sanity': 'pass'}
            print(f'{fixture}: interpreter and Wasm with sanity checks passed')
    report['oracle_counts'] = {k:v for k,v in json.loads((HERE/'oracle-provenance.json').read_text()).items() if k.endswith('_cases')}
    report['wallet_counts'] = {k:v for k,v in json.loads((HERE/'wallet-provenance.json').read_text()).items() if k.endswith('_cases') or k.startswith('bip350_')}
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {args.report}')


if __name__ == '__main__':
    main()
