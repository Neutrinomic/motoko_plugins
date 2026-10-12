#!/usr/bin/env python3
"""Generate independent Bitcoin composition answers with Bitcoin Core v29.0.

Fetches unmodified, MIT-licensed Bitcoin Core functional-test helpers into a
cache outside the repository. Output fixtures contain inputs and digests only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

HERE = Path(__file__).resolve().parent
BASE = 'https://raw.githubusercontent.com/bitcoin/bitcoin/v29.0/test/functional/test_framework/'
FILES = ['script.py', 'messages.py', 'key.py', 'util.py', 'authproxy.py', 'coverage.py',
         'crypto/secp256k1.py', 'crypto/ripemd160.py', 'crypto/siphash.py']


def blob(data):
    return '"' + ''.join('\\%02x' % b for b in data) + '"'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path('/tmp/bitcoin-base58-audit'))
    args = parser.parse_args()
    framework = args.cache / 'test_framework'
    framework.mkdir(parents=True, exist_ok=True)
    (framework / '__init__.py').touch()
    provenance = {}
    for name in FILES:
        dest = framework / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.is_file():
            dest.write_bytes(urllib.request.urlopen(BASE + name).read())
        provenance[name] = {'url': BASE + name, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}
    sys.path.insert(0, str(args.cache))
    from test_framework.messages import COutPoint, CTransaction, CTxIn, CTxOut, hash256
    from test_framework.script import CScript, LegacySignatureHash, SegwitV0SignatureHash, TaprootSignatureHash
    from test_framework.key import TaggedHash

    transactions = []
    for output_count in [3, 1, 0]:
        tx = CTransaction()
        tx.version = 2
        tx.nLockTime = 0x99aabbcc
        tx.vin = [CTxIn(COutPoint(int.from_bytes(bytes((i * 37 + j * 5) % 256 for j in range(32)), 'little'), 17 + i),
                        bytes([0x51 + i]), [0, 0x11223344, 0xffffffff][i]) for i in range(3)]
        all_outputs = [CTxOut(100000 + i * 17, bytes([0x51 + i]) * [0, 252, 253][i]) for i in range(3)]
        tx.vout = all_outputs[:output_count]
        transactions.append(tx)
    prevouts = [CTxOut(90000000 + i * 13, b'\x51\x20' + bytes([31 + i]) * 32) for i in range(3)]
    scripts = [b'', b'\xab\x51\xab', b'\x01\xab\xab\xac', b'\x4c\x02\xab\x00\xab',
               b'\x4d\xfd\x00' + b'\xab' * 253 + b'\xab']
    legacy_types = [0, 1, 2, 3, 4, 0x21, 0x81, 0x82, 0x83, 0xff, 0xffffffff]
    tap_types = [0, 1, 2, 3, 0x81, 0x82, 0x83]
    rows = []
    legacy_count = segwit_count = taproot_count = 0
    for ti, tx in enumerate(transactions):
        for index in range(4):
            for typ in legacy_types:
                for script in scripts:
                    digest, _ = LegacySignatureHash(CScript(script), tx, index, typ)
                    rows.append(f'  ({ti}, {index}, {blob(script)}, {typ}, {blob(digest)}),')
                    legacy_count += 1
    legacy = '\n'.join(rows)
    rows = []
    for ti, tx in enumerate(transactions):
        for index in range(3):
            for typ in legacy_types:
                for script in scripts:
                    amount = prevouts[index].nValue
                    digest = SegwitV0SignatureHash(CScript(script), tx, index, typ, amount)
                    rows.append(f'  ({ti}, {index}, {blob(script)}, {typ}, {amount}, {blob(digest)}),')
                    segwit_count += 1
    segwit = '\n'.join(rows)
    rows = []
    for ti, tx in enumerate(transactions):
        for index in range(3):
            for typ in tap_types:
                if typ & 3 == 3 and index >= len(tx.vout):
                    continue
                for annex in [None, b'\x50', b'\x50' + bytes(range(252))]:
                    for codesep in [None, -1, 0, 0x7fffffff]:
                        script = scripts[4]
                        kwargs = {'annex': annex}
                        extension = 'null'
                        if codesep is not None:
                            kwargs.update(scriptpath=True, leaf_script=script, codeseparator_pos=codesep)
                            leaf = TaggedHash('TapLeaf', b'\xc0\xfd\x01\x01' + script)
                            # Script is 257 bytes: 3-byte PUSHDATA2 +253 data +1 separator.
                            extension = '?{ tapLeafHash = ' + blob(leaf) + '; codeSeparatorPosition = ' + str(codesep & 0xffffffff) + ' }'
                        digest = TaprootSignatureHash(tx, prevouts, typ, index, **kwargs)
                        ann = 'null' if annex is None else '?' + blob(annex)
                        rows.append(f'  ({ti}, {index}, {typ}, {ann}, {extension}, {blob(digest)}),')
                        taproot_count += 1
    taproot = '\n'.join(rows)
    txs = '\n'.join('  ' + blob(tx.serialize_without_witness()) + ',' for tx in transactions)
    spent = '\n'.join('  { value = ' + str(o.nValue) + '; scriptPubKey = ' + blob(o.scriptPubKey) + ' },' for o in prevouts)
    txids = '\n'.join('  ' + blob(hash256(tx.serialize_without_witness())[::-1]) + ',' for tx in transactions)
    source = f'''// Generated by generate-oracle.py using unmodified Bitcoin Core v29.0 helpers.
import T "mo:fast/Bitcoin/Transaction";
import Prim "mo:⛔";
func get<A>(x : ?A) : A {{ switch x {{ case (?v) v; case null {{ assert false; loop {{}} }} }} }};
let raw : [Blob] = [\n{txs}\n];
let txids : [Blob] = [\n{txids}\n];
let txs = Prim.Array_tabulate<T.Tx>(raw.size(), func(i) {{ get(T.parse(raw[i])) }});
let spent : [T.Output] = [\n{spent}\n];
let legacy : [(Nat, Nat, Blob, Nat32, Blob)] = [\n{legacy}\n];
let segwit : [(Nat, Nat, Blob, Nat32, Nat64, Blob)] = [\n{segwit}\n];
let taproot : [(Nat, Nat, Nat8, ?Blob, ?T.TapscriptExtension, Blob)] = [\n{taproot}\n];
var n = 0;
for (tx in txs.values()) {{
  assert T.serialize(tx, false) == ?raw[n];
  assert T.txid(tx) == ?txids[n];
  assert T.wtxid(tx) == ?txids[n];
  n += 1;
}};
n := 0;
for ((ti, index, script, kind, expected) in legacy.values()) {{
  let actual = T.signatureHashLegacy(txs[ti], index, script, kind);
  if (actual != ?expected) {{ Prim.debugPrint("legacy case " # debug_show n); assert false }};
  n += 1;
}};
let v0 = Prim.Array_tabulate<T.SegwitV0Hasher>(txs.size(), func(i) {{ get(T.prepareSegwitV0(txs[i])) }});
n := 0;
for ((ti, index, script, kind, amount, expected) in segwit.values()) {{
  let actual = v0[ti].signatureHash(index, script, amount, kind);
  if (actual != ?expected) {{ Prim.debugPrint("segwit case " # debug_show n); assert false }};
  assert T.signatureHashSegwitV0(txs[ti], index, script, amount, kind) == ?expected;
  n += 1;
}};
let tap = Prim.Array_tabulate<T.TaprootHasher>(txs.size(), func(i) {{ get(T.prepareTaproot(txs[i], spent)) }});
n := 0;
for ((ti, index, kind, annex, extension, expected) in taproot.values()) {{
  let actual = tap[ti].signatureHash(index, kind, annex, extension);
  if (actual != ?expected) {{ Prim.debugPrint("taproot case " # debug_show n); assert false }};
  assert T.signatureHashTaproot(txs[ti], index, spent, kind, annex, extension) == ?expected;
  n += 1;
}};
'''
    (HERE / 'oracle.mo').write_text(source)
    (HERE / 'oracle-provenance.json').write_text(json.dumps({
        'upstream': 'Bitcoin Core v29.0', 'files': provenance,
        'legacy_cases': legacy_count, 'segwit_v0_cases': segwit_count, 'taproot_cases': taproot_count,
        'generated_sha256': hashlib.sha256(source.encode()).hexdigest(),
    }, indent=2) + '\n')
    print(f'Generated {{legacy: {legacy_count}, segwit: {segwit_count}, taproot: {taproot_count}}}')


if __name__ == '__main__':
    main()
