#!/usr/bin/env python3
"""Compile a fixed benchmark path and archive all source/artifact identities."""
import argparse, hashlib, json, os, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--bundle', type=Path, default=Path('/home/devbox/.local/lib/motoko-compute'))
p.add_argument('--core', type=Path, default=Path('/srv/shared/code/takt/.mops/core@2.6.2/src'))
p.add_argument('--stage', required=True)
a=p.parse_args(); here=Path(__file__).resolve().parent; root=here.parent.parent
out=here/'_out'; out.mkdir(exist_ok=True)
archive=here/'results'/a.stage; archive.mkdir(parents=True,exist_ok=False)
bundle=a.bundle.resolve(); core=a.core.resolve()
env=dict(os.environ,MOC_RELEASE_RTS=str(bundle/'mo-rts.wasm'),MOC_DEBUG_RTS=str(bundle/'mo-rts-debug.wasm'))
command=[str(bundle/'moc'),'--plugin',str(root/'dist/history-ring'),'--package','fast',str(root/'packages/fast/src'),'--package','core',str(core),str(here/'main.mo'),'-o',str(out/'main.wasm')]
paths=[Path(__file__),here/'main.mo',here/'run.mjs',root/'packages/fast/src/HistoryRing.mo',bundle/'moc',bundle/'mo-rts.wasm',bundle/'mo-rts-debug.wasm']
paths+=sorted((root/'plugins/history-ring').rglob('*.ml'))+sorted((root/'plugins/history-ring').glob('plugin.json'))+sorted((root/'dist/history-ring').glob('*'))
# Hash every core source file because imports are transitive.
paths+=sorted(core.rglob('*.mo'))
hash_file=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
before={str(path):hash_file(path) for path in paths if path.is_file()}
plugin_build=json.loads((root/'dist/history-ring/build.json').read_text())
for relative, expected in plugin_build['source_sha256'].items():
 if relative.startswith('plugins/history-ring/'):
  assert hash_file(root/relative)==expected, f'Plugin binary/source mismatch: {relative}'
subprocess.run(command,env=env,check=True)
assert before=={str(path):hash_file(path) for path in paths if path.is_file()}, 'Build inputs changed during compilation'
paths.append(out/'main.wasm')
report={'stage':a.stage,'command':command,'rts_environment':{k:env[k] for k in ['MOC_RELEASE_RTS','MOC_DEBUG_RTS']},'compiler_version':subprocess.check_output([str(bundle/'moc'),'--version'],text=True,env=env).strip(),'sha256':{str(path):hash_file(path) for path in paths if path.is_file()}}
(archive/'build.json').write_text(json.dumps(report,indent=2)+'\n')
for path in paths:
 if path.is_file() and path.is_relative_to(root) and not path.is_relative_to(core) and path != out/'main.wasm':
  relative=path.relative_to(root);target=archive/'sources'/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(path.read_bytes())
(archive/'main.wasm').write_bytes((out/'main.wasm').read_bytes())
print(archive)
