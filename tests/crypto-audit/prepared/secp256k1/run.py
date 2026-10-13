#!/usr/bin/env python3
"""Run only after candidate freeze and a coordinator execution-slot grant."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tomllib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin",type=Path,required=True)
    parser.add_argument("--motoko",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--pause-file",type=Path,help="Coordinator may create this file to pause between all-engine fixtures")
    args=parser.parse_args()
    plugin,motoko,out=args.plugin.resolve(),args.motoko.resolve(),args.out.resolve()
    out.mkdir(parents=True,exist_ok=True)
    build=json.loads((plugin/"build.json").read_text())
    sources={f:h for f,h in build["source_sha256"].items() if f.startswith("plugins/secp256k1/")}
    artifacts={f.name:sha(f) for f in plugin.iterdir() if f.is_file()}
    stage=plugin.parent.parent
    module=ROOT/"packages/fast/src/Secp256k1.mo"
    module_hash=sha(module)
    assert all(sha(stage/f)==h for f,h in sources.items()),"stale source"
    assert all(artifacts[f]==h for f,h in build["sha256"].items()),"stale artifact"
    assert sha(motoko/"src/moc")==build["moc_sha256"],"mismatching compiler"
    report={"sources_sha256":sources,"artifacts_sha256":artifacts,"moc_sha256":build["moc_sha256"],"module_sha256":module_hash,"runs":[]}
    def run(command,name,cwd=ROOT,env=None,expected=0):
        log=out/name
        with log.open("w") as f:
            result=subprocess.run(list(map(str,command)),cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
        report["runs"].append({"command":list(map(str,command)),"cwd":str(cwd),"exit":result.returncode,"expected_exit":expected,"log":name,"sha256":sha(log)})
        print(f"{name}: exit {result.returncode}",flush=True)
        if result.returncode!=expected: print(log.read_text()[-6000:],flush=True)
        return result.returncode==expected
    outcomes=[run([sys.executable,HERE/"check_generator.py"],"generator.log")]
    generated=run([sys.executable,HERE/"generate.py","--plugin",plugin,"--out",out],"generate.log")
    outcomes.append(generated)
    if generated:
        capacity=re.search(r"const PUBLIC_CACHE_SIZE: usize = (\d+);",(ROOT/"plugins/secp256k1/runtime/src/lib.rs").read_text()).group(1)
        report["public_cache_bytes"]=int(capacity)
        report["independently_compared_public_points"]=32*2*(int(capacity)//64)
        env=dict(os.environ,SECP_AUDIT_VECTORS=str(out/"native-vectors.tsv"),SECP_AUDIT_CACHE_SIZE=capacity)
        for mode in ["debug","release"]:
            command=["cargo","test","--offline","--jobs","2","--manifest-path",HERE/"native/Cargo.toml","--target-dir",out/"native-target"]
            if mode=="release": command.append("--release")
            command += ["--","--nocapture","--test-threads=2"]
            outcomes.append(run(command,f"native-{mode}.log",env=env))
        root_packages={(p["name"],p["version"],p.get("checksum")) for p in tomllib.loads((ROOT/"Cargo.lock").read_text())["package"] if p.get("source","").startswith("registry+")}
        native_packages={(p["name"],p["version"],p.get("checksum")) for p in tomllib.loads((HERE/"native/Cargo.lock").read_text())["package"] if p.get("source","").startswith("registry+")}
        report["native_registry_dependencies_match_runtime_lock"]=native_packages.issubset(root_packages)
        outcomes.append(report["native_registry_dependencies_match_runtime_lock"])
        for fixture in sorted((out/"run").glob("*.mo")):
            if args.pause_file and args.pause_file.exists():
                print("Paused between fixtures for coordinator measurement wave",flush=True)
                while args.pause_file.exists(): time.sleep(0.5)
            outcomes.append(run(["test-runner","-b","-j","1",fixture],"motoko-"+fixture.stem+".log",motoko))
        for fixture in sorted((out/"fail").glob("*.mo")):
            command=[motoko/"bin/moc","--check","--package","fast",ROOT/"packages/fast/src","--plugin",plugin,fixture]
            ok=run(command,"reject-"+fixture.stem+".log",motoko,expected=1)
            # A missing plugin/compiler or parse failure must never pass a type-rejection gate.
            error=(out/("reject-"+fixture.stem+".log")).read_text()
            outcomes.append(ok and ("type error" in error) and "syntax error" not in error)
    report["generated"]=json.loads((out/"generated.json").read_text()) if generated else None
    report["engines"]={}
    for fixture in sorted((out/"run").glob("*.mo")):
        files={suffix:out/"run/_out"/(fixture.stem+"."+suffix) for suffix in ["run","run-ir","run-low","wasm-run","valid"]}
        report["engines"][fixture.name]={suffix:sha(p) for suffix,p in files.items() if p.is_file()}
        outcomes.append(all(p.is_file() for p in files.values()))
    outcomes.append(all(sha(stage/f)==h for f,h in sources.items()))
    outcomes.append(all(sha(plugin/f)==h for f,h in artifacts.items()))
    outcomes.append(sha(module)==module_hash)
    report["audit_sources_sha256"]={str(p.relative_to(HERE)):sha(p) for p in [HERE/"run.py",HERE/"generate.py",HERE/"check_generator.py",HERE/"native/Cargo.toml",HERE/"native/Cargo.lock",HERE/"native/src/lib.rs"]}
    report["passed"]=all(outcomes)
    (out/"evidence.json").write_text(json.dumps(report,indent=2)+"\n")
    print("passed="+str(report["passed"]),flush=True)
    return 0 if report["passed"] else 1
if __name__=="__main__": raise SystemExit(main())
