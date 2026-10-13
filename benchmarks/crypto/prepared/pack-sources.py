#!/usr/bin/env python3
"""Pack verified stage snapshots without consulting current production sources."""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
FORMAT = 'crypto-prepared-source-store-v1'
ARTIFACT_SUFFIXES = {'.wasm', '.o', '.a', '.so', '.dll', '.exe', '.cmxs', '.cmo', '.cmi', '.cmx', '.pyc'}
GENERATED_PARTS = {'_out', '__pycache__', 'target', 'node_modules'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(path.read_bytes())


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True)+'\n').encode()


def relative(name):
    path = PurePosixPath(name)
    assert name and path.parts and not path.is_absolute() and '..' not in path.parts and str(path) == name and '\\' not in name, 'Unsafe archive path: '+name
    return path


def keep(name):
    path = relative(name)
    return not (set(path.parts) & GENERATED_PARTS or path.parts[0] == 'toolchain'
                or path.suffix in ARTIFACT_SUFFIXES
                or path.parts[0] == 'dist' and path.suffix != '.json')


def source_bytes(name, data):
    # Script execution bits are preserved; native executables are not source inputs.
    return keep(name) and not data.startswith(b'\x7fELF')


def immutable(path, data):
    if path.exists():
        assert path.read_bytes() == data, 'Immutable source map changed: '+str(path)
        return
    with path.open('xb') as output:
        output.write(data)


def stage_name(name):
    assert re.fullmatch(r'prepared-[a-zA-Z0-9_-]+', name), 'Unsafe stage name'
    return name


def plugin_sources(build, files, blobs):
    """Check every declared source through this stage's canonical frozen aliases."""
    plugins = sorted({name for case in build['cases'] for name in case.get('plugins', [])})
    for plugin in plugins:
        relative(plugin)
        metadata = 'dist/'+plugin+'/build.json'
        assert metadata in files, 'Missing frozen plugin metadata: '+metadata
        declared = json.loads(blobs[files[metadata]['sha256']])
        assert declared['moc_sha256'] == build['compiler_sha256'], 'Plugin compiler mismatch: '+plugin
        for name, expected in declared['source_sha256'].items():
            relative(name)
            alias = 'plugin-build-inputs/'+plugin+'/'+name
            assert alias in files, 'Missing stage-frozen plugin source: '+alias
            assert files[alias]['sha256'] == expected, 'Pinned plugin source changed: '+alias
    for case in build['cases']:
        if 'source_sha256' not in case:
            continue
        path = 'benchmarks/crypto/'+str(relative(case['source']))
        assert path in files and files[path]['sha256'] == case['source_sha256'], 'Frozen benchmark fixture changed: '+path
    return plugins



def verify_source_pins(build, files, excluded):
    """Connect every stored source to its exact relative build pin."""
    pins = build['frozen_inputs_sha256']
    for name, pin in files.items():
        assert pins.get(name) == pin['sha256'], 'Packed source differs from build pin: '+name
    for name, pin in excluded.items():
        assert keep(name) and name not in files, 'Invalid native executable exclusion: '+name
        assert pins.get(name) == pin, 'Unpinned native executable exclusion: '+name
    for name, pin in pins.items():
        if keep(name):
            assert files.get(name, {}).get('sha256') == pin or excluded.get(name) == pin, 'Missing pinned frozen input: '+name


def collect_stage(directory):
    stage_name(directory.name)
    build_path = directory/'build.json'
    build_pin = sha(build_path)
    build = json.loads(build_path.read_text())
    assert build['protocol'] == 'crypto-prepared-v1', 'Different build protocol'
    assert build.get('complete') is True, 'Build still incomplete: '+directory.name
    assert build['stage'] == directory.name, 'Build/stage mismatch'
    archive = directory/'sources.tar.gz'
    assert archive.is_file(), 'Missing original source archive: '+directory.name
    archive_pin = sha(archive)
    pins = build['frozen_inputs_sha256']
    files, blobs, excluded = {}, {}, {}

    def add(name, data, mode):
        relative(name)
        if not keep(name):
            return
        content_hash = digest(data)
        assert pins.get(name) == content_hash, 'Unpinned/changed frozen input: '+directory.name+'/'+name
        if data.startswith(b'\x7fELF'):
            excluded[name] = content_hash
            return
        item = {'sha256': content_hash, 'mode': mode & 0o777}
        if name in files:
            assert files[name] == item, 'Conflicting frozen source: '+name
        files[name] = item
        blobs[content_hash] = data

    with tarfile.open(archive, 'r:gz') as tar:
        seen = set()
        for member in tar:
            relative(member.name)
            if member.isdir():
                continue
            assert member.isfile(), 'Non-regular archived source: '+member.name
            assert member.name not in seen, 'Duplicate archived source: '+member.name
            seen.add(member.name)
            add(member.name, tar.extractfile(member).read(), member.mode)
    # Recover source inputs omitted by the archive only from this stage's pinned snapshot.
    freeze = directory/'inputs'
    if freeze.exists():
        for path in sorted(freeze.rglob('*')):
            if not path.is_file():
                continue
            name = path.relative_to(freeze).as_posix()
            if name in files or not keep(name):
                continue
            data = path.read_bytes()
            if pins.get(name) == digest(data):
                add(name, data, path.stat().st_mode)
    assert files, 'Empty source snapshot: '+directory.name
    plugins = plugin_sources(build, files, blobs)
    verify_source_pins(build, files, excluded)
    assert sha(archive) == archive_pin and sha(build_path) == build_pin, 'Stage inputs changed during packing'
    mapping = {'format': FORMAT, 'stage': directory.name, 'build_sha256': build_pin,
               'original_archive_sha256': archive_pin, 'input_pin_protocol': 'relative-path',
               'plugins': plugins, 'excluded_native_executables_sha256': dict(sorted(excluded.items())), 'files': dict(sorted(files.items()))}
    return mapping, blobs


def metadata_pins(directory):
    # Metadata remains in the evidence tree; original binary artifacts are pinned
    # by build.json but intentionally not duplicated into this source-only store.
    return {path.relative_to(directory).as_posix(): sha(path)
            for path in sorted(directory.rglob('*'))
            if path.is_file() and 'inputs' not in path.relative_to(directory).parts
            and path.name != 'source-map.json' and path.suffix in {'.json', '.log'}}


def load_store(here=HERE):
    index = json.loads((here/'source-store.json').read_text())
    assert index['format'] == FORMAT, 'Unknown source-store format'
    store = here/'source-store.tar.gz'
    assert sha(store) == index['sha256'], 'Source store changed'
    blobs = {}
    with tarfile.open(store, 'r:gz') as tar:
        for member in tar:
            assert member.isfile() and re.fullmatch(r'sha256/[0-9a-f]{64}', member.name), 'Invalid content-store entry'
            key = member.name.split('/')[1]
            assert key not in blobs, 'Duplicate content-store entry'
            data = tar.extractfile(member).read()
            assert digest(data) == key, 'Corrupt content-store entry'
            blobs[key] = data
    assert len(blobs) == index['unique_files'], 'Content count differs'
    maps = {}
    for name, entry in index['stages'].items():
        directory = here/'results'/stage_name(name)
        map_path = directory/'source-map.json'
        assert sha(map_path) == entry['source_map_sha256'], 'Stage source map changed: '+name
        mapping = json.loads(map_path.read_text())
        assert mapping['format'] == FORMAT and mapping['stage'] == name
        assert mapping['original_archive_sha256'] == entry['original_archive_sha256']
        assert mapping['build_sha256'] == entry['metadata_sha256']['build.json']
        for path, pin in mapping['files'].items():
            relative(path)
            assert pin['sha256'] in blobs and source_bytes(path, blobs[pin['sha256']]), 'Invalid packed source: '+path
            assert isinstance(pin['mode'], int) and 0 <= pin['mode'] <= 0o777, 'Unsafe restored mode'
        maps[name] = mapping
    return index, blobs, maps


def pack(stages, here=HERE):
    contents, entries = {}, {}
    for name in stages:
        directory = here/'results'/stage_name(name)
        mapping, blobs = collect_stage(directory)
        map_path = directory/'source-map.json'
        immutable(map_path, encoded(mapping))
        contents.update(blobs)
        entries[name] = {'source_map_sha256': sha(map_path), 'original_archive_sha256': mapping['original_archive_sha256'],
                         'metadata_sha256': metadata_pins(directory)}
    assert entries and contents, 'No stages selected'
    here.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='source-store-', suffix='.tmp', dir=here)
    os.close(descriptor)
    temporary = Path(temporary)
    try:
        with temporary.open('wb') as output, gzip.GzipFile(filename='', mode='wb', fileobj=output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as tar:
                for key, data in sorted(contents.items()):
                    info = tarfile.TarInfo('sha256/'+key)
                    info.size = len(data); info.mode = 0o644; info.mtime = 0
                    tar.addfile(info, io.BytesIO(data))
        index = {'format': FORMAT, 'sha256': sha(temporary), 'unique_files': len(contents), 'stages': entries}
        temporary.replace(here/'source-store.tar.gz')
        (here/'source-store.json').write_bytes(encoded(index))
    finally:
        temporary.unlink(missing_ok=True)
    load_store(here)
    print(f'{len(entries)} stages; {len(contents)} unique source contents; {(here/"source-store.tar.gz").stat().st_size} compressed bytes')
    return index


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', action='append', help='Repeat for an explicit completed-stage cohort; default all prepared stages')
    args = parser.parse_args()
    stages = args.stage or [path.parent.name for path in sorted((HERE/'results').glob('prepared-*/build.json'))]
    assert len(set(stages)) == len(stages), 'Duplicate stage argument'
    pack(stages)


if __name__ == '__main__':
    main()
