from pathlib import Path
import json
out=Path(__file__).resolve().parent
vectors={
'Nat8':['0','1','127','128','254','255'],
'Int8':['-128','-127','-1','0','1','127'],
'Nat16':['0','1','32767','32768','65534','65535'],
'Int16':['-32768','-32767','-1','0','1','32767'],
'Nat32':['0','1','2147483647','2147483648','4294967294','4294967295'],
'Int32':['-2147483648','-2147483647','-1','0','1','2147483647'],
'Char':["'\\u{0}'", "'a'", "'☃'", "'💫'", "'\\u{10fffe}'", "'\\u{10ffff}'"],
'Bool':['false','false','false','true','true','Prim.fixtureTrue()'],
'Nat64':['0','1','1152921504606846975','1152921504606846976','18446744073709551614','18446744073709551615'],
'Int64':['-9223372036854775808','-576460752303423489','-1','0','576460752303423488','9223372036854775807'],
'Nat':['0','1','2305843009213693951','2305843009213693952','2 ** 300','2 ** 301'],
'Int':['-(2 ** 300)','-2305843009213693953','-1','0','2305843009213693952','2 ** 300'],
}
s=['import Prim "mo:⛔";','actor {','type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};','transient var repetitions = 0;','transient var checksum : Int = 0;','transient var expected : Int = 0;', 'public func configure(index : Nat) : async () { repetitions := [0, 1, 4096][index] };','public func clear() : async () { checksum := 0 };']
for typ,values in vectors.items():
    s.append(f'transient let inputs{typ} : [{typ}] = [{", ".join(values)}];')
    s.append(f'''public func compare{typ}() : async Measurement {{
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputs{typ}.values()) {{
    for (b in inputs{typ}.values()) {{
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    }};
    check += if (a < inputs{typ}[5]) -1 else if (a == inputs{typ}[5]) 0 else 1;
  }};
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {{
    var weight = 1;
    for (a in inputs{typ}.values()) {{
      for (b in inputs{typ}.values()) {{
        acc += Prim.fixtureCompare<{typ}>(a, b) * weight;
        weight += 1;
      }};
      acc += Prim.fixtureCompare<{typ}>(a, inputs{typ}[5]);
    }};
    iteration += 1;
  }};
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {{instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}}
}};''')
s += ['public query func bytesResult() : async Blob { assert checksum == expected; "ok" };','}']
s = [part.replace('a < b', 'not a and b').replace('a < inputsBool[5]', 'not a and inputsBool[5]') if 'public func compareBool' in part else part for part in s]
(out/'main.mo').write_text('\n'.join(s)+'\n')
(out/'cases.json').write_text(json.dumps({'cases':[{'name':f'scalar-comparisons-{n}', 'index':i,'family':'SDK scalar ordering','phases':[{'label':t,'method':'compare'+t,'kind':'checked_decode','require_no_gc':True} for t in vectors]} for i,n in enumerate([0,1,4096])], 'correctness':'All six-by-six pair orderings plus final-column comparisons contribute to retained checksum; expected checksum uses native Motoko operators outside timed region.'},indent=2)+'\n')
