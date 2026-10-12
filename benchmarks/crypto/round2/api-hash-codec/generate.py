#!/usr/bin/env python3
"""Complete callable fixtures for BLAKE3/HMAC and checked Bitcoin encodings.

Expected bytes come only from Python hashlib/hmac, integer radix conversion,
and the retained official BLAKE3 corpus. Public method timings exclude input
and state preparation, and result interpretation runs in the query method.
"""
import hashlib
import hmac
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
sys.path.insert(0, str(BENCH))
from common import actor, blob

cases, rows = [], []
existing = json.loads((BENCH / 'all-cases.json').read_text())['cases']


def add(name, family, impl, imports, decls, configure, operation, expected,
        plugins=(), output='result', typ='Blob', initial='""', notes=''):
    target = HERE / 'cases' / name / impl / 'main.mo'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(actor(imports, decls, configure, operation, output, typ, initial))
    case = dict(name=name, family=family, implementation=impl,
                comparison='isolated-public-call', plugins=list(plugins),
                source=target.relative_to(BENCH).as_posix(), expected_hex=expected.hex(),
                notes=notes)
    cases.append(case)
    return {'name': name, 'implementation': impl}


def row(module, function, workload, size, plugin, native=None, notes=''):
    rows.append(dict(id=module+'.'+function, module=module, function=function,
                     workload=workload, size=size, plugin_case=plugin,
                     native_case=native, notes=notes))


def existing_row(module, function, name, baseline, workload, size, notes=''):
    selected = {c['implementation']: c for c in existing if c['name'] == name}
    assert 'native' in selected and baseline in selected
    row(module, function, workload, size,
        {'name': name, 'implementation': 'native'},
        {'name': name, 'implementation': baseline}, notes)


def unwrap(expr):
    return f'switch ({expr}) {{ case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected result") }}'


# Each inline reference below preserves reusable keys and non-destructive sum.
# Mops bitcoin/Hmac itself is consuming, so directly timing that sum would not
# implement the same operation. This composition uses only public sha2 APIs.
def reference_hmac(mode):
    suffix = '256' if mode == 'sha256' else '512'
    blocksize = 64 if mode == 'sha256' else 128
    return f'''
  type Digest = {{ write : Blob -> (); sum : () -> Blob; reset : () -> () }};
  type PreparedKey = {{ digest : Blob -> Blob; stream : () -> Digest }};
  func restore(snapshot : S.StaticSha{suffix}) : S.Digest {{
    let value = S.Digest(#{mode}); value.unshare(snapshot); value
  }};
  func prepare(key : Blob) : PreparedKey {{
    let normalized = if (key.size() > {blocksize}) S.fromBlob(#{mode}, key) else key;
    let keyArray = Prim.blobToArray(normalized);
    let innerPad = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>({blocksize}, func(i) {{
      (if (i < keyArray.size()) keyArray[i] else 0) ^ 0x36
    }}));
    let outerPad = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>({blocksize}, func(i) {{
      (if (i < keyArray.size()) keyArray[i] else 0) ^ 0x5c
    }}));
    let inner = S.Digest(#{mode}); inner.writeBlob(innerPad);
    let outer = S.Digest(#{mode}); outer.writeBlob(outerPad);
    let initialInner = inner.share();
    let initialOuter = outer.share();
    func finish(innerDigest : Blob) : Blob {{
      let value = restore(initialOuter); value.writeBlob(innerDigest); value.sum()
    }};
    object {{
      public func digest(message : Blob) : Blob {{
        let value = restore(initialInner); value.writeBlob(message); finish(value.sum())
      }};
      public func stream() : Digest {{
        var current = restore(initialInner);
        object {{
          public func write(message : Blob) {{ current.writeBlob(message) }};
          public func sum() : Blob {{ let copy = restore(current.share()); finish(copy.sum()) }};
          public func reset() {{ current.unshare(initialInner) }};
        }}
      }};
    }}
  }};
'''


key = bytes(range(32))
message = bytes(i % 251 for i in range(1024))
for mode, suffix in [('sha256', '256'), ('sha512', '512')]:
    existing_row('HMAC', mode, f'hmac-{mode}-1024', 'mops-bitcoin',
                 'authenticate one message', '32-byte key; 1024-byte message',
                 'Direct Mops Hmac construction, write and one consuming sum implement this one-shot operation.')
    imports = {'native': 'import H "mo:fast/HMAC";',
               'mops-sha2-composed': f'import S "mo:sha2/Sha{suffix}";'}
    for action in ['constructor', 'write', 'sum', 'reset', 'prepare',
                   'prepared-digest', 'prepared-stream', 'prepared-write',
                   'prepared-sum', 'prepared-reset']:
        name = f'api-hmac-{mode}-{action}'
        refs = {}
        for impl in ['native', 'mops-sha2-composed']:
            plugin = impl == 'native'
            prepare = f'H.prepareSha{suffix}(key)' if plugin else 'prepare(key)'
            construct = f'H.SHA{suffix}(key)' if plugin else 'prepare(key).stream()'
            digest_type = 'H.Digest' if plugin else 'Digest'
            prepared_type = 'H.PreparedKey' if plugin else 'PreparedKey'
            decls = ('' if plugin else reference_hmac(mode)) + f'''
              transient let key : Blob = {blob(key)};
              transient let input : Blob = {blob(message)};
              transient var prepared : {prepared_type} = {prepare};
              transient var stream : {digest_type} = {construct};
            '''
            config = f'prepared := {prepare}; stream := '+('prepared.stream();' if action.startswith('prepared-') else construct+';')
            output = 'result'
            expected = hmac.digest(key, message, mode)
            if action == 'constructor':
                operation = f'stream := {construct};'
                output, expected = 'stream.sum()', hmac.digest(key, b'', mode)
            elif action in ['write', 'prepared-write']:
                operation, output = 'stream.write(input);', 'stream.sum()'
            elif action in ['sum', 'prepared-sum']:
                config += ' stream.write(input);'
                operation = 'result := stream.sum();'
                output = 'assert stream.sum() == result; stream.write("\\01"); assert stream.sum() == '+blob(hmac.digest(key, message+b'\x01', mode))+'; result'
            elif action in ['reset', 'prepared-reset']:
                config += ' stream.write(input);'
                operation = 'stream.reset();'
                output, expected = 'stream.sum()', hmac.digest(key, b'', mode)
            elif action == 'prepare':
                operation, output = f'prepared := {prepare};', 'prepared.digest(input)'
            elif action == 'prepared-digest':
                operation = 'result := prepared.digest(input);'
                output = 'assert prepared.digest(input) == result; assert prepared.digest("") == '+blob(hmac.digest(key, b'', mode))+'; result'
            elif action == 'prepared-stream':
                operation = 'stream := prepared.stream();'
                output, expected = 'let other = prepared.stream(); other.write(input); assert other.sum() == '+blob(hmac.digest(key, message, mode))+'; stream.sum()', hmac.digest(key, b'', mode)
            else:
                raise AssertionError(action)
            refs[impl] = add(name, 'hmac-sha2', impl, imports[impl], decls, config,
                             operation, expected, ['hmac-sha2'] if plugin else [],
                             output=output,
                             notes='One public call timed. Pure Motoko reference composes pinned sha2 public share/unshare snapshots to retain reusable-key and non-destructive sum semantics; all oracle bytes use Python hmac.')
        function = {
            'constructor': f'SHA{suffix}', 'write': f'SHA{suffix}.write',
            'sum': f'SHA{suffix}.sum', 'reset': f'SHA{suffix}.reset',
            'prepare': f'prepareSha{suffix}',
            'prepared-digest': f'prepareSha{suffix}.digest',
            'prepared-stream': f'prepareSha{suffix}.stream',
            'prepared-write': f'prepareSha{suffix}.stream.write',
            'prepared-sum': f'prepareSha{suffix}.stream.sum',
            'prepared-reset': f'prepareSha{suffix}.stream.reset',
        }[action]
        row('HMAC', function, action.replace('-', ' '),
            '32-byte key' if action == 'prepare' else
            '32-byte key; '+('empty stream' if action in ['constructor', 'prepared-stream'] else '1024-byte message'),
            refs['native'], refs['mops-sha2-composed'],
            'Equivalent pure Motoko composition over pinned sha2 state snapshots; key/state setup excluded except constructor and prepare. Reset follows a 1024-byte write outside timing.')


vectors = {int(parts[0]): parts[1:] for line in (BENCH/'fixtures/blake3-official-vectors.txt').read_text().splitlines() if (parts := line.split())}
blake_key = b'whats the Elvish word for friend'
context = 'BLAKE3 2019-12-27 16:29:52 test vectors context'
existing_row('BLAKE3', 'digest', 'blake3-1024', 'mops-blake3', 'unkeyed digest', '1024 bytes')
existing_row('BLAKE3', 'keyedHash', 'blake3-keyed-1024', 'mops-blake3', 'keyed digest', '32-byte key; 1024 bytes',
             'Valid 32-byte key. Plugin returns a checked Result; Mops accepts valid key directly.')
for action in ['deriveKey', 'xof', 'new', 'newKeyed', 'newDeriveKey', 'update', 'finalize', 'finalizeXof']:
    name = 'api-blake3-'+action.lower()
    expected = bytes.fromhex(vectors[1024][0][:64])
    decls = f'transient let input : Blob = {blob(message)}; transient let key : Blob = {blob(blake_key)}; transient var state = H.new();'
    configure, output = 'state := H.new();', 'result'
    native = None
    if action == 'deriveKey':
        operation = f'result := H.deriveKey("{context}", input);'
        expected = bytes.fromhex(vectors[1024][2][:64])
    elif action == 'xof':
        operation = f'result := {unwrap("H.xof(input, 13, 100)")};'
        expected = bytes.fromhex(vectors[1024][0])[13:113]
    elif action == 'new':
        operation, output = 'state := H.new();', unwrap('H.finalize(state)')
        expected = bytes.fromhex(vectors[0][0][:64])
    elif action == 'newKeyed':
        operation, output = f'state := {unwrap("H.newKeyed(key)")};', unwrap('H.finalize(state)')
        expected = bytes.fromhex(vectors[0][1][:64])
    elif action == 'newDeriveKey':
        operation, output = f'state := H.newDeriveKey("{context}");', unwrap('H.finalize(state)')
        expected = bytes.fromhex(vectors[0][2][:64])
    elif action == 'update':
        decls += ' transient var original = H.new();'
        configure += ' original := state;'
        operation, output = f'state := {unwrap("H.update(state, input)")};', unwrap('H.finalize(state)')
        output = 'assert ('+unwrap('H.finalize(original)')+') == '+blob(bytes.fromhex(vectors[0][0][:64]))+'; '+output
    else:
        configure += f' state := {unwrap("H.update(state, input)")};'
        operation = f'result := {unwrap("H.finalize(state)" if action == "finalize" else "H.finalizeXof(state, 13, 100)")};'
        if action == 'finalizeXof': expected = bytes.fromhex(vectors[1024][0])[13:113]
    plugin = add(name, 'blake3', 'native', 'import H "mo:fast/BLAKE3";', decls,
                 configure, operation, expected, ['blake3'], output=output,
                 notes='Official BLAKE3 corpus oracle. Sole public call measured; output state interpretation and digest serialization excluded.')
    notes = ''
    if action in ['new', 'newKeyed', 'update', 'finalize']:
        baseline_decls = f'transient let input : Blob = {blob(message)}; transient let key : Blob = {blob(blake_key)}; transient var state = H.hasherInit();'
        baseline_configure = 'state := H.hasherInit();'
        baseline_output = 'Prim.arrayToBlob(H.hasherFinalize(state, 32))'
        if action == 'new': baseline_operation = 'state := H.hasherInit();'
        elif action == 'newKeyed': baseline_operation = 'state := H.hasherInitKeyed(Prim.blobToArray(key));'
        elif action == 'update':
            baseline_decls += ' transient var original = H.hasherInit();'
            baseline_configure += ' original := state;'
            baseline_operation = 'state := H.hasherUpdate(state, Prim.blobToArray(input));'
            baseline_output = 'assert Prim.arrayToBlob(H.hasherFinalize(original, 32)) == '+blob(bytes.fromhex(vectors[0][0][:64]))+'; '+baseline_output
        else:
            baseline_configure += ' state := H.hasherUpdate(state, Prim.blobToArray(input));'
            baseline_operation, baseline_output = 'result := Prim.arrayToBlob(H.hasherFinalize(state, 32));', 'result'
        native = add(name, 'blake3', 'mops-blake3', 'import H "mo:blake3";', baseline_decls,
                     baseline_configure, baseline_operation, expected, output=baseline_output,
                     notes='Uses public immutable Hasher API so update preserves the input state, matching mo:fast semantics. Valid single-chunk official vector; representation conversions inside API timing.')
        notes = 'Mops immutable Hasher API, single chunk; Blob/array conversion included. Finalization preserves state.'
    elif action in ['deriveKey', 'newDeriveKey']:
        notes = 'No correct pinned native counterpart: Mops blake3 0.1.2 ignores the derivation context.'
    else:
        notes = 'No correct pinned native counterpart for this 100-byte seek: Mops blake3 0.1.2 truncates output at the first 64-byte block boundary.'
    row('BLAKE3', action, 'isolated '+action,
        '32-byte key; empty state' if action == 'newKeyed' else
        'empty state' if action in ['new', 'newDeriveKey'] else
        '1024-byte input; seek 13; output 100 bytes' if action in ['xof', 'finalizeXof'] else '1024 bytes',
        plugin, native, notes)


# Use established paired plain codecs and add missing checksum codec pairs.
for function in ['encode', 'decode']:
    existing_row('Base58', function, f'base58-{function}-82', 'mops-bitcoin',
                 'Bitcoin Base58 '+function, '82 bytes',
                 'Valid alphabet, leading-zero preservation, Blob/array representation conversions included.')
    existing_row('Bech32', function, f'bech32m-{function}-53', 'mops-bitcoin',
                 'Bech32m '+function, '2-byte HRP; 53 groups',
                 'Valid lowercase BIP350 checksummed payload; both APIs validate checksum on decode.')

alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def base58(value):
    leading = len(value)-len(value.lstrip(b'\0'))
    integer, encoded = int.from_bytes(value, 'big'), ''
    while integer:
        integer, digit = divmod(integer, 58)
        encoded = alphabet[digit]+encoded
    return '1'*leading+encoded

payload = bytes(i % 251 for i in range(78))
checked = payload+hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
encoded = base58(checked)
for action in ['encode', 'decode']:
    refs = {}
    for impl in ['native', 'mops-bitcoin']:
        plugin = impl == 'native'
        name = 'api-base58check-'+action+'-78'
        imports = f'import B "mo:{"fast" if plugin else "bitcoin"}/Base58Check";'
        if action == 'encode':
            decls = f'transient let input : Blob = {blob(payload)};'
            op = 'result := B.encode('+('input' if plugin else 'Prim.blobToArray(input)')+');'
            expected, typ, initial, output = encoded.encode(), 'Text', '""', 'Prim.encodeUtf8(result)'
        else:
            decls = f'transient let input : Text = "{encoded}";'
            op = 'result := '+(unwrap('B.decode(input)') if plugin else 'switch (B.decode(input)) { case (?value) Prim.arrayToBlob(value); case null Prim.trap("unexpected checksum") }')+';'
            expected, typ, initial, output = payload, 'Blob', '""', 'result'
        refs[impl] = add(name, 'base58', impl, imports, decls, '', op, expected,
                        ['base58', 'sha256'] if plugin else [], typ=typ, initial=initial, output=output,
                        notes='Python integer-radix + hashlib double-SHA256 oracle. Valid Base58 alphabet; both paths verify/produce all four checksum bytes; payload conversion included.')
    row('Base58Check', action, 'checksummed Bitcoin extended-key sized payload', '78-byte payload; 4-byte checksum',
        refs['native'], refs['mops-bitcoin'],
        ('Both paths generate the four-byte checksum.' if action == 'encode' else 'Both paths check the four-byte checksum.')+
        ' Valid input avoids unrelated malformed-character error-policy differences.')


# Reuse the independently checked round-two Segwit fixtures; add equivalent
# pure Motoko calls with full decoded HRP/version/program framing in the query.
bech_cases = json.loads((BENCH/'round2/bech32-workloads/cases.json').read_text())['cases']
by_name = {case['name']: case for case in bech_cases}
program = bytes.fromhex('79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798')
address = bytes.fromhex(by_name['bech32-segwit-encode-v1-program32']['expected_hex']).decode()
for action in ['encode', 'decode']:
    name = f'bech32-segwit-{action}-v1-program32'
    plugin = by_name[name]
    if action == 'encode':
        decls = f'transient let input : Blob = {blob(program)};'
        op = 'result := '+unwrap('S.encode("bc", {version = 1; program = Prim.blobToArray(input)})')+';'
        typ, initial, output = 'Text', '""', 'Prim.encodeUtf8(result)'
    else:
        decls = f'transient let input : Text = "{address}";'
        op = 'result := '+unwrap('S.decode(input)')+';'
        typ, initial = '(Text, S.WitnessProgram)', '("", {version = 0; program = []})'
        output = 'Prim.arrayToBlob(Array.concat<Nat8>(Array.concat<Nat8>(Prim.blobToArray(Prim.encodeUtf8(result.0)), [0, result.1.version]), result.1.program))'
    native = add(name, 'bech32', 'mops-bitcoin', 'import S "mo:bitcoin/Segwit";\nimport Array "mo:core/Array";',
                 decls, '', op, bytes.fromhex(plugin['expected_hex']), output=output, typ=typ, initial=initial,
                 notes='Paired against official-secp-generator witness program checked by existing independent Python BIP173/BIP350 oracle. Both paths validate witness version, program length and checksum variant; the native encode implementation additionally round-trips through decode.')
    row('Segwit', action, 'Taproot v1 witness program '+action, '32-byte program; 62-character address',
        {'name': name, 'implementation': 'native'}, native,
        'Native Mops encoder additionally checks its output by decoding it. Both decoders validate every field; output query retains HRP, version and program.')
row('Bech32', 'convertBits', '8-bit to padded 5-bit groups', '32 input bytes; 52 output groups',
    {'name': 'bech32-convert-8to5-n32', 'implementation': 'native'}, None,
    'Pinned bitcoin Segwit bit conversion is private; no independently callable native counterpart is exposed.')


# A seek fully contained within one output block is correct in the pinned
# implementation. Keep the longer unsupported workloads above, and separately
# provide the closest correct published counterpart as the representative row.
for action in ['xof', 'finalizeXof']:
    name = 'api-blake3-'+action.lower()+'-seek13-length32'
    expected = bytes.fromhex(vectors[1024][0])[13:45]
    refs = {}
    for impl in ['native', 'mops-blake3']:
        plugin = impl == 'native'
        imports = 'import H "mo:fast/BLAKE3";' if plugin else 'import H "mo:blake3";'
        decls = f'transient let input : Blob = {blob(message)};'
        configure = ''
        if action == 'xof':
            operation = ('result := '+unwrap('H.xof(input, 13, 32)')+';' if plugin else
                         'let state = H.hasherUpdate(H.hasherInit(), Prim.blobToArray(input)); result := Prim.arrayToBlob(H.hasherFinalizeSeek(state, 13, 32));')
        else:
            decls += ' transient var state = '+('H.new();' if plugin else 'H.hasherInit();')
            configure = ('state := '+unwrap('H.update(H.new(), input)')+';' if plugin else
                         'state := H.hasherUpdate(H.hasherInit(), Prim.blobToArray(input));')
            operation = ('result := '+unwrap('H.finalizeXof(state, 13, 32)')+';' if plugin else
                         'result := Prim.arrayToBlob(H.hasherFinalizeSeek(state, 13, 32));')
        refs[impl] = add(name, 'blake3', impl, imports, decls, configure, operation,
                         expected, ['blake3'] if plugin else [],
                         notes='Official BLAKE3 vector bytes13..44. One1024-byte input chunk and seek output fully within first64-byte output block are correct in the pinned Mops implementation. Immutable state preserved; output conversion included.')
    row('BLAKE3', action, 'short seeked XOF within one output block',
        '1024-byte input; seek 13; output 32 bytes', refs['native'], refs['mops-blake3'],
        'Closest correct published counterpart: immutable Mops Hasher API. One-shot xof includes init/update/finalize; finalizeXof prepares state outside measurement. Does not establish correctness for multi-block XOF.')
    rows[-1]['id'] += ':seek13:length32'
    rows[-1]['representative'] = True


(HERE/'cases.json').write_text(json.dumps({'cases': cases}, indent=2)+'\n')
(HERE/'inventory.json').write_text(json.dumps({'api_rows': rows}, indent=2)+'\n')
print(f'Generated {len(cases)} new cases; {len(rows)} callable rows (SHA/RIPEMD and Bech32 supplemental inventory merged separately).')
