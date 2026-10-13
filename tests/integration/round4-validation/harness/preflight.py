from pathlib import Path
import hashlib,json,shutil,subprocess,sys
root=Path('/srv/shared/code/motoko_experiments/plugins/_build/signature-round4/integration')
sdk=Path('/srv/shared/code/motoko_experiments/prepared-crypto/sdk')
ashroot=Path('/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation')
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
expected='24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2'
assert sha(sdk/'src/moc')==expected,'SDK executable changed'
plugins=sorted(p.parent.name for p in (root/'plugins').glob('*/plugin.json'))
assert len(plugins)==23,'Unexpected final plugin count'
selected=json.loads((root/'_build/round4-validation/selected-runtime-pins.json').read_text())
assert set(selected)=={'ed25519','rsa','ml-dsa','secp256k1','p256','bls12-381'},'Incomplete six-runtime parity pins'
artifacts={}
for name in plugins:
    m=json.loads((root/f'dist/{name}/build.json').read_text())
    assert m['moc_sha256']==expected,f'{name}: wrong compiler'
    for f,h in m['sha256'].items():assert sha(root/f'dist/{name}'/f)==h,f'{name}: stale artifact {f}'
    for f,h in m['source_sha256'].items():assert sha(root/f)==h,f'{name}: stale source {f}'
    artifacts[name]={'build_manifest_sha256':sha(root/f'dist/{name}/build.json'),'artifacts':m['sha256']}
for name,pin in selected.items():
    assert artifacts[name]['artifacts']['runtime.wasm']==pin['runtime_wasm_sha256'],f'{name}: central runtime differs from selected audited lane'
previous=json.loads((root/'tests/integration/prepared-validation/logs/ash-20261013T052853.log.provenance.json').read_text())
for field,filename in [('rts','mo-rts.wasm'),('rts_debug','mo-rts-debug.wasm')]:
    assert sha(sdk/'rts'/filename)==previous['tools'][field]['sha256'],'RTS changed'
ash=json.loads((ashroot/'ash-source-provenance.json').read_text())
for name,hashes in ash['files'].items():
    assert sha(ashroot/'ash-local'/name)==hashes['copied_sha256'],f'Ash source changed: {name}'
tests=[root/'tests/packaging.py',root/'tests/integration/run/signature-composition.mo',root/'packages/fast/tests/fixtures/PreparedComposition.mo',root/'packages/fast/tests/fixtures/RSA.mo',root/'packages/fast/tests/ash/PreparedComposition.mo',root/'packages/fast/tests/ash/PreparedComposition.ash.json',root/'tests/integration/run/prepared-composition.mo',*sorted((root/'tests/integration/fail').glob('prepared-*.mo'))]
tools={'moc':sdk/'src/moc','moc_wrapper':sdk/'bin/wrapper.sh','rts':sdk/'rts/mo-rts.wasm','rts_debug':sdk/'rts/mo-rts-debug.wasm','didc':Path('/home/devbox/.local/bin/didc'),'pocketic':Path('/home/devbox/.local/bin/pocket-ic'),'bun':Path(shutil.which('bun')),'test_runner':Path(shutil.which('test-runner'))}
fast_sources={str(p.relative_to(root)):sha(p) for p in sorted((root/'packages/fast/src').rglob('*')) if p.is_file()}
fast_tree_hash=hashlib.sha256(json.dumps(fast_sources,sort_keys=True,separators=(',', ':')).encode()).hexdigest()
record={'sdk_revision':subprocess.check_output(['git','-C',str(sdk),'rev-parse','HEAD'],text=True).strip(),'moc_version':subprocess.check_output([str(sdk/'bin/moc'),'--version'],text=True).strip(),'plugins':artifacts,'selected_runtime_parity':selected,'fast_sources_sha256':fast_sources,'fast_package_sha256':fast_tree_hash,'tools':{n:{'path':str(p.resolve()),'sha256':sha(p)} for n,p in tools.items()},'ash_provenance_sha256':sha(ashroot/'ash-source-provenance.json'),'test_sources_sha256':{str(p.relative_to(root)):sha(p) for p in tests}}
Path(sys.argv[1]).write_text(json.dumps(record,indent=2)+'\n')
print('Verified unchanged compiler/RTS, all23 plugin artifact/source closures, selected six-runtime parity, and private Ash source.')
