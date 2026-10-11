from pathlib import Path
import hashlib, importlib.util, json, os, subprocess
out=Path(__file__).resolve().parent/'map'
candidate=out.parents[2]
baseline=Path('/srv/shared/code/motoko_experiments/motoko_sha')
plugins=Path('/srv/shared/code/motoko_experiments/plugins')
spec=importlib.util.spec_from_file_location('plugin_build',plugins/'scripts/build.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
manifest=json.loads((plugins/'plugins/pure-map/plugin.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
provenance={'actor':sha(out/'main.mo'),'Map.mo':sha(out/'Map.mo'),'plugin_sources':{p.name:sha(p) for p in (plugins/'plugins/pure-map/compiler').glob('*.ml')},'compilers':{}}
for name,root in [('baseline',baseline),('candidate',candidate)]:
    work=out/name;work.mkdir(exist_ok=True)
    moc,includes=build.prepare_host(root,os.environ.copy(),True)
    package=build.compiler_plugin(manifest,includes,work,os.environ.copy())
    subprocess.run([str(root/'bin/moc'),'--plugin',str(work),str(out/'main.mo'),'-o',str(work/'main.wasm')],check=True)
    provenance['compilers'][name]={'revision':subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip(),'moc':sha(moc),'plugin':sha(package),'wasm':sha(work/'main.wasm')}
(out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
