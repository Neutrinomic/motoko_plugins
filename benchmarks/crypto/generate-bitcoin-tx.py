#!/usr/bin/env python3
"""Bitcoin transaction workloads with independent hashlib/wire-format oracles.

No transaction or digest is obtained from either benchmark implementation.
The Taproot comparison is deliberately restricted to equal spent-output scripts:
bitcoin 0.2.1's API accepts only one script for all inputs. BIP143 has no Mops
counterpart and is compared only between native one-shot and prepared APIs.
"""
import hashlib
import json
import runpy

from common import HERE, actor, blob, save_case


SCRIPT = bytes.fromhex('76a914') + hashlib.sha256(b'tx-benchmark-owner').digest()[:20] + bytes.fromhex('88ac')
TAP_SCRIPT = bytes.fromhex('5120') + hashlib.sha256(b'tx-benchmark-taproot-key').digest()
VERSION, LOCKTIME = 2, 850_000


def sha(value):
    return hashlib.sha256(value).digest()


def double_sha(value):
    return sha(sha(value))


def le(value, width):
    return value.to_bytes(width, 'little')


def compact(value):
    if value < 253:
        return bytes([value])
    if value <= 0xffff:
        return b'\xfd' + le(value, 2)
    if value <= 0xffffffff:
        return b'\xfe' + le(value, 4)
    return b'\xff' + le(value, 8)


def field(value):
    return compact(len(value)) + value


def fixtures(count):
    inputs = [dict(txid=sha(b'tx-benchmark-input-' + le(i, 4)), index=i % 3,
                   sequence=0xfffffffd-i, amount=100_000+i) for i in range(count)]
    outputs = [(count * 90_000, bytes.fromhex('0014') + sha(b'tx-benchmark-recipient')[:20]),
               (8_000, TAP_SCRIPT)]
    return inputs, outputs


def outpoint(value):
    return value['txid'] + le(value['index'], 4)


def output(value):
    return le(value[0], 8) + field(value[1])


def serialize(inputs, outputs, signing_index=None):
    return (le(VERSION, 4) + compact(len(inputs)) + b''.join(
        outpoint(value) + field(SCRIPT if signing_index == i else b'') + le(value['sequence'], 4)
        for i, value in enumerate(inputs)) + compact(len(outputs)) +
        b''.join(map(output, outputs)) + le(LOCKTIME, 4))


def legacy(inputs, outputs, index):
    return double_sha(serialize(inputs, outputs, index) + le(1, 4))


def segwit_v0(inputs, outputs, index):
    item = inputs[index]
    return double_sha(le(VERSION, 4) + double_sha(b''.join(map(outpoint, inputs))) +
                      double_sha(b''.join(le(i['sequence'], 4) for i in inputs)) +
                      outpoint(item) + field(SCRIPT) + le(item['amount'], 8) + le(item['sequence'], 4) +
                      double_sha(b''.join(map(output, outputs))) + le(LOCKTIME, 4) + le(1, 4))


def taproot(inputs, outputs, index):
    tag = sha(b'TapSighash')
    return sha(tag + tag + b'\x00\x00' + le(VERSION, 4) + le(LOCKTIME, 4) +
               sha(b''.join(map(outpoint, inputs))) +
               sha(b''.join(le(i['amount'], 8) for i in inputs)) +
               sha(field(TAP_SCRIPT) * len(inputs)) +
               sha(b''.join(le(i['sequence'], 4) for i in inputs)) +
               sha(b''.join(map(output, outputs))) + b'\x00' + le(index, 4))


NATIVE_IMPORTS = '''import T "mo:fast/Bitcoin/Transaction";
import A "mo:core/Array";
import B "mo:core/Blob";'''
BASELINE_IMPORTS = '''import T "mo:bitcoin/bitcoin/Transaction";
import S "mo:bitcoin/bitcoin/Script";
import A "mo:core/Array";
import B "mo:core/Blob";
import N32 "mo:core/Nat32";'''


def native_declarations(inputs, outputs):
    ins = ',\n'.join('{previousTxid = ' + blob(i['txid']) + '; previousIndex = ' + str(i['index']) +
                     '; scriptSig = ""; sequence = ' + str(i['sequence']) + '; witness = []}' for i in inputs)
    outs = ',\n'.join('{value = ' + str(value) + '; scriptPubKey = ' + blob(script) + '}' for value, script in outputs)
    prevouts = ',\n'.join('{value = ' + str(i['amount']) + '; scriptPubKey = ' + blob(TAP_SCRIPT) + '}' for i in inputs)
    return f'''transient let tx : T.Tx = {{version = {VERSION}; inputs = [{ins}]; outputs = [{outs}]; lockTime = {LOCKTIME}}};
transient let prevouts : [T.Output] = [{prevouts}];
transient let scriptCode : Blob = {blob(SCRIPT)};'''


def baseline_declarations(inputs, outputs):
    raw = blob(serialize(inputs, outputs))
    amounts = ', '.join(str(i['amount']) for i in inputs)
    declarations = f'''transient var tx : ?T.Transaction = null;
transient var script : S.Script = [];
transient var tapScript : S.Script = [];
transient let amounts : [Nat64] = [{amounts}];'''
    configure = f'''let #ok(value) = T.fromBytes(({raw} : Blob).values()) else Prim.trap("baseline transaction"); tx := ?value;
let #ok(legacyScript) = S.fromBytes(({blob(SCRIPT)} : Blob).values(), false) else Prim.trap("legacy script"); script := legacyScript;
let #ok(tap) = S.fromBytes(({blob(TAP_SCRIPT)} : Blob).values(), false) else Prim.trap("Taproot script"); tapScript := tap;'''
    return declarations, configure


def emit(name, implementation, comparison, expected, source, count, notes, native=True, kind='paired'):
    spec = dict(name=name, family='bitcoin-transaction', implementation=implementation, comparison=comparison,
                plugins=['sha256'] if native else [], expected_hex=expected.hex(), notes=notes,
                benchmark_kind=kind, operations_per_sample=count, dependency_lock='dependencies/mops.lock',
                fixture_provenance='generate-bitcoin-tx.py independent Python Bitcoin wire encoding and hashlib; BIP143 SIGHASH_ALL and BIP341 key-path SIGHASH_DEFAULT equations.')
    return save_case(spec, source, 'bitcoin-tx-cases')


def composed_verification():
    # Reuse the independent affine arithmetic oracle, never plugin/baseline output.
    affine = runpy.run_path(str(HERE / 'generate-curves.py'))
    curve = affine['CURVES']['secp256k1']
    secret, nonce = affine['SECRET'], affine['NONCE']
    add = lambda a, b: affine['ec_add'](a, b, curve['p'])
    multiply = lambda scalar: affine['multiply'](curve['g'], scalar, add)
    public = multiply(secret)
    inputs, outputs = fixtures(1)
    digest = legacy(inputs, outputs, 0)
    r = multiply(nonce)[0] % curve['n']
    s = ((int.from_bytes(digest, 'big') + r*secret) * pow(nonce, -1, curve['n'])) % curve['n']
    s = min(s, curve['n'] - s)
    inverse = pow(s, -1, curve['n'])
    check = add(multiply(int.from_bytes(digest, 'big')*inverse % curve['n']),
                affine['multiply'](public, r*inverse % curve['n'], add))
    assert check[0] % curve['n'] == r
    encoded = bytes([2 | (public[1] & 1)]) + public[0].to_bytes(32, 'big')
    signature = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    name = 'bitcoin-legacy-sighash-verify-1-input'
    notes = ('Composed transaction workflow: legacy SIGHASH_ALL then ECDSA verify of the exact digest. '
             'Native uses SHA256 and secp256k1 plugins; baseline uses bitcoin 0.2.1 transaction hashing '
             'and ecdsa 8.0.1 verifyHashed because bitcoin Ecdsa.verify would add an extra prehash. '
             'Full-width independent Python key/signature fixture. Baseline curve/key/signature setup '
             'outside measurement; native compressed-key/signature decoding inside measurement.')
    native = native_declarations(inputs, outputs)
    native += f'\ntransient let publicKey : Blob = {blob(encoded)}; transient let signature : Blob = {blob(signature)};'
    operation = ('let ?digest = T.signatureHashLegacy(tx, 0, scriptCode, 1) else Prim.trap("sighash"); '
                 'let #ok(valid) = C.verifyPrehash(publicKey, digest, signature) else Prim.trap("verify"); result := valid;')
    source = actor(NATIVE_IMPORTS + '\nimport C "mo:fast/Secp256k1";', native, '', operation,
                   'if (result) "\\01" else "\\00"', 'Bool', 'false')
    case = emit(name, 'native', name, b'\x01', source, 1, notes)
    case['plugins'] = ['sha256', 'secp256k1']
    case['fixture_provenance'] += ' ECDSA fixture generated and algebraically verified with generate-curves.py independent affine Python.'
    yield case
    baseline, configure = baseline_declarations(inputs, outputs)
    baseline += f'''\ntransient let curve = E.Curve(#secp256k1);
transient let publicKey = E.PublicKey({public[0]}, {public[1]}, curve);
transient let signature = E.Signature({r}, {s}, curve);'''
    operation = ('let ?value = tx else Prim.trap("configure first"); '
                 'let digest = value.createP2pkhSignatureHash(script, 0, 1); '
                 'result := publicKey.verifyHashed(digest.values(), signature);')
    source = actor(BASELINE_IMPORTS + '\nimport E "mo:ecdsa";', baseline, configure, operation,
                   'if (result) "\\01" else "\\00"', 'Bool', 'false')
    case = emit(name, 'mops-bitcoin', name, b'\x01', source, 1, notes, False)
    case['fixture_provenance'] += ' ECDSA fixture generated and algebraically verified with generate-curves.py independent affine Python.'
    yield case


def main():
    cases = []
    for count in (1, 10, 100):
        inputs, outputs = fixtures(count)
        native = native_declarations(inputs, outputs)
        baseline, configure = baseline_declarations(inputs, outputs)
        name = f'bitcoin-serialize-{count}-inputs'
        notes = 'Legacy wire serialization, empty scriptSig and witnesses, two outputs. Inputs constructed or parsed before measurement. Baseline [Nat8] to Blob output conversion is outside measurement.'
        source = actor(NATIVE_IMPORTS, native, '', 'let ?value = T.serialize(tx, false) else Prim.trap("native serialize"); result := value;')
        cases.append(emit(name, 'native', name, serialize(inputs, outputs), source, 1, notes))
        source = actor(BASELINE_IMPORTS, baseline, configure,
                       'let ?value = tx else Prim.trap("configure first"); result := value.toBytesIgnoringWitness();',
                       'B.fromArray(result)', '[Nat8]', '[]')
        cases.append(emit(name, 'mops-bitcoin', name, serialize(inputs, outputs), source, 1, notes, False))

        for scheme, oracle, native_call, baseline_call in (
            ('legacy-all', legacy, 'T.signatureHashLegacy(tx, i, scriptCode, 1)', 'value.createP2pkhSignatureHash(script, N32.fromNat(i), 1)'),
            ('taproot-default', taproot, 'T.signatureHashTaproot(tx, i, prevouts, 0, null, null)', 'value.createTaprootKeySpendSignatureHash(amounts, tapScript, N32.fromNat(i))'),
        ):
            name = f'bitcoin-{scheme}-sign-all-{count}-inputs'
            expected = b''.join(oracle(inputs, outputs, i) for i in range(count))
            notes = f'Compute all {count} input sighashes, in input order, including per-call validation and transaction-wide hashing. Output concatenation outside measurement. '
            notes += ('Legacy SIGHASH_ALL, no witnesses. Baseline mutates its input scripts; native preserves the transaction.' if scheme == 'legacy-all' else
                      'BIP341 key-path DEFAULT, no annex. All spent scripts are the same P2TR script to match the restricted bitcoin 0.2.1 API; each amount and outpoint differs.')
            operation = f'result := A.tabulate<Blob>({count}, func(i) {{ let ?value = {native_call} else Prim.trap("native sighash"); value }});'
            source = actor(NATIVE_IMPORTS, native, '', operation,
                           'B.fromArray(A.flatten<Nat8>(A.map<Blob, [Nat8]>(result, B.toArray)))', '[Blob]', '[]')
            cases.append(emit(name, 'native', name, expected, source, count, notes))
            operation = f'let ?value = tx else Prim.trap("configure first"); result := A.tabulate<[Nat8]>({count}, func(i) {{ {baseline_call} }});'
            source = actor(BASELINE_IMPORTS, baseline, configure, operation, 'B.fromArray(A.flatten<Nat8>(result))', '[[Nat8]]', '[]')
            cases.append(emit(name, 'mops-bitcoin', name, expected, source, count, notes, False))

        for scheme, oracle, prepare, direct_call, prepared_call in (
            ('bip143-all', segwit_v0, 'T.prepareSegwitV0(tx)', 'T.signatureHashSegwitV0(tx, i, scriptCode, prevouts[i].value, 1)', 'prepared.signatureHash(i, scriptCode, prevouts[i].value, 1)'),
            ('taproot-default', taproot, 'T.prepareTaproot(tx, prevouts)', 'T.signatureHashTaproot(tx, i, prevouts, 0, null, null)', 'prepared.signatureHash(i, 0, null, null)'),
        ):
            name = f'bitcoin-{scheme}-cache-{count}-inputs'
            expected = b''.join(oracle(inputs, outputs, i) for i in range(count))
            notes = f'Native API comparison: compute all {count} input sighashes. Prepared case includes hasher creation and the first lazy transaction-wide hashes inside measurement. No warm cache from configure. '
            notes += ('bitcoin 0.2.1 has no BIP143 implementation; this is not a Mops comparison.' if scheme == 'bip143-all' else
                      'All prevout amounts and outpoints differ; spent scripts are equal for comparability with the separate Mops workload.')
            for implementation, call in (('native', direct_call), ('native-prepared', prepared_call)):
                operation = f'let ?prepared = {prepare} else Prim.trap("prepare"); ' if implementation == 'native-prepared' else ''
                operation += f'result := A.tabulate<Blob>({count}, func(i) {{ let ?value = {call} else Prim.trap("native sighash"); value }});'
                source = actor(NATIVE_IMPORTS, native, '', operation,
                               'B.fromArray(A.flatten<Nat8>(A.map<Blob, [Nat8]>(result, B.toArray)))', '[Blob]', '[]')
                cases.append(emit(name, implementation, name, expected, source, count, notes, kind='native-api-comparison'))
    cases.extend(composed_verification())
    out = HERE / 'bitcoin-tx-cases' / 'cases.json'
    out.write_text(json.dumps({'cases': cases}, indent=2) + '\n')
    print(f'Generated {len(cases)} Bitcoin transaction cases in {out.parent}')


if __name__ == '__main__':
    main()
