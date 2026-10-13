#!/usr/bin/env python3
"""Build isolated scheduling benchmarks with frozen compiler/RTS provenance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def source(variant, kind):
    typ, compare, key, number = {
        'nat': ('Nat', 'Nat.compare', 'i', 'k'),
        'int': ('Int', 'Int.compare', 'i', 'Int.abs(k)'),
        'deadline': ('{at : Int; ticket : Nat}', 'compareDeadline',
                     '{at = i / 4; ticket = i}', 'k.ticket'),
    }[kind]
    imports = 'import Q "mo:fast/IndexedPriorityQueue";' if variant == 'plugin' else (
        'import Q "mo:core/PriorityQueue";' if variant == 'core-pq' else
        f'import Q "mo:{"core" if variant == "core-map" else "fast"}/Map";')
    if variant == 'plugin':
        storage = 'transient var queue = Q.empty<Key, Nat>(); transient var handles : [var ?Q.Handle<Key, Nat>] = [var];'
        reset = 'Q.clear(queue); handles := Prim.Array_init<?Q.Handle<Key, Nat>>(capacity, null);'
        add = f'handles[i] := ?Q.push(queue, {compare}, priority, value)'
        peek = 'Q.peek(queue)'
        pop = f'Q.pop(queue, {compare})'
        get = 'switch(handles[i]) {case (?h) Q.get(h); case null null}'
        remove = f'switch(handles[i]) {{case (?h) Q.remove(h, {compare}); case null null}}'
        reschedule = f'switch(handles[i]) {{case (?h) Q.reschedule(h, {compare}, priority); case null false}}'
        replace = f'switch(handles[i]) {{case (?h) Q.replace(h, {compare}, priority, value); case null null}}'
        clear = 'Q.clear(queue); handles := [var]'
    elif variant == 'core-pq':
        storage = 'transient var queue = Q.empty<(Key, Nat)>();'
        reset = 'Q.clear(queue);'
        add = 'Q.push(queue, comparePair, (priority, value))'
        peek = 'Q.peek(queue)'
        pop = 'Q.pop(queue, comparePair)'
        get = remove = replace = 'Prim.trap("Core PriorityQueue has no handle operations")'
        reschedule = 'Prim.trap("Core PriorityQueue has no handle operations")'
        clear = 'Q.clear(queue)'
    else:
        storage = 'transient var queue = Q.empty<Key, Nat>(); transient var handles : [var ?Key] = [var];'
        reset = 'Q.clear(queue); handles := Prim.Array_init<?Key>(capacity, null);'
        add = f'Q.add(queue, {compare}, priority, value); handles[i] := ?priority'
        peek = 'Q.minEntry(queue)'
        pop = f'switch (Q.minEntry(queue)) {{case (?pair) {{Q.remove(queue, {compare}, pair.0); ?pair}}; case null null}}'
        get = f'switch(handles[i]) {{case (?k) {{switch(Q.get(queue, {compare}, k)) {{case (?v) ?(k,v); case null null}}}}; case null null}}'
        remove = f'switch(handles[i]) {{case (?k) {{switch(Q.take(queue, {compare}, k)) {{case (?v) {{handles[i] := null; ?(k,v)}}; case null null}}}}; case null null}}'
        reschedule = f'switch(remove(i)) {{case (?(_,v)) {{add(i,priority,v); true}}; case null false}}'
        replace = 'let old = remove(i); switch old {case (?_) add(i,priority,value); case null {}}; old'
        clear = 'Q.clear(queue); handles := [var]'
    peek_priority = 'Q.peekPriority(queue)' if variant == 'plugin' else 'switch(peek()) {case (?(k,_)) ?k; case null null}'
    return f'''import Prim "mo:⛔";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
{imports}
actor {{
  type Key = {typ};
  type Pair = (Key, Nat);
  type Order = {{#less; #equal; #greater}};
  type Measurement = {{instructions : Nat64; allocated : Nat; reclaimed : Nat; checksum : Nat; count : Nat}};
  type Memory = {{heap : Nat; memory : Nat; allocated : Nat; reclaimed : Nat}};
  func compareDeadline(a : {{at : Int; ticket : Nat}}, b : {{at : Int; ticket : Nat}}) : Order {{
    if(a.at < b.at) #less else if(a.at > b.at) #greater else Nat.compare(a.ticket,b.ticket)
  }};
  func comparePair(a : Pair, b : Pair) : Order {{ {compare}(b.0,a.0) }};
  func key(i : Nat) : Key {{ {key} }};
  func number(k : Key) : Nat {{ {number} }};
  {storage}
  transient var configured = 0;
  transient var selectedDistribution = 0;
  func initial(i : Nat) : Nat {{switch(selectedDistribution) {{case 0 (configured - i); case 1 (i + 1); case 2 ((i * 157) % configured + 1); case 3 1; case _ (i % 16 + 1)}}}};
  transient var sink = 0;
  func add(i : Nat, priority : Key, value : Nat) {{ {add} }};
  func peek() : ?Pair {{ {peek} }};
  func peekPriority() : ?Key {{ {peek_priority} }};
  func pop() : ?Pair {{ {pop} }};
  func get(i : Nat) : ?Pair {{ {get} }};
  func remove(i : Nat) : ?Pair {{ {remove} }};
  func reschedule(i : Nat, priority : Key) : Bool {{ {reschedule} }};
  func replace(i : Nat, priority : Key, value : Nat) : ?Pair {{ {replace} }};
  func size() : Nat {{ Q.size(queue) }};
  func value(pair : ?Pair) : Nat {{switch pair {{case (?(_,v)) v; case null 0}}}};
  public func configure(n : Nat, capacity : Nat, distribution : Nat) : async () {{
    {reset}
    configured := n; selectedDistribution := distribution; sink := 0;
  }};
  public func fill(start : Nat, count : Nat) : async () {{
    var i = start;
    while(i < start + count) {{ let p = initial(i); add(i,key(p),p); i += 1 }};
  }};
  public func measure(operation : Nat, repetitions : Nat) : async Measurement {{
    let ab = Prim.rts_total_allocation();
    let rb = Prim.rts_reclaimed();
    let before = Prim.performanceCounter(0);
    var checksum = 0;
    var i = 0;
    while(i < repetitions) {{
      switch operation {{
        case 0 {{checksum += value(peek())}};
        case 1 {{checksum += value(get(i % configured))}};
        case 2 {{let p = configured + 1 + i; add(configured+i,key(p),p); checksum += p}};
        case 3 {{checksum += value(pop())}};
        case 4 {{checksum += value(remove(i))}};
        case 5 {{if(reschedule(i,key(configured+1+i))) checksum += 1}};
        case 6 {{checksum += value(replace(i,key(configured+1+i),configured+1+i))}};
        case 7 {{add(configured,key(0),i); checksum += value(pop())}};
        case 8 {{{clear}}};
        case 9 {{switch(peekPriority()) {{case (?k) checksum += number(k); case null {{}}}}}};
        case 10 {{add(configured+i,key(0),i); checksum += i}};
        case 11 {{if(reschedule(i,key(0))) checksum += 1}};
        case 12 {{checksum += value(remove((i * 157) % configured))}};
        case _ Prim.trap("unknown operation");
      }};
      i += 1;
    }};
    sink := checksum;
    let after = Prim.performanceCounter(0);
    let aa = Prim.rts_total_allocation();
    let ra = Prim.rts_reclaimed();
    {{instructions = after - before; allocated = aa - ab; reclaimed = ra - rb; checksum; count = size()}}
  }};
  public query func memory() : async Memory {{
    {{heap = Prim.rts_heap_size(); memory = Prim.rts_memory_size();
      allocated = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}}
  }};
  public func validate() : async {{count : Nat; sum : Nat; sorted : Bool}} {{
    var count = 0; var sum = 0; var previous = 0; var sorted = true;
    label drain loop {{ switch(pop()) {{
      case null break drain;
      case (?(k,v)) {{let p = number(k); if(count > 0 and p < previous) sorted := false;
        previous := p; count += 1; sum += v;}};
    }} }};
    {{count; sum; sorted}}
  }};
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=Path('/home/devbox/.local/lib/motoko-compute'))
    parser.add_argument('--core', type=Path, default=Path('/srv/shared/code/takt/.mops/core@2.6.2/src'))
    parser.add_argument('--phase', required=True)
    parser.add_argument('--variants', default='plugin,core-pq,core-map,fast-map')
    parser.add_argument('--keys', default='nat,int,deadline')
    args = parser.parse_args()
    phase = HERE / 'results' / args.phase
    if phase.exists():
        parser.error('phase already exists; use a fresh phase name')
    phase.mkdir(parents=True)
    bundle = args.bundle.resolve()
    stage = HERE/'_stage'
    stage.mkdir(exist_ok=True)
    # Freeze all imported Motoko modules at one fixed absolute path. Independent
    # owners can keep editing other plugins without changing these build inputs.
    shutil.copytree(ROOT/'packages/fast/src',stage/'fast',dirs_exist_ok=True)
    shutil.copytree(args.core,stage/'core',dirs_exist_ok=True)
    env = dict(os.environ, MOC_RELEASE_RTS=str(bundle/'mo-rts.wasm'), MOC_DEBUG_RTS=str(bundle/'mo-rts-debug.wasm'))
    hashes = {}
    def record(path):
        hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in (bundle/'moc',bundle/'mo-rts.wasm',bundle/'mo-rts-debug.wasm'):
        record(path)
    for path in (Path(__file__),HERE/'run.mjs'):
        target = phase/'harness'/path.name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(path,target)
        record(target)
    inputs = list((ROOT/'plugins/indexed-priority-queue').rglob('*.ml'))
    for path in inputs:
        target = phase/'source'/path.relative_to(ROOT)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(path,target)
        record(target)
    for base in (stage/'fast',stage/'core'):
        for path in base.rglob('*.mo'):
            target=phase/'imports'/path.relative_to(stage)
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(path,target)
            record(target)
    plugins = sorted({{'plugin':'indexed-priority-queue','fast-map':'mutable-map'}[variant]
                      for variant in args.variants.split(',') if variant in ('plugin','fast-map')})
    staged_hashes={}
    for plugin in plugins:
        plugin_stage=stage/'dist'/plugin
        shutil.copytree(ROOT/'dist'/plugin,plugin_stage,dirs_exist_ok=True)
        plugin_build=json.loads((plugin_stage/'build.json').read_text())
        for name,digest in plugin_build['source_sha256'].items():
            path=ROOT/name
            content=path.read_bytes()
            if hashlib.sha256(content).hexdigest()!=digest:
                raise ValueError(f'{plugin} source differs from built artifact: {name}')
            target=phase/'source'/name
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(content)
            record(target)
        for name,digest in plugin_build['sha256'].items():
            if hashlib.sha256((plugin_stage/name).read_bytes()).hexdigest()!=digest:
                raise ValueError(f'{plugin} artifact differs from manifest: {name}')
        for path in plugin_stage.iterdir():
            if path.is_file():
                target=phase/'artifacts'/plugin/path.name
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(path,target)
                record(target)
    for base in (stage/'fast',stage/'core',stage/'dist'):
        for path in base.rglob('*'):
            if path.is_file(): staged_hashes[path]=hashlib.sha256(path.read_bytes()).hexdigest()
    cases = []
    for variant in args.variants.split(','):
        for kind in args.keys.split(','):
            name = variant+'-'+kind
            mo = phase/(name+'.mo')
            mo.write_text(source(variant,kind))
            staged = HERE/'_stage'/(name+'.mo')
            staged.parent.mkdir(exist_ok=True)
            shutil.copyfile(mo,staged)
            wasm = phase/(name+'.wasm')
            command = [str(bundle/'moc'),'-A','M0236,M0194,M0244','--package','fast',str(stage/'fast'),'--package','core',str(stage/'core'),str(staged),'-o',str(wasm)]
            plugin = {'plugin':'indexed-priority-queue','fast-map':'mutable-map'}.get(variant)
            if plugin:
                plugin_stage=stage/'dist'/plugin
                command[1:1] = ['--plugin',str(plugin_stage)]
            subprocess.run(command,env=env,check=True)
            record(mo);record(wasm)
            cases.append({'variant':variant,'key':kind,'wasm':str(wasm),'command':command})
    for path,digest in staged_hashes.items():
        if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise ValueError(f'staged build input changed during phase: {path}')
    for path,digest in hashes.items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest:
            raise ValueError(f'build input changed during phase: {path}')
    (phase/'build.json').write_text(json.dumps({'phase':args.phase,'cases':cases,'sha256':hashes,
        'compiler_version':subprocess.check_output([str(bundle/'moc'),'--version'],env=env,text=True).strip(),
        'core':str(args.core),'core_sha256':{str(p.relative_to(args.core)):hashlib.sha256(p.read_bytes()).hexdigest() for p in args.core.rglob('*.mo')},
        'rts_environment':{k:env[k] for k in ('MOC_RELEASE_RTS','MOC_DEBUG_RTS')}},indent=2)+'\n')


if __name__ == '__main__':
    main()
