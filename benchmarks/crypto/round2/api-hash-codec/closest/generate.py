#!/usr/bin/env python3
"""Closest published implementations, with explicit contract differences.

Only creates files in this directory. Original API fixtures stay immutable.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2]
sys.path.insert(0, str(BENCH))
from common import actor, blob

inventory = json.loads((HERE.parent/'api-inventory.json').read_text())['api_rows']
suite = json.loads((HERE.parent/'suite-cases.json').read_text())['cases']
case_map = {(c['name'], c['implementation']): c for c in suite}
cases, overrides = [], {}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def emit(row, implementation, source, expected, notes, attribution):
    name = row['plugin_case']['name']
    path = HERE/'cases'/name/implementation/'main.mo'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source)
    original = case_map[(name, row['plugin_case']['implementation'])]
    assert original['expected_hex'] == expected.hex(), row['id']
    case = dict(name=name, family=original['family'], implementation=implementation,
                comparison='closest-published-counterpart', plugins=[],
                expected_hex=expected.hex(), source=path.relative_to(BENCH).as_posix(),
                notes=notes, attribution=attribution)
    cases.append(case)
    overrides[row['id']] = dict(native_case=dict(name=name, implementation=implementation,
                                               source=case['source'], source_sha256=sha(path)),
                                notes=notes, comparison_contract='closest published code; see caveat',
                                attribution=attribution)


ripemd_path = BENCH/'dependencies/.mops/bitcoin@0.2.1/src/Ripemd160.mo'
ripemd_attribution = dict(package='bitcoin', version='0.2.1',
                         source=ripemd_path.relative_to(BENCH).as_posix(),
                         source_sha256=sha(ripemd_path))
for row in inventory:
    if row.get('native_case') or row['module'] != 'RIPEMD160':
        continue
    function, size = row['function'], row['size']
    data = bytes(i % 251 for i in range(size))
    decls = f'transient let input : Blob = {blob(data)}; transient var state = H.Digest();'
    configure = 'state := H.Digest();'
    output = 'result'
    if function == 'init':
        operation, output = 'state := H.Digest();', 'Prim.arrayToBlob(state.sum())'
        expected = hashlib.new('ripemd160', b'').digest()
        note = 'Closest published code: bitcoin/Ripemd160.Digest() constructs mutable object state, while plugin init() returns a canonical immutable Blob. Timed constructor only; finalization for empty-state oracle occurs in query. No allocation/representation equivalence is claimed.'
    elif function == 'update':
        prefix = bytes(range(17))
        configure += ' state.write(Prim.blobToArray('+blob(prefix)+'));'
        operation, output = 'state.write(Prim.blobToArray(input));', 'Prim.arrayToBlob(state.sum())'
        expected = hashlib.new('ripemd160', prefix+data).digest()
        note = 'Closest published code: bitcoin/Ripemd160.Digest.write mutates its prepared receiver; plugin update returns a new immutable state preserving the input state and validates serialized state. Both append the same bytes to a 17-byte prefix. Required Blob-to-array input conversion is timed; final digest is checked in query. Cost ratio does not imply equivalent mutation/validation contracts.'
    elif function in ['finalize', 'Digest.sum']:
        configure += ' state.write(Prim.blobToArray(input));'
        operation = 'result := Prim.arrayToBlob(state.sum());'
        expected = hashlib.new('ripemd160', data).digest()
        note = 'Closest published code: bitcoin/Ripemd160.Digest.sum finalizes and consumes/locks mutable state; plugin '+function+' preserves state for repeat finalization and continued writes. Both return the same digest once. Result array-to-Blob conversion is timed. Cost ratio does not imply equivalent state-preservation contracts.'
    else:
        raise AssertionError(function)
    emit(row, 'mops-bitcoin-closest', actor('import H "mo:bitcoin/Ripemd160";', decls,
         configure, operation, output), expected, note, ripemd_attribution)


segwit_path = BENCH/'dependencies/.mops/bitcoin@0.2.1/src/Segwit.mo'
segwit_source = segwit_path.read_text()
start = segwit_source.index('  func convertBits(')
opening = segwit_source.index('{', start)
depth, finish = 1, opening+1
while depth:
    depth += (segwit_source[finish] == '{')-(segwit_source[finish] == '}')
    finish += 1
assert segwit_source[finish] == ';'
exact_body = segwit_source[start:finish+1]
# Preserve and record the exact published function, including its private
# declaration. It becomes actor-private, so no public API modification is made.
(HERE/'bitcoin-0.2.1-convertBits.mo.txt').write_text(exact_body+'\n')
for row in inventory:
    if row['id'] != 'Bech32.convertBits':
        continue
    original = case_map[(row['plugin_case']['name'], row['plugin_case']['implementation'])]
    source = (BENCH/original['source']).read_text()
    literal = re.search(r'input := "((?:\\[0-9a-f]{2})*)";', source).group(1)
    data = bytes.fromhex(literal.replace('\\', ''))
    bits = ''.join(f'{v:08b}' for v in data)
    bits += '0'*((-len(bits)) % 5)
    expected = bytes(int(bits[i:i+5], 2) for i in range(0, len(bits), 5))
    imports = '''import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import VarArray "mo:core/VarArray";
import { type Result } "mo:core/Types";'''
    decls = exact_body+'\n transient let input : Blob = '+blob(data)+';'
    operation = 'result := switch (convertBits(Prim.blobToArray(input), 0, 8, 5, true)) { case (#ok(value)) Prim.arrayToBlob(value); case (#err(_)) Prim.trap("unexpected conversion error") };'
    note = 'Closest published code: exact private convertBits function extracted unchanged from bitcoin0.2.1 Segwit.mo, with attribution and SHA256 pins. Valid 8-to-5 padded conversion matches byte-for-byte; Blob-to-array and array-to-Blob adapters are timed. The plugin additionally validates bit widths and enforces16MiB input/output bounds; published private code assumes valid widths and has no such cap. This is a benchmark-only actor-private extraction, not a public package API.'
    attribution = dict(package='bitcoin', version='0.2.1',
                       source=segwit_path.relative_to(BENCH).as_posix(), source_sha256=sha(segwit_path),
                       extraction_sha256=hashlib.sha256(exact_body.encode()).hexdigest(),
                       extraction_start_line=segwit_source[:start].count('\n')+1,
                       extraction_end_line=segwit_source[:finish+1].count('\n')+1)
    emit(row, 'mops-bitcoin-private', actor(imports, decls, '', operation), expected, note, attribution)


# The pinned implementation handles each individual output block correctly.
# Joining two public seek calls is existing-API composition, not a new hash.
blake_path = BENCH/'dependencies/.mops/blake3@0.1.2/src/lib.mo'
blake_vectors = {int(parts[0]): parts[1:] for line in (BENCH/'fixtures/blake3-official-vectors.txt').read_text().splitlines() if (parts := line.split())}
for row in inventory:
    if row['id'] not in ['BLAKE3.xof', 'BLAKE3.finalizeXof']:
        continue
    data = bytes(i % 251 for i in range(1024))
    expected = bytes.fromhex(blake_vectors[1024][0])[13:113]
    decls = f'transient let input : Blob = {blob(data)};'
    operation = 'result := Prim.arrayToBlob(Array.append<Nat8>(H.hasherFinalizeSeek(state, 13, 51), H.hasherFinalizeSeek(state, 64, 49)));'
    if row['function'] == 'xof':
        configure = ''
        operation = 'let state = H.hasherUpdate(H.hasherInit(), Prim.blobToArray(input)); '+operation
    else:
        decls += ' transient var state = H.hasherInit();'
        configure = 'state := H.hasherUpdate(H.hasherInit(), Prim.blobToArray(input));'
    note = 'Closest published code composed from two correct public hasherFinalizeSeek calls: bytes13..63 and64..112, concatenated and converted to Blob inside timing. The pinned single call truncates at its first output-block boundary, so it cannot provide100bytes directly. This composition produces identical official-vector output without implementing compression or cryptographic state transitions. Only one1024-byte input chunk is used; this does not repair upstream multi-chunk hashing. '+('One-shot timing includes init and update.' if row['function']=='xof' else 'State preparation is excluded and finalization preserves its immutable receiver.')
    attribution = dict(package='blake3', version='0.1.2', source=blake_path.relative_to(BENCH).as_posix(),
                       source_sha256=sha(blake_path),
                       composition='Array.append(hasherFinalizeSeek(state,13,51),hasherFinalizeSeek(state,64,49))')
    emit(row, 'mops-blake3-composed', actor('import H "mo:blake3";\nimport Array "mo:base/Array";',
         decls, configure, operation), expected, note, attribution)


# Domain-separate the public immutable state and compose published hashing
# primitives. Compression, endian conversion, padding and output generation
# remain entirely in the pinned library. Both phases fit one input chunk.
derive_helpers = '''
  func withFlags(state : H.Hasher, flags : Nat8) : H.Hasher {
    let chunk = state.chunk;
    {
      key = state.key; cvStackLen = state.cvStackLen; cvStack = state.cvStack;
      chunk = {
        cv = chunk.cv; chunkCounter = chunk.chunkCounter; buf = chunk.buf;
        bufLen = chunk.bufLen; blocksCompressed = chunk.blocksCompressed; flags;
      };
    }
  };
  func newDerive(context : Text) : H.Hasher {
    let contextState = withFlags(H.hasherInit(), Prim.natToNat8(H.DERIVE_KEY_CONTEXT));
    let contextKey = H.hasherFinalize(H.hasherUpdate(contextState, Prim.blobToArray(Prim.encodeUtf8(context))), 32);
    withFlags(H.hasherInitKeyed(contextKey), Prim.natToNat8(H.DERIVE_KEY_MATERIAL))
  };
'''
context = 'BLAKE3 2019-12-27 16:29:52 test vectors context'
for row in inventory:
    if row['id'] not in ['BLAKE3.deriveKey', 'BLAKE3.newDeriveKey']:
        continue
    decls = derive_helpers+f'\n transient let context : Text = "{context}";'
    output = 'result'
    if row['function'] == 'deriveKey':
        decls += ' transient let input : Blob = '+blob(bytes(i % 251 for i in range(1024)))+';'
        operation = 'let state = newDerive(context); result := Prim.arrayToBlob(H.hasherFinalize(H.hasherUpdate(state, Prim.blobToArray(input)), 32));'
        expected = bytes.fromhex(blake_vectors[1024][2][:64])
    else:
        decls += ' transient var state = H.hasherInit();'
        operation = 'state := newDerive(context);'
        output = 'Prim.arrayToBlob(H.hasherFinalize(state, 32))'
        expected = bytes.fromhex(blake_vectors[0][2][:64])
    note = 'Closest published primitives composed with two-phase domain separation: exported Hasher record/DERIVE_KEY_CONTEXT flag hash UTF8context; resulting32-byte key initializes published hasherInitKeyed with exported DERIVE_KEY_MATERIAL flag. All compression, state updates, key decoding and finalization use pinned public functions. The high-level upstream derive_key ignores context and is not used. Official BLAKE3 context/material vectors independently check this bounded composition; context and material each fit a single1024-byte chunk, so no claim is made for broken upstream multi-chunk behavior. '+('The whole derive operation is timed.' if row['function']=='deriveKey' else 'Only derived-state creation is timed; finalization of empty material occurs in query.')
    attribution = dict(package='blake3', version='0.1.2', source=blake_path.relative_to(BENCH).as_posix(),
                       source_sha256=sha(blake_path),
                       composition='published Hasher/ChunkState records + DERIVE_KEY_CONTEXT/DERIVE_KEY_MATERIAL + hasherInit/hasherInitKeyed/hasherUpdate/hasherFinalize')
    emit(row, 'mops-blake3-composed', actor('import H "mo:blake3";', decls, '', operation, output),
         expected, note, attribution)


remaining = [dict(id=r['id'], reason=r['notes']) for r in inventory
             if not r.get('native_case') and r['id'] not in overrides]
assert not remaining
(HERE/'cases.json').write_text(json.dumps({'cases': cases}, indent=2)+'\n')
(HERE/'override.json').write_text(json.dumps(overrides, indent=2)+'\n')
(HERE/'remaining-blanks.json').write_text(json.dumps({'rows': remaining,
    'notes': 'All12 previously blank rows now have closest published counterparts with explicit caveats. RIPEMD uses mutable/consuming methods; Bech32 extracts the exact private function; long XOF concatenates public seeks; derivation orchestrates public states/flags and existing hash primitives. Runtime exact-output validation remains required.'}, indent=2)+'\n')
print(f'{len(cases)} closest-code actors; {len(overrides)} overrides; {len(remaining)} genuine unsupported rows')
