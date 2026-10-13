#!/usr/bin/env python3
"""Generate independent public-API audit cases; no plugin code is imported.

Published Wycheproof expectations are kept, with this API's separately documented
strict encoding errors. Synthetic mixed-order cases distinguish the uncofactored
equation from cofactor-only verification and prime-subgroup-only validation.
"""
import hashlib
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, -1, P) % P
I = pow(2, (P - 1) // 4, P)
IDENTITY = (0, 1)
BASE = (15112221349535400772501151409588531511454012693041857206046113283949847762202,
        46316835694926478169428394003475163141307993866256225615783033603165251855960)


def add(a, b):
    """Affine Edwards addition, independent of runtime/reference projective code."""
    x, y = a
    u, v = b
    cross = D * x * u * y * v % P
    return ((x * v + u * y) * pow(1 + cross, -1, P) % P,
            (y * v + x * u) * pow(1 - cross, -1, P) % P)


def mul(n, point):
    out = IDENTITY
    while n:
        if n & 1:
            out = add(out, point)
        point = add(point, point)
        n >>= 1
    return out


def encode(point):
    x, y = point
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def decode(raw):
    if len(raw) != 32:
        return None
    encoded = int.from_bytes(raw, "little")
    sign, y = encoded >> 255, encoded % 2**255
    if y >= P:
        return None
    xx = (y * y - 1) * pow(D * y * y + 1, -1, P) % P
    x = pow(xx, (P + 3) // 8, P)
    if x * x % P != xx:
        x = x * I % P
    if x * x % P != xx or x == 0 and sign:
        return None
    return (x if x % 2 == sign else -x % P, y)


def strict_point(raw):
    point = decode(raw)
    return point is not None and mul(8, point) != IDENTITY


def classify(key, signature, valid):
    if not strict_point(key):
        return "invalidPublicKey"
    if (len(signature) != 64 or not strict_point(signature[:32])
            or int.from_bytes(signature[32:], "little") >= L):
        return "invalidSignature"
    return "true" if valid else "false"


def blob(raw):
    return '"' + ''.join(f'\\{byte:02x}' for byte in raw) + '"'


def main():
    cases = []

    def case(name, key, message, signature, valid, category):
        expected = classify(key, signature, valid)
        if valid:
            assert expected == "true", name
        cases.append(dict(name=name, publicKey=key.hex(), message=message.hex(),
                          signature=signature.hex(), expected=expected, category=category))

    corpus = json.loads((HERE / 'vectors/ed25519_test.json').read_text())
    for group in corpus['testGroups']:
        key = bytes.fromhex(group['publicKey']['pk'])
        for vector in group['tests']:
            case(f"wycheproof-{vector['tcId']}", key, bytes.fromhex(vector['msg']),
                 bytes.fromhex(vector['sig']), vector['result'] == 'valid', 'wycheproof')
    assert len(cases) == corpus['numberOfTests']

    rfc = json.loads((ROOT / 'benchmarks/crypto/round3/ed25519/fixtures/rfc8032.json').read_text())['vectors'][0]
    key, message, signature = (bytes.fromhex(rfc[field]) for field in ('publicKey', 'message', 'signature'))

    # Recover one order-8 point independently and exercise every torsion point.
    torsion = None
    for y in range(2, 100):
        point = decode(y.to_bytes(32, 'little'))
        if point is not None:
            candidate = mul(L, point)
            if mul(8, candidate) == IDENTITY and mul(4, candidate) != IDENTITY:
                torsion = candidate
                break
    assert torsion is not None
    for n in range(8):
        raw = encode(mul(n, torsion))
        case(f'small-order-key-{n}', raw, message, signature, False, 'encoding')
        case(f'small-order-r-{n}', key, message, raw + signature[32:], False, 'encoding')
    for y in range(P, 2**255):
        for sign in range(2):
            raw = (y | sign << 255).to_bytes(32, 'little')
            case(f'noncanonical-key-{y-P}-{sign}', raw, message, signature, False, 'encoding')
            case(f'noncanonical-r-{y-P}-{sign}', key, message, raw + signature[32:], False, 'encoding')
    for y in (1, P - 1):
        raw = (y | 1 << 255).to_bytes(32, 'little')
        case(f'zero-x-sign-key-{y}', raw, message, signature, False, 'encoding')
        case(f'zero-x-sign-r-{y}', key, message, raw + signature[32:], False, 'encoding')
    off_curve = next(y.to_bytes(32, 'little') for y in range(2, 100)
                     if decode(y.to_bytes(32, 'little')) is None)
    case('off-curve-key', off_curve, message, signature, False, 'encoding')
    case('off-curve-r', key, message, off_curve + signature[32:], False, 'encoding')
    for scalar in (0, L-1, L, L+1, 2*L, 2**256-1):
        case(f'scalar-{scalar}', key, message, signature[:32] + scalar.to_bytes(32, 'little'), False, 'scalar')
    scalar = int.from_bytes(signature[32:], 'little') + L
    case('scalar-malleation-add-L', key, message, signature[:32] + scalar.to_bytes(32, 'little'), False, 'scalar')
    for length in (0, 1, 31, 33, 63, 64, 65, 128, 4096):
        case(f'key-length-{length}', bytes(length), message, signature, False, 'length')
    for length in (0, 1, 31, 32, 63, 65, 128, 4096):
        case(f'sig-length-{length}', key, message, bytes(length), False, 'length')
    case('bad-key-before-bad-sig', b'', message, b'', False, 'precedence')

    # A=7B+T, R=11B+uT, S=(11+7k) mod L. Their cofactored equation
    # always holds. The uncofactored equation holds iff u+k == 0 mod 8.
    mixed_key = encode(add(mul(7, BASE), torsion))
    assert strict_point(mixed_key) and mul(L, decode(mixed_key)) != IDENTITY
    for u in range(8):
        r_bytes = encode(add(mul(11, BASE), mul(u, torsion)))
        for want_valid in (True, False):
            for counter in range(1000):
                msg = f'mixed-order-{u}-{want_valid}-{counter}'.encode()
                challenge = int.from_bytes(hashlib.sha512(r_bytes + mixed_key + msg).digest(), 'little') % L
                if ((u + challenge) % 8 == 0) == want_valid:
                    break
            else:
                raise AssertionError('failed to construct mixed-order case')
            sig = r_bytes + ((11 + 7 * challenge) % L).to_bytes(32, 'little')
            assert (mul(int.from_bytes(sig[32:], 'little'), BASE)
                    == add(decode(r_bytes), mul(challenge, decode(mixed_key)))) == want_valid
            case(f'mixed-order-{u}-{want_valid}', mixed_key, msg, sig, want_valid, 'mixed-order')

    payload = {'description': __doc__, 'cases': cases}
    (HERE / 'vectors/cases.json').write_text(json.dumps(payload, indent=2) + '\n')
    run = HERE / 'run'
    run.mkdir(exist_ok=True)
    prefix = ('//MOC-FLAG --plugin ../../../../../dist/ed25519 --package fast ../../../../../packages/fast/src --sanity-checks\n'
              'import Ed "mo:fast/Ed25519";\n')
    for group, selected in [('wycheproof', cases[:151]), ('adversarial', cases[151:])]:
        text = prefix
        for row in selected:
            expected = '#ok(' + row['expected'] + ')' if row['expected'] in ('true', 'false') else '#err(#' + row['expected'] + ')'
            text += (f"// {row['name']}\nassert Ed.verify({blob(bytes.fromhex(row['publicKey']))},"
                     f"{blob(bytes.fromhex(row['message']))},{blob(bytes.fromhex(row['signature']))}) == {expected};\n")
            if row['category'] == 'mixed-order':
                text += f"assert Ed.validatePublicKey({blob(bytes.fromhex(row['publicKey']))}) == #ok(true);\n"
        # One known-good call after adversarial errors checks no retained failure state.
        text += f'assert Ed.verify({blob(key)},{blob(message)},{blob(signature)}) == #ok(true);\n'
        (run / f'{group}.mo').write_text(text)
    # Node's built-in OpenSSL signs independently; fixed test seed is public.
    openssl = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', '''
import {createPrivateKey,createPublicKey,sign,verify} from 'node:crypto';
const seed=Buffer.alloc(32,41);
const sk=createPrivateKey({format:'der',type:'pkcs8',key:Buffer.concat([
 Buffer.from('302e020100300506032b657004220420','hex'),seed])});
const pk=createPublicKey(sk), key=pk.export({format:'der',type:'spki'}).subarray(-32);
const vectors=[seed,key,Buffer.from(Array.from({length:65536},(_,i)=>i%251))].map((msg,index)=>{
 const signature=sign(null,msg,sk);
 if(!verify(null,msg,pk,signature))throw Error('OpenSSL self-check failed');
 return {name:['seed-alias','key-alias','64KiB'][index],length:msg.length,signature:signature.toString('hex')};
});
console.log(JSON.stringify({source:'Node built-in OpenSSL',node:process.version,openssl:process.versions.openssl,
 seed:seed.toString('hex'),publicKey:key.toString('hex'),vectors}));
'''], text=True))
    (HERE / 'vectors/openssl-extra.json').write_text(json.dumps(openssl, indent=2) + '\n')
    seed = bytes.fromhex(openssl['seed'])
    key = bytes.fromhex(openssl['publicKey'])
    text = prefix + 'import Prim "mo:⛔";\n'
    text += f'let seed : Blob = {blob(seed)};\nlet key : Blob = {blob(key)};\n'
    text += 'assert Ed.keyPairFromSeed(seed) == #ok({secretKey=seed;publicKey=key});\n'
    text += 'let large = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(65_536,func(i) {Prim.natToNat8(i % 251)}));\n'
    for name, vector in zip(['seed', 'key', 'large'], openssl['vectors']):
        expected = blob(bytes.fromhex(vector['signature']))
        text += f'let {name}Signature : Blob = {expected};\n'
        text += f'assert Ed.sign(seed,{name}) == #ok({name}Signature);\n'
        text += f'assert Ed.verify(key,{name},{name}Signature) == #ok(true);\n'
    text += 'assert Ed.sign("",large) == #err(#invalidSecretKey);\n'
    text += 'assert Ed.verify(key,large,"") == #err(#invalidSignature);\n'
    text += 'assert Ed.verify(key,large,largeSignature) == #ok(true);\n'
    text += f'assert seed == {blob(seed)};\nassert key == {blob(key)};\n'
    text += 'let retained = [seedSignature,keySignature,largeSignature];\n'
    text += 'for (sig in retained.values()) { assert sig.size() == 64 };\n'
    text += 'assert Ed.verify(key,seed,retained[0]) == #ok(true);\n'
    (run / 'large-aliasing.mo').write_text(text)
    summary = {kind: sum(row['category'] == kind for row in cases) for kind in sorted({row['category'] for row in cases})}
    print(json.dumps({'cases': len(cases), 'categories': summary}))


if __name__ == '__main__':
    main()
