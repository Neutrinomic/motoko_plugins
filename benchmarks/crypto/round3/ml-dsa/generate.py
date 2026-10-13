#!/usr/bin/env python3
"""Generate ML-DSA public API cases from pinned NIST ACVP external vectors."""
import json
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
CRYPTO = HERE.parents[1]
ROOT = CRYPTO.parents[1]
sys.path.insert(0, str(CRYPTO))
from common import actor, blob, save_case
vectors = json.loads((ROOT / 'plugins/ml-dsa/tests/vectors/acvp-ml-dsa-44.json').read_text())
cases = []
for tc_id in [4, 6, 11, 362, 373]:
    vector = next(v for v in vectors['sigGen'] if v['tcId'] == tc_id)
    declarations = '\n'.join(f'transient let {key} : Blob = {blob(vector[key])};' for key in ['seed', 'pk', 'message', 'context', 'rnd', 'signature'])
    declarations += '\nfunc unwrap<T>(value : H.Result<T>) : T { switch(value) { case (#ok x) x; case (#err e) Prim.trap(debug_show(e)) } };'
    for operation in ['public-key', 'sign', 'verify']:
        if operation == 'public-key' and tc_id != 4:
            continue
        if operation == 'public-key':
            expr = 'H.publicKey(seed)'
            expected = vector['pk']
            result_type, initial, normalized = 'Blob', '""', 'result'
        elif operation == 'sign':
            expr = 'H.sign(seed, message, context)' if vector['deterministic'] else 'H.signRandomized(seed, message, context, rnd)'
            expected = vector['signature']
            result_type, initial, normalized = 'Blob', '""', 'result'
        else:
            expr = 'H.verify(pk, message, signature, context)'
            expected = '01'
            result_type, initial, normalized = 'Bool', 'false', 'if (result) "\\01" else "\\00"'
        name = f'mldsa-{operation}-acvp-{tc_id}'
        case = {'name': name, 'family': 'ml-dsa', 'implementation': 'native', 'comparison': 'blob-public-api', 'plugins': ['ml-dsa'], 'expected_hex': expected.lower(),
            'notes': f"FIPS204-tr1 ACVP tcId {tc_id}: message {len(vector['message'])//2} B, context {len(vector['context'])//2} B; public signing includes full seed expansion; no precomputed private key.",
            'operation': operation, 'message_bytes': len(vector['message'])//2, 'context_bytes': len(vector['context'])//2, 'deterministic': vector['deterministic']}
        source = actor('import H "mo:fast/MLDSA";', declarations, '', f'result := unwrap({expr});', normalized, result_type, initial)
        cases.append(save_case(case, source, 'round3/ml-dsa/cases'))
(HERE / 'cases.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
print(f'Generated {len(cases)} independent-oracle ML-DSA cases.')
