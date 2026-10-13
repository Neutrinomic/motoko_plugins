#!/usr/bin/env python3
"""Additional bridge regression: eager argument effects, aliases and GC roots."""
import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location('vectors', HERE / 'generate.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--core', type=Path, required=True)
    args = parser.parse_args()
    plugin, out = args.plugin.resolve(), args.out.resolve()
    (out / 'run').mkdir(parents=True, exist_ok=True)
    key = v.encoded(v.multiply(1))
    digest = bytes(32)
    sig = v.audit.sign(v.curve, 1, digest, True)
    schnorr = v.schnorr(1, digest, digest)
    xonly = key[1:]
    text = v.audit.flags('secp256k1', plugin)
    for name, data in [('key',key),('digest',digest),('signature',sig),('xonly',xonly),('schnorr',schnorr)]:
        text += f'let {name} : Blob = {v.blob(data)};\n'
    text += '''
var sequence : Nat = 0;
func arg(n : Nat, value : Blob) : Blob { sequence := sequence * 10 + n; value };
assert Curve.verifyPrehash(arg(1,key),arg(2,digest),arg(3,signature)) == #ok(true);
assert sequence == 123;
sequence := 0;
assert Curve.verifyPrehash(arg(1,""),arg(2,""),arg(3,"")) == #err(#invalidPublicKey);
assert sequence == 123;
sequence := 0;
assert Curve.verifyPrehash(arg(1,key),arg(2,""),arg(3,"")) == #err(#invalidDigest);
assert sequence == 123;
sequence := 0;
assert Curve.verifyPrehash(arg(1,key),arg(2,digest),arg(3,"")) == #err(#invalidSignature);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrVerify(arg(1,xonly),arg(2,digest),arg(3,schnorr)) == #ok(true);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrVerify(arg(1,""),arg(2,digest),arg(3,"")) == #err(#invalidPublicKey);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrVerify(arg(1,xonly),arg(2,digest),arg(3,"")) == #err(#invalidSignature);
assert sequence == 123;
sequence := 0;
let alias = (do { sequence := sequence * 10 + 4; Curve.schnorrVerify });
assert alias(arg(1,xonly),arg(2,digest),arg(3,schnorr)) == #ok(true);
assert sequence == 4123;
sequence := 0;
let ecdsaAliases = [Curve.verifyPrehash, Curve.verifyPrehash];
let schnorrAliases = [Curve.schnorrVerify, alias];
assert ecdsaAliases[0](arg(1,key),arg(2,digest),arg(3,signature)) == #ok(true);
assert sequence == 123;
sequence := 0;
assert schnorrAliases[1](arg(1,xonly),arg(2,digest),arg(3,schnorr)) == #ok(true);
assert sequence == 123;
'''
    (out / 'run/audit-secp256k1-predicate-bridge.mo').write_text(text)
    # Reuse the existing complete nine-method Ash suite, retaining actual
    # predicate result variants alongside existing keys/signatures during its
    # GC test (which requires more than 16 MiB of confirmed reclamation).
    source = (ROOT / 'packages/fast/tests/ash/Secp256k1.mo').read_text()
    changes = {
        'import Cases "../lib/Secp256k1Tests";': 'import Cases "mo:cases/Secp256k1Tests";',
        '    tweakedSecret : Blob;': '    tweakedSecret : Blob;\n    verified : Secp.Result<Bool>;\n    invalid : Secp.Result<Bool>;\n    schnorrVerified : Secp.Result<Bool>;',
        '      secret; schnorrSecret; digest; auxiliary; key; signature; xOnly;': '      secret; schnorrSecret; digest; auxiliary; key; signature; xOnly;\n      verified = Secp.verifyPrehash(key, digest, signature);\n      invalid = Secp.verifyPrehash("", digest, signature);\n      schnorrVerified = Secp.schnorrVerify(xOnly, auxiliary, expectedSchnorr);',
        '      assert retained.secret == one and retained.schnorrSecret == three;': '      assert retained.verified == #ok(true);\n      assert retained.invalid == #err(#invalidPublicKey);\n      assert retained.schnorrVerified == #ok(true);\n      assert retained.secret == one and retained.schnorrSecret == three;',
    }
    for before, after in changes.items():
        assert source.count(before) == 1, before
        source = source.replace(before, after)
    (out / 'PredicateAsh.mo').write_text(source)
    config = {'mo': {'fast': str(ROOT / 'packages/fast/src'), 'core': str(args.core.resolve()),
                     'cases': str(ROOT / 'packages/fast/tests/lib')},
              'canisters': [{'name':'predicate_bridge', 'src':'PredicateAsh.mo',
                              'mocArgs':['--plugin',str(plugin),'--sanity-checks']}]}
    (out / 'Predicate.ash.json').write_text(json.dumps(config,indent=2)+'\n')

if __name__ == '__main__': main()
