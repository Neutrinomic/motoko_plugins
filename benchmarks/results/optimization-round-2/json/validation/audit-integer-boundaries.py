from pathlib import Path
import random
import sys

source=Path(sys.argv[1])
out=Path(sys.argv[2])
source_text=source.read_text()
rng=random.Random(290411)
values={0,1,-1}
for n in [1,6,7,8,14,31,32,63,64,65,127,128,255,256,511,512,1024,2048,4096,8192,13605]:
    for delta in [-1,0,1]:
        values.add((1<<n)+delta)
        values.add(-((1<<n)+delta))
for n in [1,8,9,10,17,18,19,26,27,36,127,128,1024,4095]:
    for delta in [-1,0,1]:
        values.add(10**n+delta)
        values.add(-(10**n+delta))
for _ in range(250):
    n=rng.randrange(0,13607)
    value=rng.getrandbits(n)
    values.add(value if rng.randrange(2) else -value)

def leb(value,signed):
    result=[]
    while True:
        byte=value&127
        value>>=7
        done=(value==0 and (not signed or not byte&64)) or (signed and value==-1 and byte&64)
        result.append(byte if done else byte|128)
        if done:
            return result

rows=[]
for value in sorted(values):
    for signed in [False,True] if value>=0 else [True]:
        data=leb(value,signed)
        expected=str(value)
        assert len(expected.removeprefix('-'))<=4096
        assert len(data)<=2048
        rows.append(f'assert_eq!(leb_to_decimal(&{data!r}, {str(signed).lower()}), b"{expected}");')
appended='\n#[cfg(test)] mod independent_integer_audit {\nuse super::*;\n#[test] fn direct_leb_vectors() {\n'+'\n'.join(rows)+'\n}\n}\n'
out.write_text(source_text+appended)
print(f'Generated {len(rows)} independent Python integer/LEB vectors; seed 290411, up to 4096 decimal digits.')
