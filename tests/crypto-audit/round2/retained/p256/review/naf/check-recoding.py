from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parent
source=root.parent/'p256-verify-naf/plugins/p256/runtime/src/lib.rs'

def recode(value):
    data=value.to_bytes(32,'big')
    digits=[0]*257
    position=0
    carry=0
    while position<257:
        window=carry
        for offset in range(5):
            bit=position+offset
            if bit<256:
                window+=((data[31-bit//8]>>(bit%8))&1)<<offset
        if window&1==0:
            position+=1
            continue
        if window<16:
            digits[position]=window
            carry=0
        else:
            digits[position]=window-32
            carry=1
        position+=5
    return digits

values=[x for x in range(65536)]
values += [x<<240 for x in range(65536)]
values += [int.from_bytes(hashlib.sha256(x.to_bytes(4,'big')).digest(),'big') for x in range(4096)]
for bit in range(256):
    values += [(1<<bit)-1,1<<bit,(1<<bit)+1]
values += [(1<<256)-1,int('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',16)-1]
for value in values:
    digits=recode(value)
    assert sum(digit<<bit for bit,digit in enumerate(digits))==value, hex(value)
    for bit,digit in enumerate(digits):
        assert digit==0 or (digit&1 and abs(digit)<=15), (value,bit,digit)
        if digit:
            assert not any(digits[bit+1:bit+5]), (value,bit,digit)
report={'candidate_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'cases':len(values),'checks':['Exact integer reconstruction','257digit bounded output','Odd nonzero digits in[-15,15]','Fourzero digits follow every nonzero digit'],'coverage':['Every16-bit value in low16and high16positions','4096SHA256 deterministic256-bit samples','Power-of-two ±1edges across256bits','Full256-bit max and scalarorderminus1'],'result':'passed','scope':'Independent Python model of Rust recoder; native curve differential tests owned by implementation agent'}
(root/'recoding-results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
