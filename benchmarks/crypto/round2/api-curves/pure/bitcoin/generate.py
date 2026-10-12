#!/usr/bin/env python3
"""Generate byte-oriented Bitcoin 0.2.1 counterparts from frozen curve fixtures."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
CRYPTO = HERE.parents[3]
UPSTREAM = CRYPTO / 'round2/curve-hotspots/fixtures/curve-inputs.json'
NAMES = {
    'pointAdd': 'r2-secp256k1-point-add-compressed-distinct',
    'pointMultiply': 'r2-secp256k1-point-multiply-compressed',
    'baseMultiply': 'r2-secp256k1-base-multiply-full-width',
    'tweakPublicKey': 'r2-secp256k1-tweak-compressed-full-width',
    'xOnlyPublicKey': 'r2-secp256k1-x-only-compressed',
    'tweakXOnlyPublicKey': 'r2-secp256k1-tweak-x-only-public-full-width',
    'tweakXOnlySecretKey': 'r2-secp256k1-tweak-x-only-secret-even-y',
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def blob(hex_string):
    return '"' + ''.join('\\' + hex_string[i:i+2] for i in range(0, len(hex_string), 2)) + '"'

COMMON = '''
  type Error = { #invalidSecretKey; #invalidPublicKey; #invalidScalar; #pointAtInfinity };
  type Result<T> = { #ok : T; #err : Error };
  // Bitcoin's decoder reduces coordinates modulo p. Explicit bounds restore
  // canonical SEC1 input semantics before entering the pinned package decoder.
  func decodePoint(input : Blob) : Result<J.Point> {
    let data = Prim.blobToArray(input);
    if (data.size() != 33 and data.size() != 65) return #err(#invalidPublicKey);
    if (data.size() == 33 and data[0] != 2 and data[0] != 3) return #err(#invalidPublicKey);
    if (data.size() == 65 and data[0] != 4) return #err(#invalidPublicKey);
    if (Common.readBE256(data, 1) >= Curves.secp256k1.p) return #err(#invalidPublicKey);
    if (data.size() == 65 and Common.readBE256(data, 33) >= Curves.secp256k1.p) return #err(#invalidPublicKey);
    switch (J.fromBytes(data, Curves.secp256k1)) {
      case null #err(#invalidPublicKey);
      case (?point) { if (J.isInfinity(point)) #err(#invalidPublicKey) else #ok(point) };
    }
  };
  func decodeScalar(input : Blob, error : Error, allowZero : Bool) : Result<Nat> {
    if (input.size() != 32) return #err(error);
    let value = Common.readBE256(Prim.blobToArray(input), 0);
    if (value >= Curves.secp256k1.r or (value == 0 and not allowZero)) #err(error) else #ok(value)
  };
  func encodePoint(point : J.Point) : Result<Blob> {
    if (J.isInfinity(point)) #err(#pointAtInfinity)
    else #ok(Prim.arrayToBlob(J.toBytes(point, true)))
  };
'''

OPERATIONS = {
    'pointAdd': '''
    let p = switch (decodePoint(left)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    let q = switch (decodePoint(right)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    encodePoint(J.add(p, q))''',
    'pointMultiply': '''
    let p = switch (decodePoint(key)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    let s = switch (decodeScalar(scalar, #invalidScalar, true)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    encodePoint(J.mul(p, s))''',
    'baseMultiply': '''
    let s = switch (decodeScalar(scalar, #invalidScalar, true)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    encodePoint(J.mulBase(s, Curves.secp256k1))''',
    'tweakPublicKey': '''
    let p = switch (decodePoint(key)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    let t = switch (decodeScalar(tweak, #invalidScalar, true)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    encodePoint(J.add(p, J.mulBase(t, Curves.secp256k1)))''',
    'xOnlyPublicKey': '''
    let p = switch (decodePoint(key)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    #ok(Prim.arrayToBlob(J.toBytes(p, true).sliceToArray(1, 33)))''',
    'tweakXOnlyPublicKey': '''
    if (key.size() != 32) return #err(#invalidPublicKey);
    let data = Prim.blobToArray(key);
    if (Common.readBE256(data, 0) >= Curves.secp256k1.p) return #err(#invalidPublicKey);
    let t = switch (decodeScalar(tweak, #invalidScalar, true)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    switch (P2tr.tweakPublicKey(data, Curves.secp256k1.Fp(t))) {
      case (#err(message)) {
        if (message == "Tweaking produced an invalid public key") #err(#pointAtInfinity)
        else #err(#invalidPublicKey)
      };
      case (#ok(pk)) {
        let prefix : Nat8 = if (pk.is_even) 2 else 3;
        #ok(Prim.arrayToBlob(Array.tabulate<Nat8>(33, func(i) {
          if (i == 0) prefix else pk.bip340_public_key[i - 1]
        })))
      };
    }''',
    'tweakXOnlySecretKey': '''
    // Reference composition only: secret Nat/NAF arithmetic is variable-time.
    let d = switch (decodeScalar(secret, #invalidSecretKey, false)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    let t = switch (decodeScalar(tweak, #invalidScalar, true)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    let normalized : Nat = switch (J.toAffine(J.mulBase(d, Curves.secp256k1))) {
      case (#infinity(_)) return #err(#invalidSecretKey);
      case (#point(_, y, _)) { if (y.value % 2 == 0) d else Curves.secp256k1.r - d };
    };
    let sum = (normalized + t) % Curves.secp256k1.r;
    if (sum == 0) return #err(#pointAtInfinity);
    let bytes = VarArray.repeat<Nat8>(0, 32);
    Common.writeBE256(bytes, 0, sum);
    #ok(Prim.arrayToBlob(bytes.toArray()))''',
}

RECIPES = {
    'pointAdd': 'Canonical SEC1 checks; Jacobi.fromBytes on both keys; Jacobi.add; infinity check; Jacobi.toBytes(compressed).',
    'pointMultiply': 'Canonical SEC1/scalar checks; Jacobi.fromBytes; Jacobi.mul; infinity check; Jacobi.toBytes(compressed).',
    'baseMultiply': 'Canonical scalar checks; Jacobi.mulBase; infinity check; Jacobi.toBytes(compressed).',
    'tweakPublicKey': 'Composition: canonical SEC1/scalar checks; Jacobi.fromBytes; Jacobi.add(P, Jacobi.mulBase(t)); infinity check; compressed encoding.',
    'xOnlyPublicKey': 'Composition: canonical SEC1 checks; Jacobi.fromBytes; Jacobi.toBytes(compressed); remove parity prefix.',
    'tweakXOnlyPublicKey': 'P2tr.tweakPublicKey after canonical x/scalar bounds; reconstruct compressed SEC1 prefix from returned is_even plus x bytes.',
    'tweakXOnlySecretKey': 'Reference composition: validate secret/tweak; Jacobi.mulBase(secret); toAffine for parity; normalize d to even Y; add tweak modulo group order; reject zero; Common.writeBE256.',
}

def main():
    local = HERE / 'fixtures.json'
    if not local.exists():
        upstream = json.loads(UPSTREAM.read_text())
        selected = [row for row in upstream['cases'] if row['name'] in NAMES.values()]
        assert len(selected) == 7
        local.write_text(json.dumps({
            'upstream': str(UPSTREAM.relative_to(CRYPTO)),
            'upstream_sha256': sha(UPSTREAM),
            'oracle_source': upstream['oracle_source'],
            'oracle_sha256': upstream['oracle_sha256'],
            'cases': selected,
        }, indent=2) + '\n')
    fixtures = json.loads(local.read_text())
    rows = {row['name']: row for row in fixtures['cases']}
    manifest = []
    mapping = {}
    for api, name in NAMES.items():
        row = rows[name]
        declarations = '\n'.join(f'  transient let {key} : Blob = {blob(value)};' for key, value in row['inputs'].items())
        params = ', '.join(f'{key} : Blob' for key in row['inputs'])
        args = ', '.join(row['inputs'])
        source = f'''// Generated by round2/api-curves/pure/bitcoin/generate.py. Do not edit.
// Bitcoin 0.2.1 public API composition; all byte conversion and validation are timed.
import Prim "mo:prim";
import Array "mo:core/Array";
import VarArray "mo:core/VarArray";
import J "mo:bitcoin/ec/Jacobi";
import Curves "mo:bitcoin/ec/Curves";
import Common "mo:bitcoin/Common";
import P2tr "mo:bitcoin/bitcoin/P2tr";
persistent actor {{
{COMMON}
{declarations}
  transient var result : Result<Blob> = #ok("");
  func operation({params}) : Result<Blob> {{{OPERATIONS[api]}
  }};
  public func configure() : async () {{}};
  public func run() : async {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}} {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := operation({args});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = stop-start; allocated = allocatedAfter-allocatedBefore;
      reclaimed = reclaimedAfter-reclaimedBefore; outputSize = 0}}
  }};
  public query func bytesResult() : async Blob {{
    let #ok(actual) = result else Prim.trap("unexpected Bitcoin counterpart error");
    assert actual == {blob(row['expected_hex'])};
    actual
  }};
}}
'''
        target = HERE / 'cases' / name / 'main.mo'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source)
        caveat = ('Variable-time Motoko NAF multiplication and Nat arithmetic; reference composition for a fixed public test secret, not a constant-time signing implementation.'
                  if api == 'tweakXOnlySecretKey' else
                  'Valid-input API counterpart with canonical bounds restored in wrapper; Bitcoin Jacobian multiplication is variable-time.')
        item = {
            'name': name, 'family': 'secp256k1', 'implementation': 'mops-bitcoin-api',
            'comparison': name, 'plugins': [], 'source': str(target.relative_to(CRYPTO)),
            'expected_hex': row['expected_hex'], 'operations_per_sample': 1,
            'notes': 'Byte-oriented API counterpart: Blob decode, canonical validation, public package calls, result encoding and Blob construction are all measured. Result unwrap and expected comparison are outside measurement. ' + caveat,
            'fixture_provenance': 'Exact inputs/expected bytes copied from frozen independently computed curve-hotspots fixtures; no plugin outputs used as oracle.',
            'plugin_source_case': name, 'api': api,
        }
        manifest.append(item)
        mapping['Secp256k1.' + api] = {
            'api': api, 'family': 'secp256k1', 'plugin_source_case': name,
            'native_case': {'name': name, 'implementation': 'mops-bitcoin-api'},
            'plugin_case': {'name': name, 'implementation': 'fast'},
            'counterpart_api': RECIPES[api],
            'notes': item['notes'],
            'pure_source': item['source'], 'package': 'bitcoin@0.2.1',
            'kind': 'composed', 'recipe': RECIPES[api], 'caveats': caveat,
            'input_hex': row['inputs'], 'expected_hex': row['expected_hex'],
            'source_sha256': sha(target),
        }
    (HERE / 'cases.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (HERE / 'api-mapping.json').write_text(json.dumps(mapping, indent=2) + '\n')
    (HERE / 'provenance.json').write_text(json.dumps({
        'generator_sha256': sha(Path(__file__)), 'fixtures_sha256': sha(local),
        'upstream_fixture_sha256': fixtures['upstream_sha256'],
        'dependency_lock_sha256': sha(CRYPTO / 'dependencies/mops.lock'),
        'measurement': 'Blob input to typed Blob Result, including decode, validation, operation and encode. Immutable input constants and module initialization precede measurement.',
        'case_count': len(manifest),
    }, indent=2) + '\n')
    print(f'Generated {len(manifest)} Bitcoin API counterparts in {HERE}')

if __name__ == '__main__':
    main()
