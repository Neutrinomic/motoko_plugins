#!/usr/bin/env python3
"""Independent prefix-boundary and mixed-order production API fixtures.

No production implementation is imported. Reuse the previous affine oracle
instead of duplicating its curve arithmetic; signing answers come from OpenSSL.
"""
import hashlib
import importlib.util
import json
import math
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ORACLE = ROOT / 'tests/crypto-audit/round3/ed25519/generate.py'
spec = importlib.util.spec_from_file_location('affine_oracle', ORACLE)
curve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(curve)


def main():
    # Both SHA-512 padding (112 mod 128) and complete-block transitions, with
    # the 32-byte nonce prefix and the 64-byte challenge prefix included.
    lengths = [base + delta for base in (48, 64, 80, 96, 176, 192, 208, 224)
               for delta in (-1, 0, 1)]
    requested = [dict(name=f'prefix-boundary-{n}',
                      seed=hashlib.sha256(f'ed25519-round5-{n}'.encode()).hexdigest(),
                      message=bytes((i * 73 + n) % 256 for i in range(n)).hex())
                 for n in lengths]
    # RFC 8032 sections 7.2 (foo) and 7.3 (abc). These signatures are valid
    # in their named domains, but not under this plugin's pure Ed25519 API.
    modes = [dict(name='rfc8032-ctx-foo',
        seed='0305334e381af78f141cb666f6199f57bc3495335a256a95bd2a55bf546663f6',
        publicKey='dfc9425e4f968f7f0c29f0259cf5f9aed6851c2bb4ad8bfb860cfee0ab248292',
        message='f726936d19c800494e3fdaff20b276a8',
        signature='55a4cc2f70a54e04288c5f4cd1e45a7bb520b36292911876cada7323198dd87a'
                  '8b36950b95130022907a7fb7c4e9b2d5f6cca685a587b4b21f4b888e4e7edb0d'),
        dict(name='rfc8032-ph-abc',
        seed='833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42',
        publicKey='ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf',
        message='616263',
        signature='98a70222f0b8121aa9d30f813d683f809e462b469c7ff87639499bb94e6dae41'
                  '31f85042463c2a355a2003d062adf5aaa10b8c61e636062aaad11c2a26083406')]
    requested += [dict(name=row['name'] + '-pure', seed=row['seed'], message=row['message'])
                  for row in modes]
    openssl = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', '''
import {readFileSync} from 'node:fs';
import {createPrivateKey,createPublicKey,sign,verify} from 'node:crypto';
const rows=JSON.parse(readFileSync(0,'utf8'));
const vectors=rows.map(row=>{
 const key=createPrivateKey({format:'der',type:'pkcs8',key:Buffer.concat([
  Buffer.from('302e020100300506032b657004220420','hex'),Buffer.from(row.seed,'hex')])});
 const pk=createPublicKey(key), message=Buffer.from(row.message,'hex');
 const signature=sign(null,message,key);
 if(!verify(null,message,pk,signature))throw Error('OpenSSL self-check');
 return {...row,publicKey:pk.export({format:'der',type:'spki'}).subarray(-32).toString('hex'),
  signature:signature.toString('hex')};
});
console.log(JSON.stringify({node:process.version,openssl:process.versions.openssl,vectors}));
'''], input=json.dumps(requested), text=True))
    cases = []

    def case(name, key, message, signature, valid):
        assert curve.classify(key, signature, valid) == ('true' if valid else 'false')
        k = int.from_bytes(hashlib.sha512(signature[:32] + key + message).digest(), 'little') % curve.L
        assert (curve.mul(int.from_bytes(signature[32:], 'little'), curve.BASE) ==
                curve.add(curve.decode(signature[:32]), curve.mul(k, curve.decode(key)))) == valid
        cases.append(dict(name=name, publicKey=key.hex(), message=message.hex(),
                          signature=signature.hex(), expected=valid))

    torsion = next(curve.mul(curve.L, point) for y in range(2, 100)
                   if (point := curve.decode(y.to_bytes(32, 'little'))) is not None
                   and curve.mul(4, curve.mul(curve.L, point)) != curve.IDENTITY)
    assert curve.mul(8, torsion) == curve.IDENTITY
    for t in (2, 4, 6, 7):
        a = curve.add(curve.mul(7, curve.BASE), curve.mul(t, torsion))
        key = curve.encode(a)
        assert curve.mul(curve.L, a) != curve.IDENTITY
        for u in range(8):
            r = curve.encode(curve.add(curve.mul(11, curve.BASE), curve.mul(u, torsion)))
            for valid in (True, False):
                if valid and u % math.gcd(t, 8):
                    continue
                for counter in range(256):
                    message = f'round5-t{t}-u{u}-{valid}-{counter}'.encode()
                    k = int.from_bytes(hashlib.sha512(r + key + message).digest(), 'little') % curve.L
                    if ((u + t * k) % 8 == 0) == valid:
                        break
                else:
                    raise AssertionError('no chosen residue')
                signature = r + ((11 + 7 * k) % curve.L).to_bytes(32, 'little')
                case(f'mixed-t{t}-u{u}-{valid}', key, message, signature, valid)
                # The weak cofactored equation holds for every generated row.
                assert curve.mul(8 * int.from_bytes(signature[32:], 'little'), curve.BASE) == curve.mul(
                    8, curve.add(curve.decode(r), curve.mul(k, a)))
                if valid:
                    opposite = bytearray(key)
                    opposite[31] ^= 128
                    case(f'opposite-key-t{t}-u{u}', bytes(opposite), message, signature, False)
    for row, pure in zip(modes, openssl['vectors'][-2:]):
        assert row['publicKey'] == pure['publicKey']
        key, message, signature = (bytes.fromhex(row[k]) for k in ('publicKey', 'message', 'signature'))
        # Check the RFC signature in its intended domain as well, so a typo
        # cannot turn mode separation into a vacuous invalid-signature test.
        ph = int('ph' in row['name'])
        context = b'' if ph else b'foo'
        dom2 = b'SigEd25519 no Ed25519 collisions' + bytes([ph, len(context)]) + context
        actual = hashlib.sha512(message).digest() if ph else message
        k = int.from_bytes(hashlib.sha512(dom2 + signature[:32] + key + actual).digest(), 'little') % curve.L
        assert curve.mul(int.from_bytes(signature[32:], 'little'), curve.BASE) == curve.add(
            curve.decode(signature[:32]), curve.mul(k, curve.decode(key)))
        case(row['name'], key, message, signature, False)
        alternate = b'foo' + message if 'ctx' in row['name'] else hashlib.sha512(message).digest()
        case(row['name'] + '-prefix-or-digest', key, alternate, signature, False)
    unrelated = bytes.fromhex(openssl['vectors'][0]['publicKey'])
    for row in cases:
        message, signature = (bytes.fromhex(row[k]) for k in ('message', 'signature'))
        k = int.from_bytes(hashlib.sha512(signature[:32] + unrelated + message).digest(), 'little') % curve.L
        assert curve.mul(int.from_bytes(signature[32:], 'little'), curve.BASE) != curve.add(
            curve.decode(signature[:32]), curve.mul(k, curve.decode(unrelated)))
    payload = dict(source='Node/OpenSSL pure Ed25519 and independent affine verification oracle',
                   rfc='https://www.rfc-editor.org/rfc/rfc8032.html#section-7.2',
                   affine_oracle_sha256=hashlib.sha256(ORACLE.read_bytes()).hexdigest(),
                   node=openssl['node'], openssl=openssl['openssl'],
                   signing=openssl['vectors'], verification=cases)
    (HERE / 'vectors.json').write_text(json.dumps(payload, indent=2) + '\n')
    blob = lambda value: curve.blob(bytes.fromhex(value))
    text = '// Generated by generate.py; independent expected bytes are in vectors.json.\nmodule {\n'
    text += '  public let signing : [{seed : Blob; publicKey : Blob; message : Blob; signature : Blob}] = [\n'
    for row in payload['signing']:
        text += '    { ' + '; '.join(f'{key} = {blob(row[key])}' for key in
                                     ('seed', 'publicKey', 'message', 'signature')) + ' },\n'
    text += '  ];\n  public let verification : [{publicKey : Blob; message : Blob; signature : Blob; expected : Bool}] = [\n'
    for row in cases:
        text += '    { ' + '; '.join(f'{key} = {blob(row[key])}' for key in
                                     ('publicKey', 'message', 'signature'))
        text += '; expected = ' + str(row['expected']).lower() + ' },\n'
    text += '  ];\n}\n'
    (HERE / 'Vectors.mo').write_text(text)
    print(f'{len(payload["signing"])} signing vectors; {len(cases)} verification cases')


if __name__ == '__main__':
    main()
