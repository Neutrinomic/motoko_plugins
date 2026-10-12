#!/usr/bin/env python3
"""Audit direct function coverage and assemble curve API report rows.

Each row names an actual actor that directly calls the public function. Pure
Motoko peers are admitted only by the separate semantic mapping, never inferred
from equal output or operation names. Measurements are populated by the runner.
"""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
ROOT = BENCH.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifests = [BENCH/'curve-cases/cases.json', HERE.parent/'curve-hotspots/curve-cases.json', HERE/'gap-cases.json']
    all_cases = [case for path in manifests for case in json.loads(path.read_text())]
    lookup = {(case['name'], case['implementation']):case for case in all_cases}
    mapping_file = HERE/'pure/mappings.json'
    mappings = json.loads(mapping_file.read_text()) if mapping_file.exists() else {}
    rows, evidence = [], []
    selected = {
        'derivePublicKey':('gap', '32-byte secret; compressed SEC1 output', '32 bytes'),
        'compressPublicKey':('gap', 'Valid uncompressed SEC1 input', '65 bytes'),
        'decompressPublicKey':('gap', 'Valid compressed SEC1 input', '33 bytes'),
        'convertPublicKey':('convert-compressed-to-uncompressed', 'Valid compressed SEC1 to uncompressed', '33 bytes'),
        'publicKey':('public-key-uncompressed', 'Full-width secret; uncompressed SEC1 output', '32 bytes'),
        'pointAdd':('point-add-compressed-distinct', 'Compressed and uncompressed distinct points', '33 + 65 bytes'),
        'pointMultiply':('point-multiply-compressed', 'Compressed point and full-width scalar', '33 + 32 bytes'),
        'baseMultiply':('base-multiply-full-width', 'Generator times full-width scalar', '32 bytes'),
        'tweakPublicKey':('tweak-compressed-full-width', 'Compressed point plus full-width scalar times generator', '33 + 32 bytes'),
        'signPrehash':('sign', 'RFC6979 deterministic ECDSA of a SHA-256 digest', '32-byte secret + 32-byte digest'),
        'verifyPrehash':('verify-compressed-low-s', 'Valid compact low-S signature and compressed public key', '33 + 32 + 64 bytes'),
        'signatureToDer':('der-encode-ordinary', 'Compact low-S signature to minimal DER', '64 bytes'),
        'signatureFromDer':('der-decode-ordinary', 'Minimal DER to compact signature', '71 bytes'),
        'normalizeSignature':('normalize-high-s', 'Compact high-S to low-S signature', '64 bytes'),
        'xOnlyPublicKey':('x-only-compressed', 'Validate compressed SEC1 and extract X', '33 bytes'),
        'schnorrSign':('schnorr-sign-message-32', 'Official BIP340 vector 1, supplied auxiliary bytes', '32-byte message'),
        'schnorrVerify':('schnorr-verify-message-32', 'Official BIP340 vector 1, valid signature', '32-byte message + 64-byte signature'),
        'tweakXOnlyPublicKey':('tweak-x-only-public-full-width', 'Even-Y lift of X-only key plus full-width tweak', '32 + 32 bytes'),
        'tweakXOnlySecretKey':('tweak-x-only-secret-even-y', 'Full-width even-Y secret and tweak', '32 + 32 bytes'),
    }
    for family, module in [('secp256k1','Secp256k1'),('p256','P256')]:
        api_path = ROOT/'packages/fast/src'/f'{module}.mo'
        api_text = api_path.read_text()
        functions = re.findall(r'public (?:let|func) (\w+)', api_text)
        for function in functions:
            suffix, workload, size = selected[function]
            case_name = (f'api-{family}-{function}-fast' if suffix == 'gap' else
                         f'{family}_sign_rfc6979_fast' if suffix == 'sign' else
                         f'r2-{family}-{suffix}')
            case = lookup[(case_name, 'fast')]
            source = BENCH/case['source']
            assert re.search(r'\bC\.'+function+r'\(', source.read_text()), f'{module}.{function} is not directly called by {source}'
            ident = f'{module}.{function}'
            mapping = mappings.get(ident, {})
            if mapping.get('plugin_case'):
                assert mapping['plugin_case'] == {'name':case_name,'implementation':'fast'}, (ident,mapping)
            note = 'One direct public API call. Blob input construction and Result/output checks are outside measurement.'
            if function == 'signPrehash':
                note += ' Pinned Mops ecdsa accepts a supplied nonce and lacks RFC6979 nonce generation, so no equivalent pure-Motoko comparison is claimed.'
            if function.startswith('schnorr'):
                note += ' Pinned Mops ecdsa and bitcoin packages lack BIP340; pure-Motoko cell intentionally blank.'
            if mapping.get('notes'):
                note += ' '+mapping['notes']
            if function == 'signatureFromDer':
                # The two curves can produce different DER lengths.
                fixture = json.loads((HERE.parent/'curve-hotspots/fixtures/curve-inputs.json').read_text())
                record = next(x for x in fixture['cases'] if x['name']==case_name)
                size = f"{len(bytes.fromhex(record['inputs']['der']))} bytes"
            row = dict(id=ident,module=module,function=function,workload=workload,size=size,
                       plugin_case={'name':case_name,'implementation':'fast'},notes=note)
            if mapping.get('native_case'):
                row['native_case']=mapping['native_case']
            if mapping.get('counterpart_api'):
                row['counterpart_api']=mapping['counterpart_api']
            rows.append(row)
            evidence.append(dict(id=ident,public_module=api_path.relative_to(ROOT).as_posix(),
                                 public_module_sha256=digest(api_path),source=case['source'],source_sha256=digest(source),
                                 expected_hex=case['expected_hex'],direct_call_verified=True))
        assert len(functions)==len(set(functions))
    (HERE/'curve-api-rows.json').write_text(json.dumps({'api_rows':rows},indent=2)+'\n')
    (HERE/'curve-coverage.json').write_text(json.dumps({'api_count':len(rows),'directly_covered':len(evidence),
        'semantic_peer_mapping_complete':mapping_file.exists(), 'functions':evidence},indent=2)+'\n')
    print(f'{len(rows)} direct function rows, {sum("native_case" in r for r in rows)} matched pure-Motoko peers')


if __name__=='__main__':
    main()
