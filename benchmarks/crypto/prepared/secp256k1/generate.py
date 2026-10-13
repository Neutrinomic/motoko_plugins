#!/usr/bin/env python3
"""Matched prepared Secp fixtures using retained independent signature answers."""
import argparse, csv, importlib.util, json
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
p = argparse.ArgumentParser()
p.add_argument('--common', type=Path, default=HERE.parent / 'common.py')
p.add_argument('--screen', action='store_true')
a = p.parse_args()
spec = importlib.util.spec_from_file_location('prepared_common', a.common)
common = importlib.util.module_from_spec(spec); spec.loader.exec_module(common)
vectors = ROOT / 'plugins/secp256k1/tests/vectors'
ecdsa = next(csv.DictReader((vectors/'ecdsa-rfc6979.csv').open()))
schnorr = next(csv.DictReader((vectors/'bip340.csv').open()))
fixture = {'ecdsa-rfc6979-key1-sample': dict(ecdsa,
    source='plugins/secp256k1/tests/vectors/ecdsa-rfc6979.csv',
    oracle='python-ecdsa 0.19.2; retained independent round3 oracle'),
    'bip340-0': dict(schnorr, source='https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv')}
(HERE/'fixtures.json').write_text(json.dumps(fixture, indent=2)+'\n')
profiles = [
    ('ecdsa-verify', 'ECDSA-SHA256', 'verify', 'ecdsa-rfc6979-key1-sample', ecdsa['public'], ecdsa['digest'], ecdsa['signature'], '',
     'PreparedPublicKey', 'preparePublicKey', 'verifyPrehash', 'verifyPrehashPrepared', '01', 512),
    ('schnorr-verify', 'BIP340', 'verify', 'bip340-0', schnorr['public key'], schnorr['message'], schnorr['signature'], '',
     'PreparedSchnorrPublicKey', 'prepareSchnorrPublicKey', 'schnorrVerify', 'schnorrVerifyPrepared', '01', 512),
    ('schnorr-sign', 'BIP340', 'sign', 'bip340-0', schnorr['secret key'], schnorr['message'], '', schnorr['aux_rand'],
     'PreparedSchnorrSecretKey', 'prepareSchnorrSecretKey', 'schnorrSign', 'schnorrSignPrepared', schnorr['signature'].lower(), 64),
]
cases=[]
for label, profile, operation, fixture_id, raw, message, signature, aux, keytype, factory, direct, prepared, expected, payload in profiles:
  for mode, reuse in [('direct',1),('prepare',1),('prepared',1)] + ([] if a.screen else [('cold',1)] + [(mode,n) for n in [2,10,100] for mode in ['direct','prepared','cold']]):
    name=f'secp256k1-{label}-{mode}-n{reuse}'
    callarg=common.blob(aux if operation=='sign' else signature)
    messagearg=common.blob(message)
    rawarg=common.blob(raw)
    declarations=f'''transient var key : ?Curve.{keytype} = null;
  func unwrap<T>(value : Curve.Result<T>) : T {{ switch value {{ case (#ok x) x; case (#err _) {{ assert false; loop {{}} }} }} }};
  func preparedKey() : Curve.{keytype} {{ switch key {{ case (?x) x; case null {{ assert false; loop {{}} }} }} }};'''
    configure=f'key := ?unwrap(Curve.{factory}({rawarg}));' if mode=='prepared' else ''
    call=f'Curve.{direct}({rawarg}, {messagearg}, {callarg})' if mode=='direct' else f'Curve.{prepared}(preparedKey(), {messagearg}, {callarg})'
    convert=lambda expression: f'unwrap({expression})' if operation=='sign' else f'(if (unwrap({expression})) "\\01" else "\\00")'
    if mode=='prepare':
      measured=f'key := ?unwrap(Curve.{factory}({rawarg}));'
      output=convert(call)
    else:
      measured=f'result := {convert(call)};'
      if reuse>1: measured=f'var remaining = {reuse}; while (remaining > 0) {{ {measured} remaining -= 1; }};'
      if mode=='cold': measured=f'key := ?unwrap(Curve.{factory}({rawarg})); ' + measured
      output='result'
    source=common.actor('import Curve "mo:fast/Secp256k1";', declarations, configure, measured, output_expr=output, memory_metrics=True)
    relative=f'prepared/secp256k1/cases/{name}/main.mo'
    target=ROOT/'benchmarks/crypto'/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source)
    cases.append({'name':name,'implementation':'native','family':'secp256k1','plugins':['secp256k1'],
      'source':relative,'expected_hex':expected,'memory_metrics':True,
      'prepared':{'scheme':'secp256k1','profile':profile,'operation':operation,'fixture':fixture_id,
        'fixture_source':'prepared/secp256k1/fixtures.json','comparison_group':f'secp256k1-{label}-{fixture_id}-payload{payload}',
        'mode':mode,'reuse':reuse,'payload_bytes':0 if mode=='direct' else payload}})
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} cases; public payload {512} B')
