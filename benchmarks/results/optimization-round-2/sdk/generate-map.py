from pathlib import Path
import json,shutil
out=Path(__file__).resolve().parent/'map'
out.mkdir(exist_ok=True)
shutil.copy2('/srv/shared/code/motoko_experiments/plugins/plugins/pure-map/motoko/Map.mo',out/'Map.mo')
s=['import Prim "mo:⛔";','import Map "Map";','actor {','type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};','transient var count = 0;','transient var expected = 0;','transient var total = 0;', 'transient var overwritten = 0;', 'public func clear() : async () { total := 0; overwritten := 0 };']
for typ in ['Nat32','Int32']: s.append(f'transient var map{typ} : Map.Map<{typ}, Nat> = null;')
s += ['public func configure(index : Nat) : async () {', '  count := [1_000, 10_000, 100_000][index];', '  mapNat32 := null; mapInt32 := null;', '  var n = 0;', '  while (n < count) {', '    mapNat32 := Prim.pmap_add_static<Nat32, Nat>(mapNat32, Prim.natToNat32(n * 2), n);','    mapInt32 := Prim.pmap_add_static<Int32, Nat>(mapInt32, Prim.intToInt32(n * 2 - count), n);', '    n += 1;', '  };', '};']
phases=[]
for typ in ['Nat32','Int32']:
 for op in ['getHit','getMiss','overwrite']:
    name=typ+op; phases.append({'label':name,'method':name,'kind':'checked_decode','require_no_gc':True})
    key='Prim.natToNat32(n * 2)' if typ=='Nat32' else 'Prim.intToInt32(n * 2 - count)'
    if op=='getMiss': key=key.replace('n * 2','n * 2 + 1')
    code=f'let ?value = Prim.pmap_get_static<{typ}, Nat>(map{typ}, key) else Prim.trap("missing"); acc += value;'
    if op=='getMiss':code=f'assert Prim.pmap_get_static<{typ}, Nat>(map{typ}, key) == null; acc += 1;'
    if op=='overwrite':code=f'map{typ} := Prim.pmap_add_static<{typ}, Nat>(map{typ}, key, n + 1); acc += n + 1;'
    s += [f'public func {name}() : async Measurement {{', '  expected := 0;', '  var n = 0;', '  while (n < 1000) {', '    expected += '+('1' if op=='getMiss' else ('n % count + 1' if op=='overwrite' else 'n % count'))+';', '    n += 1;', '  };', f'  overwritten := {1 if typ=="Nat32" else 2};' if op=='overwrite' else '  overwritten := 0;', '  let beforeAllocation = Prim.rts_total_allocation();', '  let beforeReclaimed = Prim.rts_reclaimed();', '  let started = Prim.performanceCounter(0);', '  var acc = 0;', '  var i = 0;', '  while (i < 1000) {', '    let n = i % count;',f'    let key = {key};', f'    {code}', '    i += 1;', '  };', '  total := acc;', '  let ended = Prim.performanceCounter(0);', '  let afterAllocation = Prim.rts_total_allocation();', '  let afterReclaimed = Prim.rts_reclaimed();', '  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;', '   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}', '};']
s += ['public query func bytesResult() : async Blob { assert total == expected; var i = 0; while (i < 1000 and overwritten != 0) { let n = i % count; if (overwritten == 1) { assert Prim.pmap_get_static<Nat32, Nat>(mapNat32, Prim.natToNat32(n * 2)) == ?(n + 1) } else { assert Prim.pmap_get_static<Int32, Nat>(mapInt32, Prim.intToInt32(n * 2 - count)) == ?(n + 1) }; i += 1 }; "ok" };','}']
(out/'main.mo').write_text('\n'.join(s)+'\n')
(out/'cases.json').write_text(json.dumps({'cases':[{'name':f'map-scalar-{n}', 'index':i,'family':'SDK static scalar maps','phases':phases} for i,n in enumerate([1000,10000,100000])], 'correctness':'Native expected lookup checksums, missing lookups, and overwritten retained maps; 1000 operations on prebuilt maps; setup excluded.'},indent=2)+'\n')
