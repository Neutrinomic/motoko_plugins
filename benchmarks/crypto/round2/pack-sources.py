#!/usr/bin/env python3
"""Deduplicate exact source snapshots; retain a map for each measured build."""
import hashlib,io,json,tarfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
blobs={};maps=[];pending=[]
for archive in sorted((BENCH/'results').glob('round2-*/sources.tar.gz')):
    files={}
    with tarfile.open(archive,'r:gz') as tar:
        for member in tar.getmembers():
            if not member.isfile():continue
            assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            relative=Path(member.name)
            if '_out' in relative.parts or '__pycache__' in relative.parts or relative.suffix in {'.wasm','.cmxs','.cmo','.cmi','.cmx','.o','.a','.so','.pyc'}:continue
            data=tar.extractfile(member).read();digest=hashlib.sha256(data).hexdigest()
            if digest in blobs:assert blobs[digest]==data
            blobs[digest]=data;files[member.name]={'sha256':digest,'mode':member.mode}
    # Retain plugin build metadata (full compiler/source/artifact provenance)
    # even for early snapshots whose source tar omitted the dist directory.
    for src in (archive.parent/'inputs/dist').glob('**/*.json'):
        data=src.read_bytes();digest=hashlib.sha256(data).hexdigest();blobs[digest]=data
        files[str(src.relative_to(archive.parent/'inputs'))]={'sha256':digest,'mode':0o644}
    for src in (archive.parent/'inputs/benchmark-oracles').rglob('*'):
        if not src.is_file():continue
        data=src.read_bytes();digest=hashlib.sha256(data).hexdigest();blobs[digest]=data
        files[str(src.relative_to(archive.parent/'inputs'))]={'sha256':digest,'mode':0o644}
    mapping={'original_archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':files}
    target=archive.with_name('source-map.json');pending.append((archive,target,mapping));maps.append(target)
# Fill every declared plugin build input from frozen contents or still-available
# original stage sources, accepting a file only when its declared pin matches.
for archive,target,mapping in pending:
    build_manifest=json.loads(archive.with_name('build.json').read_text())
    for metadata in (archive.parent/'inputs/dist').glob('*/build.json'):
        plugin=metadata.parent.name;pin=json.loads(metadata.read_text())
        original=[Path(name).parents[2] for name in build_manifest['inputs_sha256'] if name.endswith('/dist/'+plugin+'/build.json')]
        for name,expected in pin['source_sha256'].items():
            if expected not in blobs:
                candidates=[root/name for root in original]+[BENCH.parents[1]/name]
                for candidate in candidates:
                    if candidate.is_file():
                        data=candidate.read_bytes()
                        if hashlib.sha256(data).hexdigest()==expected:blobs[expected]=data;break
            assert expected in blobs, f'Missing pinned source content: {archive.parent.name}/{plugin}/{name}'
            mapping['files'][str(Path('plugin-build-inputs')/plugin/name)]={'sha256':expected,'mode':0o644}
    target.write_text(json.dumps(mapping,indent=2)+'\n')
store=HERE/'source-store.tar.gz';temp=store.with_suffix('.tmp')
with tarfile.open(temp,'w:gz') as tar:
    for digest,data in sorted(blobs.items()):
        info=tarfile.TarInfo('sha256/'+digest);info.size=len(data);info.mode=0o644;info.mtime=0;tar.addfile(info,io.BytesIO(data))
# Verify every archived content object before replacing the content store.
with tarfile.open(temp,'r:gz') as tar:
    for member in tar.getmembers():
        data=tar.extractfile(member).read();assert hashlib.sha256(data).hexdigest()==Path(member.name).name
assert len(blobs)>0
temp.replace(store)
(HERE/'source-store.json').write_text(json.dumps({'sha256':hashlib.sha256(store.read_bytes()).hexdigest(),'unique_files':len(blobs),'stage_maps':{str(p.relative_to(BENCH)):hashlib.sha256(p.read_bytes()).hexdigest() for p in maps}},indent=2)+'\n')
print(f'{len(maps)} stages; {len(blobs)} unique source contents; {store.stat().st_size} compressed bytes')
