#!/usr/bin/env python3
"""Generate byte-oriented Mops ECDSA counterparts from frozen independent fixtures."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2]
FIXTURE = BENCH / 'round2/curve-hotspots/fixtures/curve-inputs.json'
INPUTS = {row['name']: row for row in json.loads(FIXTURE.read_text())['cases']}


def blob(value):
    return '"' + ''.join('\\%02x' % b for b in bytes.fromhex(value)) + '"'


HELPERS = r'''
  type Result<T> = {#ok : T; #err : Text};
  func number(bytes : [Nat8], start : Nat, length : Nat) : Nat {
    var value = 0; var i = start;
    while (i < start + length) { value := value * 256 + Prim.nat8ToNat(bytes[i]); i += 1 };
    value
  };
  func parseKey(key : Blob) : Result<E.PublicKey> {
    let bytes = Prim.blobToArray(key);
    if (bytes.size() != 33 and bytes.size() != 65) return #err("invalid public key length");
    if (not ((bytes.size() == 33 and (bytes[0] == 2 or bytes[0] == 3)) or
      (bytes.size() == 65 and bytes[0] == 4))) return #err("invalid SEC1 prefix");
    E.publicKeyFromBytes(key.vals(), #raw({curve}))
  };
  func parseCompact(signature : Blob) : Result<E.Signature> {
    if (signature.size() != 64) return #err("invalid compact length");
    let bytes = Prim.blobToArray(signature);
    let r = number(bytes, 0, 32); let s = number(bytes, 32, 32);
    if (r == 0 or r >= curve.params.r or s == 0 or s >= curve.params.r)
      return #err("invalid signature scalar");
    #ok(E.Signature(r, s, curve))
  };
  func publicKey(secret : Blob, compressed : Bool) : Result<Blob> {
    if (secret.size() != 32) return #err("invalid secret key length");
    switch (E.privateKeyFromBytes(secret.vals(), #raw({curve}))) {
      case (#err(error)) #err(error);
      case (#ok(key)) #ok(Prim.arrayToBlob(key.getPublicKey().toBytes(
        if (compressed) #compressed else #uncompressed)));
    }
  };
  func convertPublicKey(key : Blob, compressed : Bool) : Result<Blob> {
    switch (parseKey(key)) {
      case (#err(error)) #err(error);
      case (#ok(key)) #ok(Prim.arrayToBlob(key.toBytes(
        if (compressed) #compressed else #uncompressed)));
    }
  };
  func verifyPrehash(key : Blob, digest : Blob, signature : Blob) : Result<Bool> {
    let publicKey = switch (parseKey(key)) {
      case (#err(error)) return #err(error); case (#ok(value)) value;
    };
    if (digest.size() != 32) return #err("invalid digest length");
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(publicKey.verifyHashed(digest.vals(), value));
    }
  };
  func signatureToDer(signature : Blob) : Result<Blob> {
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(Prim.arrayToBlob(value.toBytes(#der)));
    }
  };
  func signatureFromDer(der : Blob) : Result<Blob> {
    let bytes = Prim.blobToArray(der); let size = bytes.size();
    if (size < 8 or size > 72) return #err("invalid DER length");
    if (bytes[0] != 0x30 or Prim.nat8ToNat(bytes[1]) != size - 2 or bytes[2] != 2)
      return #err("invalid DER sequence");
    let rSize = Prim.nat8ToNat(bytes[3]);
    if (rSize == 0 or rSize > 33 or rSize + 6 > size) return #err("invalid DER R length");
    if (bytes[4] >= 128 or (rSize > 1 and bytes[4] == 0 and bytes[5] < 128))
      return #err("nonminimal or negative DER R");
    let sTag = 4 + rSize;
    if (bytes[sTag] != 2) return #err("invalid DER S tag");
    let sSize = Prim.nat8ToNat(bytes[sTag + 1]); let sStart = sTag + 2;
    if (sSize == 0 or sSize > 33 or sStart + sSize != size) return #err("invalid DER S length");
    if (bytes[sStart] >= 128 or (sSize > 1 and bytes[sStart] == 0 and bytes[sStart + 1] < 128))
      return #err("nonminimal or negative DER S");
    let r = number(bytes, 4, rSize); let s = number(bytes, sStart, sSize);
    if (r == 0 or r >= curve.params.r or s == 0 or s >= curve.params.r)
      return #err("invalid DER signature scalar");
    switch (E.signatureFromBytes(der.vals(), curve, #der)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(Prim.arrayToBlob(value.toBytes(#raw)));
    }
  };
  func normalizeSignature(signature : Blob) : Result<Blob> {
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) {
        // Use the exact mathematical half-order: P-256's package rHalf uses floor,
        // but Signature's constructor compares with < rather than <=.
        let s = if (value.original_s > curve.params.r / 2)
          curve.params.r - value.original_s else value.original_s;
        #ok(Prim.arrayToBlob(E.Signature(value.original_r, s, curve).toBytes(#raw)))
      };
    }
  };
'''


def actor(kind, row, operation):
    declarations = '\n  '.join(f'transient let {name} : Blob = {blob(value)};'
                               for name, value in row['inputs'].items())
    typ = row['result_type']
    initial = 'false' if typ == 'Bool' else '""'
    actual = 'if (value) "\\01" else "\\00"' if typ == 'Bool' else 'value'
    return f'''// Generated by round2/api-curves/pure/generate-ecdsa.py. Do not edit.
import Prim "mo:prim";
import E "mo:ecdsa";
persistent actor {{
  transient let curve = E.Curve(#{kind});
{HELPERS}
  {declarations}
  transient var result : Result<{typ}> = #ok({initial});
  public func configure() : async () {{}};
  public func run() : async {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}} {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := {operation};
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = stop-start; allocated = allocatedAfter-allocatedBefore;
      reclaimed = reclaimedAfter-reclaimedBefore; outputSize = 0}}
  }};
  public query func bytesResult() : async Blob {{
    let #ok(value) = result else Prim.trap("unexpected pure Motoko error");
    let actual : Blob = {actual};
    assert actual == {blob(row['expected_hex'])};
    actual
  }};
}}
'''


def main():
    cases = []; mapping = []
    common = [
        ('publicKey', 'public-key-uncompressed', 'publicKey(secret, false)'),
        ('derivePublicKey', 'public-key-uncompressed', 'publicKey(secret, true)'),
        ('convertPublicKey', 'convert-compressed-to-uncompressed', 'convertPublicKey(key, false)'),
        ('verifyPrehash', 'verify-compressed-low-s', 'verifyPrehash(key, digest, signature)'),
        ('signatureToDer', 'der-encode-ordinary', 'signatureToDer(signature)'),
        ('signatureFromDer', 'der-decode-ordinary', 'signatureFromDer(der)'),
        ('normalizeSignature', 'normalize-high-s', 'normalizeSignature(signature)'),
    ]
    for family, module, kind in [('secp256k1', 'Secp256k1', 'secp256k1'), ('p256', 'P256', 'prime256v1')]:
        selections = list(common)
        if family == 'secp256k1':
            selections += [
                ('compressPublicKey', 'convert-uncompressed-to-compressed', 'convertPublicKey(key, true)'),
                ('decompressPublicKey', 'convert-compressed-to-uncompressed', 'convertPublicKey(key, false)'),
            ]
        for api, suffix, operation in selections:
            fixture_name = f'r2-{family}-{suffix}'
            row = dict(INPUTS[fixture_name])
            plugin_case = fixture_name
            if api == 'derivePublicKey':
                row['expected_hex'] = INPUTS[f'r2-{family}-convert-compressed-to-compressed']['expected_hex']
                plugin_case = f'api-{family}-{api}-fast'
            if api in ('compressPublicKey', 'decompressPublicKey'):
                plugin_case = f'api-{family}-{api}-fast'
            name = f'api-{family}-{api}-ecdsa'
            target = HERE / 'ecdsa' / name / 'main.mo'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(actor(kind, row, operation))
            note = ('Byte-oriented composition of pinned ecdsa@8.0.1 APIs. Input decoding, '
                    'strict length/range validation, operation, SEC1/DER/compact serialization and '
                    'array-to-Blob conversion are measured. Only reusable curve construction and '
                    'immutable input literals are outside timing. Fixture comes from the independent '
                    'frozen curve oracle; no plugin outputs were used. Typed error text differs from '
                    'the native API; comparison is for this valid input.')
            if api == 'verifyPrehash':
                note += (' ecdsa Signature normalizes S before verifyHashed; this low-S fixture '
                         'has identical ECDSA semantics. Package P-256 has a half-order boundary '
                         'quirk, so this row does not assert complete validation equivalence.')
            if api == 'signatureFromDer':
                note += (' Strict DER framing/minimal-positive-integer and scalar-range guards '
                         'precede the package ASN.1 decoder, whose raw acceptance is more permissive.')
            if api == 'normalizeSignature':
                note += (' Scalar min(S,n-S) is composed explicitly around E.Signature serialization '
                         'to preserve the precise half-order boundary for both curves.')
            if api in ('publicKey', 'derivePublicKey'):
                note += (' The pure Motoko key multiplication is variable-time; this is a mathematical '
                         'output comparison and does not assert the native secret operation and this '
                         'reference have equivalent side-channel properties.')
            comparison = plugin_case.removesuffix('-fast') if plugin_case.startswith('api-') else plugin_case
            entry = dict(name=name, family=family, implementation='ecdsa', comparison=comparison,
                         plugins=[], source=target.relative_to(BENCH).as_posix(),
                         expected_hex=row['expected_hex'], notes=note,
                         api=f'{module}.{api}', plugin_case=plugin_case, fixture_case=fixture_name)
            cases.append(entry)
            mapping.append({k: entry[k] for k in ('api', 'name', 'implementation', 'plugin_case', 'fixture_case')})
    for family, module in [('secp256k1', 'Secp256k1'), ('p256', 'P256')]:
        for api in (['signPrehash', 'schnorrSign', 'schnorrVerify'] if family == 'secp256k1' else ['signPrehash']):
            mapping.append(dict(api=f'{module}.{api}', name=None, implementation=None,
                                reason=('Neither pinned ecdsa@8.0.1 nor bitcoin@0.2.1 supplies RFC6979 nonce '
                                        'derivation or BIP340 signing/verification. Supplied-nonce ECDSA signing '
                                        'is not a semantically equivalent operation.')))
    (HERE / 'ecdsa-cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    (HERE / 'ecdsa-mapping.json').write_text(json.dumps(mapping, indent=2) + '\n')
    counterparts = {
        'publicKey': 'E.privateKeyFromBytes(#raw) -> PrivateKey.getPublicKey -> PublicKey.toBytes(#uncompressed)',
        'derivePublicKey': 'E.privateKeyFromBytes(#raw) -> PrivateKey.getPublicKey -> PublicKey.toBytes(#compressed)',
        'convertPublicKey': 'E.publicKeyFromBytes(#raw) -> PublicKey.toBytes(#uncompressed)',
        'compressPublicKey': 'E.publicKeyFromBytes(#raw) -> PublicKey.toBytes(#compressed)',
        'decompressPublicKey': 'E.publicKeyFromBytes(#raw) -> PublicKey.toBytes(#uncompressed)',
        'verifyPrehash': 'E.publicKeyFromBytes(#raw) + E.Signature -> PublicKey.verifyHashed',
        'signatureToDer': 'Validated compact scalar decoding -> E.Signature.toBytes(#der)',
        'signatureFromDer': 'Strict DER guards -> E.signatureFromBytes(#der) -> Signature.toBytes(#raw)',
        'normalizeSignature': 'Validated compact scalar decoding -> min(S,n-S) -> E.Signature.toBytes(#raw)',
    }
    by_api = {}
    cases_by_name = {c['name']: c for c in cases}
    for row in mapping:
        if row['name'] is None:
            by_api[row['api']] = dict(native_case=None, notes=row['reason'], counterpart_api=None)
        else:
            c = cases_by_name[row['name']]
            by_api[row['api']] = dict(
                native_case=dict(name=c['name'], implementation=c['implementation']),
                plugin_case=dict(name=c['plugin_case'], implementation='fast'),
                notes=c['notes'], counterpart_api=counterparts[row['api'].split('.')[1]])
    (HERE / 'ecdsa-mappings.json').write_text(json.dumps(by_api, indent=2) + '\n')
    (HERE / 'ecdsa-provenance.json').write_text(json.dumps({
        'generator': str(Path(__file__).relative_to(BENCH)),
        'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'fixture': str(FIXTURE.relative_to(BENCH)),
        'fixture_sha256': hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
        'case_count': len(cases),
        'expected_bytes_origin': 'Existing independent affine-Python frozen fixture, never plugin outputs',
    }, indent=2) + '\n')
    print(f'Generated {len(cases)} pure ECDSA cases')


if __name__ == '__main__':
    main()
