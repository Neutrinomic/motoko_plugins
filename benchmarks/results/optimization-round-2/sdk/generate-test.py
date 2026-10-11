from pathlib import Path
out=Path(__file__).resolve().parent
s=['//MOC-FLAG --plugin ../../../_build/compute-plugin-tests/callbacks','import Prim "mo:⛔";', '// Exhaustively compare both eight-bit domains, including sign boundaries.', 'var low = 0;', 'while (low < 256) {', '  var high = 0;', '  while (high < 256) {', '    let a = Prim.natToNat8(low); let b = Prim.natToNat8(high);', '    assert Prim.fixtureCompare<Nat8>(a, b) ==', '      (if (a < b) -1 else if (a == b) 0 else 1);', '    let x = Prim.intToInt8(low - 128); let y = Prim.intToInt8(high - 128);', '    assert Prim.fixtureCompare<Int8>(x, y) ==', '      (if (x < y) -1 else if (x == y) 0 else 1);', '    high += 1;', '  };', '  low += 1;', '};', '', '// Heap-loaded aliases retain the same canonical low tags as direct values.']
vectors={
'Nat16':['0','1','32767','32768','65534','65535'],
'Int16':['-32768','-32767','-1','0','1','32767'],
'Nat32':['0','1','2147483647','2147483648','4294967294','4294967295'],
'Int32':['-2147483648','-2147483647','-1','0','1','2147483647'],
'Char':["'\\u{0}'", "'a'", "'\\u{d7ff}'", "'\\u{e000}'", "'☃'", "'💫'", "'\\u{ffff}'", "'\\u{10000}'", "'\\u{10fffe}'", "'\\u{10ffff}'"]}
for typ,values in vectors.items():
    s += [f'type Alias{typ} = {typ};', f'let values{typ} : [Alias{typ}] = [{", ".join(values)}];', f'for (a in values{typ}.values()) {{', f'  for (b in values{typ}.values()) {{', f'    assert Prim.fixtureCompare<Alias{typ}>(a, b) ==', '      (if (a < b) -1 else if (a == b) 0 else 1);', '  };', '};']
(out.parents[1]/'test/compute-plugins/run/scalar-tagged-order.mo').write_text('\n'.join(s)+'\n')
