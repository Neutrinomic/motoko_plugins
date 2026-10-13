#!/usr/bin/env python3
"""Reuse pinned cases without rewriting old evidence; add R sign-bit mutations."""
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
previous = ROOT/'tests/crypto-audit/prepared/ed25519/generate.py'
spec = importlib.util.spec_from_file_location('prepared_cases', previous)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
generator.HERE = HERE
generator.main()
# Nominal types and compiler registration are unchanged by this runtime-only
# round. The new audit does not duplicate the previous rejection suite.
for path in (HERE/'fail').glob('*.mo'):
    path.unlink()
(HERE/'fail').rmdir()
corpus = json.loads((ROOT/'tests/crypto-audit/round3/ed25519/vectors/cases.json').read_text())['cases']
rows = [row for row in corpus if row['name'].startswith('mixed-order-') and row['expected']=='true']
rfc = json.loads((ROOT/'benchmarks/crypto/round3/ed25519/fixtures/rfc8032.json').read_text())['vectors']
rows += rfc
text = '''//MOC-FLAG --plugin ../../../../../dist/ed25519 --package fast ../../../../../packages/fast/src --sanity-checks
import Ed "mo:fast/Ed25519";
func check(key : Blob, message : Blob, original : Blob, opposite : Blob) {
  assert Ed.verify(key,message,original) == #ok(true);
  assert Ed.verify(key,message,opposite) == #ok(false);
  switch (Ed.preparePublicKey(key)) {
    case (#ok prepared) {
      assert Ed.verifyPrepared(prepared,message,opposite) == #ok(false);
      assert Ed.verifyPrepared(prepared,message,original) == #ok(true);
    };
    case (_) assert false;
  };
};
'''
for row in rows:
    opposite = bytearray.fromhex(row['signature'])
    opposite[31] ^= 0x80
    text += f'// {row["name"]}\ncheck('+','.join(generator.blob(value) for value in
        (row['publicKey'],row['message'],row['signature'],opposite.hex()))+');\n'
(HERE/'run/sign-bit.mo').write_text(text)
provenance = json.loads((HERE/'provenance.json').read_text())
provenance['nominal_rejections'] = 0
provenance['public_sign_bit_mutations'] = len(rows)
provenance['native_predicate_cases'] = 118
provenance['native_sign_bit_mutations'] = 96
provenance['input_sha256'][str(previous.relative_to(ROOT))] = hashlib.sha256(previous.read_bytes()).hexdigest()
provenance['generated_sha256'] = {str(path.relative_to(HERE)):hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted((HERE/'run').glob('*.mo'))}
(HERE/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
