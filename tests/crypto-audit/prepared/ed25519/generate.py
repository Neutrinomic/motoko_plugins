#!/usr/bin/env python3
"""Public prepared-key checks from the already pinned independent Ed25519 corpus."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OLD = ROOT/'tests/crypto-audit/round3/ed25519'


def blob(hexadecimal):
    return '"'+''.join('\\'+hexadecimal[index:index+2] for index in range(0, len(hexadecimal), 2))+'"'


def main():
    (HERE/'run').mkdir(parents=True, exist_ok=True)
    (HERE/'fail').mkdir(exist_ok=True)
    prefix = ('//MOC-FLAG --plugin ../../../../../dist/ed25519 --package fast ../../../../../packages/fast/src --sanity-checks\n'
              'import Ed "mo:fast/Ed25519";\n')
    corpus = json.loads((OLD/'vectors/cases.json').read_text())['cases']
    checker = '''
func check(key : Blob, message : Blob, signature : Blob, expected : Ed.Result<Bool>) {
  assert Ed.verify(key, message, signature) == expected;
  switch (Ed.preparePublicKey(key)) {
    case (#err error) { assert #err(error) == expected };
    case (#ok prepared) {
      assert Ed.verifyPrepared(prepared, message, signature) == expected;
      // Preparing another key cannot replace the first key's verification table.
      switch (Ed.preparePublicKey("\\d7\\5a\\98\\01\\82\\b1\\0a\\b7\\d5\\4b\\fe\\d3\\c9\\64\\07\\3a\\0e\\e1\\72\\f3\\da\\a6\\23\\25\\af\\02\\1a\\68\\f7\\07\\51\\1a")) {
        case (#ok other) { assert Ed.verifyPrepared(other,"","") == #err(#invalidSignature) };
        case (_) assert false;
      };
      assert Ed.verifyPrepared(prepared, message, signature) == expected;
    };
  }
};
'''
    for group, rows in [('wycheproof', corpus[:151]), ('adversarial', corpus[151:])]:
        text = prefix+checker
        for row in rows:
            result = row['expected']
            expected = '#ok('+result+')' if result in ('true', 'false') else '#err(#'+result+')'
            text += f'// {row["name"]}\ncheck({blob(row["publicKey"])},{blob(row["message"])},{blob(row["signature"])},{expected});\n'
        (HERE/'run'/f'{group}.mo').write_text(text)

    signing = []
    paths = [ROOT/'benchmarks/crypto/round3/ed25519/fixtures'/name for name in ('rfc8032.json', 'openssl.json')]
    for path in paths:
        signing.extend(json.loads(path.read_text())['vectors'])
    text = prefix+'''import Prim "mo:⛔";
func sk(seed : Blob) : Ed.PreparedSecretKey {
  switch (Ed.prepareSecretKey(seed)) { case (#ok key) key; case (_) { assert false; loop {} } }
};
func pk(raw : Blob) : Ed.PreparedPublicKey {
  switch (Ed.preparePublicKey(raw)) { case (#ok key) key; case (_) { assert false; loop {} } }
};
'''
    for index, vector in enumerate(signing):
        text += f'// {vector["name"]}\n'
        text += f'let secret{index} = sk({blob(vector["seed"])});\n'
        text += f'let public{index} = pk({blob(vector["publicKey"])});\n'
        text += f'assert Ed.signPrepared(secret{index},{blob(vector["message"])}) == {blob(vector["signature"])};\n'
    # Reverse traversal reuses objects after many intervening preparations.
    for index, vector in reversed(list(enumerate(signing))):
        text += f'assert Ed.verifyPrepared(public{index},{blob(vector["message"])},Ed.signPrepared(secret{index},{blob(vector["message"])})) == #ok(true);\n'
    extra = json.loads((OLD/'vectors/openssl-extra.json').read_text())
    text += f'let seed : Blob = {blob(extra["seed"])};\nlet rawPublic : Blob = {blob(extra["publicKey"])};\n'
    text += 'let secret = sk(seed); let publicKey = pk(rawPublic);\n'
    text += 'let large = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(65_536,func(i) {Prim.natToNat8(i % 251)}));\n'
    for variable, vector in zip(['seed', 'rawPublic', 'large'], extra['vectors']):
        text += f'assert Ed.signPrepared(secret,{variable}) == {blob(vector["signature"])};\n'
        text += f'assert Ed.verifyPrepared(publicKey,{variable},{blob(vector["signature"])}) == #ok(true);\n'
    text += '''
for (size in [0,1,31,33,64,96].values()) {
  let malformed = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size,func(_){0}));
  switch (Ed.prepareSecretKey(malformed)) { case (#err(#invalidSecretKey)) {}; case (_) assert false };
};
assert Ed.verifyPrepared(publicKey,"","") == #err(#invalidSignature);
let aliases = [secret,secret];
let publicAliases = [publicKey,publicKey];
assert Ed.signPrepared(aliases[0],large) == Ed.signPrepared(aliases[1],large);
assert Ed.verifyPrepared(publicAliases[0],large,Ed.signPrepared(aliases[1],large)) == #ok(true);
'''
    text += f'assert seed == {blob(extra["seed"])};\nassert rawPublic == {blob(extra["publicKey"])};\n'
    (HERE/'run/signing.mo').write_text(text)

    fails = {
        'blob-as-public': 'let forged : Blob = ""; let bad : Ed.PreparedPublicKey = forged;\n',
        'blob-as-secret': 'let forged : Blob = ""; let bad : Ed.PreparedSecretKey = forged;\n',
        'public-as-secret': 'func bad(key : Ed.PreparedPublicKey) : Blob { Ed.signPrepared(key, "") };\n',
        'secret-as-public': 'func bad(key : Ed.PreparedSecretKey) : Ed.Result<Bool> { Ed.verifyPrepared(key, "", "") };\n',
        'extract-secret-blob': 'func bad(key : Ed.PreparedSecretKey) : Blob { key };\n',
        'stable-handle': 'persistent actor { var key : ?Ed.PreparedPublicKey = null };\n',
        'shared-handle': 'persistent actor { public query func bad(key : Ed.PreparedSecretKey) : async Bool { true } };\n',
        'candid-handle': 'func bad(key : Ed.PreparedSecretKey) : Blob { to_candid(key) };\n',
        'show-handle': 'func bad(key : Ed.PreparedSecretKey) : Text { debug_show(key) };\n',
    }
    for name, body in fails.items():
        (HERE/'fail'/f'{name}.mo').write_text(prefix+body)
    sources = [OLD/'vectors/cases.json',OLD/'vectors/openssl-extra.json',*paths]
    (HERE/'provenance.json').write_text(json.dumps({
        'verification_cases':len(corpus), 'signing_vectors':len(signing)+3, 'nominal_rejections':len(fails),
        'input_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
        'generated_sha256':{str(path.relative_to(HERE)):hashlib.sha256(path.read_bytes()).hexdigest()
                            for directory in ('run','fail') for path in sorted((HERE/directory).glob('*.mo'))}
    },indent=2)+'\n')


if __name__ == '__main__':
    main()
