#!/usr/bin/env python3
"""Emit exact-oracle public API actors using the shared round-three harness."""
import argparse
import importlib.util
import json
from pathlib import Path
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--common', type=Path, default=HERE.parent/'common.py')
args = parser.parse_args()
spec = importlib.util.spec_from_file_location('round3_common', args.common)
common = importlib.util.module_from_spec(spec); spec.loader.exec_module(common)
vectors = json.loads((HERE/'fixtures/openssl.json').read_text())['vectors']
rows = {len(bytes.fromhex(v['message'])):v for v in vectors}
base = rows[32]
cases = []

def add(name, expression, fixture, result_type, output, expected, setup_extra=''):
    setup = '\n  '.join('transient var '+key+' : Blob = "";' for key in ['seed','key','message','signature'])
    configure = '\n    '.join(key+' := '+common.blob(fixture[field])+';'
        for key,field in [('seed','seed'),('key','publicKey'),('message','message'),('signature','signature')])
    source = common.actor('import Ed25519 "mo:fast/Ed25519";', setup, configure+setup_extra,
        'result := '+expression+';', output_expr=output, output_type='Ed25519.Result<'+result_type+'>',
        initial='#err(#invalidSignature)', memory_metrics=True)
    target=HERE/'cases'/name/'main.mo';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source)
    cases.append({'name':name,'family':'ed25519','implementation':'fast','comparison':name,
        'plugins':['ed25519'],'source':target.relative_to(HERE.parent.parent).as_posix(),
        'expected_hex':expected,'operations_per_sample':1,'memory_metrics':True,
        'notes':'One public API call; inputs prepared before measurement, Result checking/formatting and heap queries after measurement.',
        'fixture_provenance':'Independent Node/OpenSSL Ed25519 fixture '+fixture['name']})

blob_result='switch(result) { case (#ok value) value; case (#err _) { assert false; "" } }'
bool_result='switch(result) { case (#ok true) "\\01"; case (#ok false) "\\00"; case (#err _) { assert false; "" } }'
add('ed25519-derive-public-key', 'Ed25519.derivePublicKey(seed)', base, 'Blob', blob_result, base['publicKey'])
add('ed25519-key-pair-from-seed', 'Ed25519.keyPairFromSeed(seed)', base, 'Ed25519.KeyPair',
    'switch(result) { case (#ok pair) { assert pair.secretKey == seed; pair.publicKey }; case (#err _) { assert false; "" } }',base['publicKey'])
add('ed25519-validate-public-key', 'Ed25519.validatePublicKey(key)', base, 'Bool', bool_result, '01')
for length in [0,32,1024]:
    v=rows[length]
    add(f'ed25519-sign-{length}B','Ed25519.sign(seed, message)',v,'Blob',blob_result,v['signature'])
    add(f'ed25519-verify-{length}B','Ed25519.verify(key, message, signature)',v,'Bool',bool_result,'01')
    add(f'ed25519-wrong-message-{length}B','Ed25519.verify(key, message, signature)',v,'Bool',bool_result,'00',
        '\n    message := '+common.blob(v['message']+'00')+';')
# S=0 with an ordinary valid R is well-formed and does not satisfy the equation.
add('ed25519-wrong-signature','Ed25519.verify(key, message, signature)',base,'Bool',bool_result,'00',
    '\n    signature := '+common.blob(base['signature'][:64]+'00'*32)+';')
add('ed25519-malformed-signature','Ed25519.verify(key, message, signature)',base,'Bool',
    'switch(result) { case (#err(#invalidSignature)) "\\03"; case (_) { assert false; "" } }','03',
    '\n    signature := "";')
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} Ed25519 cases')
