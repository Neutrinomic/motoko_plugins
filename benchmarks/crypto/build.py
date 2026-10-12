#!/usr/bin/env python3
"""Freeze benchmark inputs, verify dependency locks and plugin provenance, compile cases."""
import argparse, hashlib, json, os, re, shutil, subprocess, tarfile
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[1]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--manifest',type=Path,default=HERE/'cases.json')
p.add_argument('--stage',required=True)
p.add_argument('--bundle',type=Path,default=Path('/home/devbox/.local/lib/motoko-compute'))
p.add_argument('--moc',type=Path)
p.add_argument('--fast-root',type=Path,help='Source directory for a plugin-compatible frozen mo:fast package')
p.add_argument('--filter',default='.')
p.add_argument('--plugin-roots',type=Path,help='JSON map plugin name to an isolated build root')
p.add_argument('--implementation',default='.')
a=p.parse_args(); bundle=a.bundle.resolve(); moc=(a.moc or bundle/'moc').resolve()
archive=HERE/'results'/a.stage
archive.mkdir(parents=True,exist_ok=False)
manifest=json.loads(a.manifest.read_text()); cases=manifest['cases'] if isinstance(manifest,dict) else manifest
cases=[c for c in cases if re.search(a.filter,c['name']) and re.search(a.implementation,c['implementation'])]
assert cases, 'No cases selected'
deps=HERE/'dependencies'; lock=json.loads((deps/'mops.lock').read_text())
packages={alias:f'{alias.split("@")[0]}@{ver}' for alias,ver in lock['deps'].items()}
assert set(packages.values())==set(lock['hashes'])
for package,hashes in lock['hashes'].items():
  for name,expected in hashes.items():
    assert name.startswith(package+'/') and '..' not in Path(name).parts
    assert sha(deps/'.mops'/name)==expected, f'Dependency integrity failure: {name}'
  for src in (deps/'.mops'/package/'src').rglob('*.mo'):
    assert str(src.relative_to(deps/'.mops')) in hashes, f'Unpinned source: {src}'
freeze=archive/'inputs'; freeze.mkdir(exist_ok=True)
plugins=sorted(set(x for c in cases for x in c.get('plugins',[])))
plugin_roots={k:Path(v).resolve() for k,v in json.loads(a.plugin_roots.read_text()).items()} if a.plugin_roots else {}
relocations={}
pinned_sources=[]
paths={moc,bundle/'mo-rts.wasm',bundle/'mo-rts-debug.wasm',a.manifest.resolve(),Path(__file__),HERE/'run.mjs',deps/'mops.toml',deps/'mops.lock'}
paths.update(HERE.glob('*.py'));paths.update(HERE.glob('*.mjs'));paths.update(p for p in (HERE/'fixtures').rglob('*') if p.is_file())
paths.update(p for p in (HERE/'curve-cases').glob('*.json') if 'roots' not in p.name)
fast_root=(a.fast_root or ROOT/'packages/fast/src').resolve()
for src in fast_root.rglob('*.mo'):
  paths.add(src);relocations[src]=Path('packages/fast/src')/src.relative_to(fast_root)
for plugin in plugins:
  plugin_root=plugin_roots.get(plugin,ROOT)
  build=json.loads((plugin_root/'dist'/plugin/'build.json').read_text())
  assert build['moc_sha256']==sha(moc), 'Plugin compiler mismatch: '+plugin
  for name,expected in build['sha256'].items():
    assert sha(plugin_root/'dist'/plugin/name)==expected, f'Plugin artifact mismatch: {plugin}/{name}'
  for name,expected in build['source_sha256'].items():
    assert not Path(name).is_absolute() and '..' not in Path(name).parts
    src=plugin_root/name
    assert sha(src)==expected, f'Plugin source/artifact mismatch: {name}'
    paths.add(src);relocations[src]=Path('plugin-build-inputs')/plugin/name
    pinned_sources.append((src,Path('plugin-build-inputs')/plugin/name,expected))
  for name in ['Cargo.lock','Cargo.toml']:
    cargo=plugin_root/name
    if cargo.exists(): paths.add(cargo);relocations[cargo]=Path('plugin-locks')/plugin/name
  plugin_paths=[p for p in (plugin_root/'dist'/plugin).rglob('*') if p.is_file()]
  plugin_paths += [p for p in (plugin_root/'plugins'/plugin).rglob('*') if p.is_file() and 'target' not in p.parts]
  paths.update(plugin_paths)
  for src in plugin_paths: relocations[src]=src.relative_to(plugin_root)
for case in cases: paths.add(HERE/case['source'])
# Hash all locked dependency files; no network or dependency resolution during a build.
paths.update(deps/'.mops'/name for hashes in lock['hashes'].values() for name in hashes)
before={str(path):sha(path) for path in sorted(paths)}
for src in sorted(paths):
  if src==moc: rel=Path('toolchain/moc')
  elif src in [bundle/'mo-rts.wasm',bundle/'mo-rts-debug.wasm']: rel=Path('toolchain')/src.name
  elif src in relocations: rel=relocations[src]
  elif src.is_relative_to(ROOT): rel=src.relative_to(ROOT)
  else: rel=Path('toolchain')/src.name
  dest=freeze/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dest)
for src,relative,expected in pinned_sources:
  dest=freeze/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
  assert sha(dest)==expected, f'Frozen plugin source mismatch: {relative}'
assert before=={str(path):sha(path) for path in sorted(paths)}, 'Inputs changed while freezing'
for plugin in plugins:
  plugin_build=json.loads((freeze/'dist'/plugin/'build.json').read_text())
  for name,expected in plugin_build['sha256'].items():
    assert sha(freeze/'dist'/plugin/name)==expected, f'Frozen plugin artifact mismatch: {plugin}/{name}'
env=dict(os.environ,MOC_RELEASE_RTS=str(freeze/'toolchain/mo-rts.wasm'),MOC_DEBUG_RTS=str(freeze/'toolchain/mo-rts-debug.wasm'))
# Keep original executable path: loader resolution may depend on installed glibc symlink.
args=[]
for alias,package in packages.items(): args+=['--package',alias,str(freeze/'benchmarks/crypto/dependencies/.mops'/package/'src')]
args+=['--package','fast',str(freeze/'packages/fast/src')]
report={'stage':a.stage,'rts_environment':{k:env[k] for k in ['MOC_RELEASE_RTS','MOC_DEBUG_RTS']},'compiler_sha256':sha(moc),'compiler_version':subprocess.check_output([str(moc),'--version'],env=env,text=True).strip(),'inputs_sha256':before,'dependency_aliases':packages,'expected_case_count':len(cases),'complete':False,'cases':[]}
for case in cases:
  dest=archive/case['name']/case['implementation'];dest.mkdir(parents=True,exist_ok=True)
  command=[str(moc),*args]
  for plugin in case.get('plugins',[]):command+=['--plugin',str(freeze/'dist'/plugin)]
  command+=[str(freeze/'benchmarks/crypto'/case['source']),'-o',str(dest/'main.wasm')]
  assert sha(moc)==before[str(moc)], 'Compiler changed after freezing'
  result=subprocess.run(command,env=env,text=True,capture_output=True)
  (dest/'compile.log').write_text(result.stdout+result.stderr)
  item={**case,'command':command,'returncode':result.returncode,'source_sha256':sha(freeze/'benchmarks/crypto'/case['source'])}
  if result.returncode==0:item.update(wasm=str((dest/'main.wasm').relative_to(archive)),wasm_sha256=sha(dest/'main.wasm'),wasm_bytes=(dest/'main.wasm').stat().st_size)
  else:item['error']='Compilation failed; see '+str((dest/'compile.log').relative_to(archive))
  report['cases'].append(item);(archive/'build.json').write_text(json.dumps(report,indent=2)+'\n')
  print(case['name'],case['implementation'],result.returncode,flush=True)
# Full frozen source + binary artifacts remain locally; archive sources in a portable compressed bundle.
with tarfile.open(archive/'sources.tar.gz','w:gz') as tar:
  for src in sorted(freeze.rglob('*')):
    if src.is_file() and 'toolchain' not in src.relative_to(freeze).parts and ('dist' not in src.relative_to(freeze).parts or src.suffix=='.json'):
      tar.add(src,arcname=src.relative_to(freeze))
assert sha(moc)==before[str(moc)], 'Compiler changed during build'
report['complete']=True
(archive/'build.json').write_text(json.dumps(report,indent=2)+'\n')
print(archive/'build.json')
