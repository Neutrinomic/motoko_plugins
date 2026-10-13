#!/usr/bin/env python3
"""P256 matched direct/prepared fixtures with preparation measured separately."""
import argparse
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
ROOT = BENCH.parents[1]

def blob(value):
    return '"' + ''.join('\\%02x' % b for b in bytes.fromhex(value)) + '"'

def check_fixtures(fixtures):
    # Independent Python integer curve arithmetic, also checked against OpenSSL
    # by the table generator. No runtime output supplies an expected answer.
    path = ROOT/'plugins/p256/tests/vectors/generate-p256-comb.py'
    spec = importlib.util.spec_from_file_location('point_oracle', path)
    curve = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(curve)
    order = int('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',16)
    def mul(point, scalar):
        result = None
        while scalar:
            if scalar & 1: result = curve.add(result, point)
            point = curve.add(point, point)
            scalar >>= 1
        return result
    for fixture in fixtures:
        key = bytes.fromhex(fixture['public'])
        assert len(key) == 33 and key[0] in (2,3)
        x = int.from_bytes(key[1:], 'big')
        y = pow((x*x*x-3*x+int('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',16)) % curve.P, (curve.P+1)//4, curve.P)
        if y & 1 != key[0] & 1: y = curve.P-y
        signature = fixture['signature']
        r,s = int(signature[:64],16),int(signature[64:],16)
        inverse = pow(s,-1,order)
        point = curve.add(mul(curve.G,int(fixture['digest'],16)*inverse % order),mul((x,y),r*inverse % order))
        assert (point is not None and point[0] % order == r) == fixture['valid'], fixture['label']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screen', action='store_true', help='RFC sample and reuse 1/2/10/100 only')
    args = parser.parse_args()
    proof = json.loads((ROOT/'plugins/p256/tests/vectors/prepared-comb-proof.json').read_text())
    width = proof['width']
    old = BENCH/'round3/p256/audit/independent-vectors.json'
    oracle = json.loads(old.read_text())
    fixtures = []
    for item in oracle['vectors']:
        if item['label'] in ['one/zero', 'one/order', 'order-minus-one/max']:
            fixtures.append({**item, 'valid': True})
    sample = next(v for v in oracle['vectors'] if v['label'] == 'RFC6979/sample')
    sample = {**sample, 'label':'rfc-sample', 'valid':True}
    fixtures = [sample] + [v for v in fixtures if v['digest'] != sample['digest']]
    if args.screen:
        fixtures = [sample]
    else:
        fixtures += [{**sample,'label':'rfc-wrong-digest','digest':'00'*32,'valid':False},
                     {**sample,'label':'rfc-wrong-key','public':oracle['vectors'][0]['public'],'valid':False}]
        order = int('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',16)
        sig = sample['signature']; low = min(int(sig[64:],16),order-int(sig[64:],16))
        fixtures += [{**sample,'label':'rfc-low-s','signature':sig[:64]+f'{low:064x}'}]
    check_fixtures(fixtures)
    fixture_file = HERE/'fixtures.json'
    fixture_file.write_text(json.dumps({'oracle':oracle['oracle'], 'upstream_file':str(old.relative_to(BENCH)),
        'upstream_sha256':hashlib.sha256(old.read_bytes()).hexdigest(), 'vectors':fixtures},indent=2)+'\n')
    cases=[]
    for fixture in fixtures:
        fid=fixture['label'].replace('/','-')
        modes=[('direct',1),('prepare',1),('prepared',1),('cold',1)]
        if fixture is sample: modes += [(mode,reuse) for reuse in (2,10,100) for mode in ('direct','prepared','cold')]
        for mode,reuse in modes:
            name=f'p256-w{width}-{fid}-{mode}-{reuse}'
            declaration='transient var prepared : ?P256.PreparedPublicKey = null;'
            key='let ?key = prepared else Prim.trap("missing prepared key");'
            prepare='let #ok(key) = P256.preparePublicKey(publicKey) else Prim.trap("prepare error"); prepared := ?key;'
            configure=prepare if mode=='prepared' else ''
            verify='P256.verifyPrehashPrepared(key, digest, signature)' if mode in ('prepared','cold') else 'P256.verifyPrehash(publicKey, digest, signature)'
            operation=prepare if mode=='prepare' else ((('do { '+prepare+' }; ' if mode=='cold' else '')+(key if mode in ('prepared','cold') else ''))+f' var i = 0; while (i < {reuse}) {{ result := {verify}; i += 1 }};')
            output=(key+' let answer = P256.verifyPrehashPrepared(key, digest, signature);') if mode=='prepare' else 'let answer = result;'
            source=f'''import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {{
  transient let publicKey : Blob = {blob(fixture['public'])};
  transient let digest : Blob = {blob(fixture['digest'])};
  transient let signature : Blob = {blob(fixture['signature'])};
  transient var result : P256.Result<Bool> = #ok false;
  {declaration}
  public func configure() : async () {{ {configure} }};
  public func run() : async {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}} {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    {operation}
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 1}}
  }};
  public query func memory() : async {{heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat}} {{
    {{heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
      totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}}
  }};
  public query func bytesResult() : async Blob {{
    {output}
    let #ok(value) = answer else Prim.trap("verification error");
    assert value == {str(fixture['valid']).lower()};
    if (value) "\\01" else "\\00"
  }};
}}
'''
            target=HERE/'cases'/name/'main.mo';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source)
            cases.append({'name':name,'implementation':'native','family':'p256','plugins':['p256'],
                'source':target.relative_to(BENCH).as_posix(),'expected_hex':'01' if fixture['valid'] else '00',
                'memory_metrics':True,'prepared':{'scheme':'p256','profile':'RFC6979-SHA256-prehash',
                'operation':'verifyPrehash','fixture':fid,'fixture_source':fixture_file.relative_to(BENCH).as_posix(),
                'comparison_group':f'p256-w{width}-{fid}','mode':mode,'reuse':reuse,
                'payload_bytes':0 if mode=='direct' else ((1<<width)-1)*64}})
    live = {case['name'] for case in cases}
    for directory in (HERE/'cases').iterdir():
        if directory.is_dir() and directory.name.startswith('p256-w') and directory.name not in live:
            shutil.rmtree(directory)
    (HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
    print(f'Generated {len(cases)} width-{width} cases')

if __name__=='__main__': main()
