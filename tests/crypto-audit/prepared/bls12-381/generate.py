#!/usr/bin/env python3
"""Generate independent prepared-key tests from retained external vectors."""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'plugins/bls12-381/tests/vectors/profiles.json'
RFC = ROOT / 'plugins/bls12-381/runtime/vectors/rfc9380.rs'
v = json.loads(SOURCE.read_text())
extra = json.loads((HERE/'extra.json').read_text())
for group in ['ic_keys', 'eth_keys', 'eth_proofs', 'ic_signatures', 'eth_signatures']:
    v[group].append(extra['negative'][group[:-1]])
rfc = RFC.read_text()
q1 = re.search('q0: "([a-f0-9]+)"', rfc).group(1)
q2 = re.search('q0: "([a-f0-9]+)"', rfc.split('pub const G2_VECTORS')[1]).group(1)
modulus = int('1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab', 16)
identity = lambda n: 'c0' + '00' * (n - 1)

def malformed(n, q):
    return [('empty', '', 1), ('short', '00' * (n - 1), 1),
            ('long', '00' * (n + 1), 1), ('flags', '00' * n, 2),
            ('infinity-sign', 'e0' + '00' * (n - 1), 2),
            ('infinity-coordinate', 'c0' + '00' * (n - 2) + '01', 2),
            ('field-modulus', ((modulus | (1 << 383)).to_bytes(48, 'big') + bytes(n - 48)).hex(), 2),
            ('subgroup', q, 2), ('identity', identity(n), 7)]

bad1, bad2 = malformed(48, q1), malformed(96, q2)
factories = []
def factory(name, op, key, proof='', status=0):
    factories.append(dict(name=name, op=op, key=key, proof=proof, status=status))

for i in range(len(v['ic_keys'])):
    factory(f'ic-valid-{i}', 22, v['ic_keys'][i])
    factory(f'eth-valid-{i}', 23, v['eth_keys'][i])
    factory(f'pop-valid-{i}', 24, v['eth_keys'][i], v['eth_proofs'][i])
for name, key, error in bad2:
    factory('ic-' + name, 22, key, status=error)
for name, key, error in bad1:
    factory('eth-' + name, 23, key, status=error)
    factory('pop-key-' + name, 24, key, v['eth_proofs'][0], error)
    for proof_name, proof, proof_error in bad2:
        # Both point decoders precede identity rejection.
        expected = proof_error if error == 7 and proof_error != 7 else error
        factory('pop-order-' + name + '-' + proof_name, 24, key, proof, expected)
for name, proof, error in bad2:
    factory('pop-proof-' + name, 24, v['eth_keys'][0], proof, error)
for i in range(2):
    factory(f'pop-wrong-key-{i}', 24, v['eth_keys'][i], v['eth_proofs'][1-i], 8)

singles = []
for profile, op, bad in [('ic', 25, bad1), ('eth', 26, bad2)]:
    for i in range(2):
        for name, key, message, signature, status, value in [
            ('valid', i, v['messages'][i], v[profile+'_signatures'][i], 0, True),
            ('wrong-key', 1-i, v['messages'][i], v[profile+'_signatures'][i], 0, False),
            ('wrong-message', i, '0062696e61727900', v[profile+'_signatures'][i], 0, False),
        ]:
            singles.append(dict(name=f'{profile}-{name}-{i}', op=op, key=key,
                                message=message, signature=signature, status=status, value=value))
    for name, signature, status in bad:
        singles.append(dict(name=f'{profile}-signature-{name}', op=op, key=0,
                            message=v['messages'][0], signature=signature, status=status, value=False))
    singles.append(dict(name=f'{profile}-negative-key-valid',op=op,key=2,message=v['messages'][0],
                        signature=v[profile+'_signatures'][2],status=0,value=True))

aggregates = []
def aggregate(name, op, keys, messages, signature, status=0, value=True):
    aggregates.append(dict(name=name, op=op, keys=keys, messages=messages,
                           signature=signature, status=status, value=value))
for profile, op, signature, bad in [
    ('ic', 27, v['ic_aggregate'], bad1),
    ('eth', 28, v['eth_aggregate'], bad2),
    ('fast', 29, v['eth_same_message_aggregate'], bad2),
]:
    messages = v['messages'] if op != 29 else [v['messages'][0]] * 2
    aggregate(profile+'-valid', op, [0, 1], messages, signature)
    aggregate(profile+'-wrong-message', op, [0, 1], ['00'] * 2 if op == 29 else [messages[0], '00'], signature, value=False)
    aggregate(profile+'-wrong-key', op, [1, 0] if op != 29 else [0, 0], messages, signature, value=False)
    for name, bad_signature, status in bad:
        aggregate(profile+'-signature-'+name, op, [0, 1], messages, bad_signature, status)
    # Repeated calls and repeated key handles must not leak prior outcomes.
    aggregate(profile+'-valid-again', op, [0, 1], messages, signature)
for count in [2, 15, 16, 17, 127]:
    for index in sorted({0, count // 2, count - 2} - {count - 1}):
        messages = [(bytes(32) + i.to_bytes(2, 'big')).hex() for i in range(count)]
        messages[-1] = messages[index]
        aggregate(f'ic-duplicate-{count}-{index}', 27, [0] * count, messages, '', 9)
aggregate('ic-binary-distinct', 27, [0] * 3, ['00', '0000', '0001'], '', 1)
aggregates += extra['aggregates']

pool = list(dict.fromkeys([''] + [h for group in ['ic_keys','eth_keys','eth_proofs','ic_signatures','eth_signatures','messages'] for h in v[group]] +
                         [h for row in factories for h in [row['key'], row['proof']]] +
                         [h for row in singles for h in [row['message'], row['signature']]] +
                         [h for row in aggregates for h in row['messages'] + [row['signature']]]))
indices = {h: i for i, h in enumerate(pool)}
idx = lambda h: str(indices[h])
(HERE/'blobs.tsv').write_text('\n'.join(pool) + '\n')
(HERE/'factories.tsv').write_text('\n'.join('\t'.join([r['name'],str(r['op']),idx(r['key']),idx(r['proof']),str(r['status'])]) for r in factories) + '\n')
(HERE/'singles.tsv').write_text('\n'.join('\t'.join([r['name'],str(r['op']),str(r['key']),idx(r['message']),idx(r['signature']),str(r['status']),str(int(r['value']))]) for r in singles) + '\n')
(HERE/'aggregates.tsv').write_text('\n'.join('\t'.join([r['name'],str(r['op']),';'.join(map(str,r['keys'])),';'.join(map(idx,r['messages'])),idx(r['signature']),str(r['status']),str(int(r['value']))]) for r in aggregates) + '\n')
(HERE/'key-indices.tsv').write_text('\n'.join('\t'.join(idx(v[group][i]) for group in ['ic_keys','eth_keys','eth_proofs']) for i in range(len(v['ic_keys']))) + '\n')
blob = lambda h: 'b' + idx(h)
literal = lambda h: '"' + ''.join('\\' + h[i:i+2] for i in range(0,len(h),2)) + '"'
errors = {1:'invalidLength',2:'invalidPoint',5:'tooManyItems',6:'emptyBatch',7:'identity',8:'invalidProof',9:'duplicateMessage'}
expected = lambda r: '#err(#'+errors[r['status']]+')' if r['status'] else '#ok('+str(r['value']).lower()+')'
lines = ['import B "mo:fast/BLS12381";', 'import Prim "mo:⛔";', 'module {',
         '  public func ok<T>(r : B.Result<T>) : T { switch r { case (#ok(x)) x; case (#err(_)) Prim.trap("unexpected factory error") } };']
lines += ['  let b'+str(i)+' : Blob = '+literal(h)+';' for i,h in enumerate(pool)]
lines += ['  public func factories() {']
for r in factories:
    name = {22:'prepareICPublicKey',23:'prepareEthereumPublicKey',24:'prepareEthereumPoPKey'}[r['op']]
    args = [blob(r['key'])] + ([blob(r['proof'])] if r['op']==24 else [])
    call = 'B.'+name+'('+','.join(args)+')'
    check = 'case (#ok(_)) {}; case (#err(_)) assert false' if not r['status'] else 'case (#err(e)) assert e == #'+errors[r['status']]+'; case (#ok(_)) assert false'
    lines += ['    // '+r['name'], '    switch ('+call+') { '+check+' };']
lines += ['  };', '  public type Keys = {ic : [B.PreparedICPublicKey]; eth : [B.PreparedEthereumPublicKey]; pop : [B.PreparedEthereumPoPKey]};',
          '  public func keys() : Keys {', '    {',
          '      ic = ['+','.join('ok(B.prepareICPublicKey('+blob(h)+'))' for h in v['ic_keys'])+'];',
          '      eth = ['+','.join('ok(B.prepareEthereumPublicKey('+blob(h)+'))' for h in v['eth_keys'])+'];',
          '      pop = ['+','.join('ok(B.prepareEthereumPoPKey('+blob(k)+','+blob(p)+'))' for k,p in zip(v['eth_keys'],v['eth_proofs']))+'];',
          '    }', '  };', '  public func singles() { let k=keys();']
for r in singles:
    profile = 'ic' if r['op']==25 else 'eth'
    name = 'verifyIC' if r['op']==25 else 'verifyEthereum'
    args = ','+blob(r['message'])+','+blob(r['signature'])
    call = 'B.'+name+'Prepared(k.'+profile+'['+str(r['key'])+']'+args+')'
    direct = 'B.'+name+'('+blob(v[profile+'_keys'][r['key']])+args+')'
    lines += ['    // '+r['name'], '    assert '+call+' == '+expected(r)+'; assert '+call+' == '+direct+';']
lines += ['  };', '  public func aggregates() { aggregatePart(0); aggregatePart(1); aggregatePart(2) };',
          '  public func aggregatePart(part : Nat) { let k=keys();']
for number, r in enumerate(aggregates):
    profile = 'ic' if r['op']==27 else 'pop'
    name = {27:'aggregateVerifyIC',28:'aggregateVerifyEthereum',29:'fastAggregateVerifyEthereum'}[r['op']]
    prepared_keys = '['+','.join('k.'+profile+'['+str(i)+']' for i in r['keys'])+']'
    direct_keys = '['+','.join(blob(v['ic_keys' if r['op']==27 else 'eth_keys'][i]) for i in r['keys'])+']'
    messages = blob(r['messages'][0]) if r['op']==29 else '['+','.join(map(blob,r['messages']))+']'
    call = 'B.'+name+'Prepared('+prepared_keys+','+messages+','+blob(r['signature'])+')'
    direct_args = direct_keys + (','+'['+','.join(blob(v['eth_proofs'][i]) for i in r['keys'])+']' if r['op']!=27 else '')
    direct = 'B.'+name+'('+direct_args+','+messages+','+blob(r['signature'])+')'
    lines += ['    // '+r['name'], '    if (part == '+str(number//24)+') { let result = '+call+'; assert result == '+expected(r)+'; assert result == '+direct+' };']
lines += ['  };', '  public func checkRetained(k : {ic : [B.PreparedICPublicKey]; eth : [B.PreparedEthereumPublicKey]; pop : [B.PreparedEthereumPoPKey]}) {']
for i in range(2):
    args = ','+blob(v['messages'][i])+','
    lines += ['    assert B.verifyICPrepared(k.ic['+str(i)+']'+args+blob(v['ic_signatures'][i])+') == #ok(true);',
              '    assert B.verifyEthereumPrepared(k.eth['+str(i)+']'+args+blob(v['eth_signatures'][i])+') == #ok(true);',
              '    assert B.aggregateVerifyEthereumPrepared([k.pop['+str(i)+']],['+blob(v['messages'][i])+'],'+blob(v['eth_signatures'][i])+') == #ok(true);']
lines += ['  };', '}']
(HERE/'Cases.mo').write_text('\n'.join(lines)+'\n')
(HERE/'public.mo').write_text('import C "Cases";\nimport E "Extra";\nimport Prim "mo:⛔";\nC.factories(); C.singles(); C.aggregates(); E.boundariesAndCallbacks();\nPrim.debugPrint("prepared independent cases passed");\n')
(HERE/'provenance.json').write_text(json.dumps(dict(baseline='f43a81e',factory_cases=len(factories),single_cases=len(singles),aggregate_cases=len(aggregates),inputs={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [SOURCE,RFC,HERE/'extra.json',HERE/'generate-extra.py']},oracle='Independent py_ecc 8.0.0 fixtures, published RFC9380 pre-cofactor subgroup-invalid points, explicit error expectations; direct API is only a second behavior oracle.'),indent=2)+'\n')
print(len(factories), 'factories,', len(singles), 'singles,', len(aggregates), 'aggregates')
