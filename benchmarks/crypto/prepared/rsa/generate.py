#!/usr/bin/env python3
"""RSA prepared-key cases using the shared preparation/reuse/heap protocol."""
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from common import actor, blob

fixture = json.loads((HERE / 'fixture.json').read_text())
inputs = '\n'.join(f'transient let {name} : Blob = {blob(fixture[field])};'
    for name, field in [('secret', 'privateKey'), ('publicKey', 'publicKey'),
                       ('message', 'message'), ('digest', 'digest'),
                       ('salt', 'salt'), ('signature', 'signature')])
cases = []
for operation, signing, prehash in [
    ('sign-prehash', True, True), ('verify-prehash', False, True),
    ('sign-message', True, False), ('verify-message', False, False),
]:
    base = 'sign' if signing else 'verify'
    method = base + ('Prehash' if prehash else '')
    factory = 'prepareSecretKey' if signing else 'preparePublicKey'
    kind = 'PreparedSecretKey' if signing else 'PreparedPublicKey'
    raw = 'secret' if signing else 'publicKey'
    payload = 1840 if signing else 824
    data = 'digest' if prehash else 'message'
    final = 'salt' if signing else 'signature'
    expected = fixture['signature'] if signing else '01'
    group = 'rsa3072-' + operation + '-openssl3072'
    modes = [('direct', 1), ('prepare', 1), ('prepared', 1)]
    if prehash:
        # Ten signatures fit one update message; one hundred are modeled in
        # the report instead of exceeding the normal instruction budget.
        for reuse in ([2, 10] if signing else [2, 10, 100]):
            modes += [('direct', reuse), ('prepared', reuse)]
    for mode, reuse in modes:
        name = f'{group}-{mode}-{reuse}'
        prepared_call = f'RSA.{method}Prepared(getKey(), {data}, {final})'
        direct_call = f'RSA.{method}({raw}, {data}, {final})'
        prepare = f'key := ?unwrap(RSA.{factory}({raw}))'
        setup = inputs + f'''
  transient var key : ?RSA.{kind} = null;
  func unwrap<T>(value : RSA.Result<T>) : T {{
    switch value {{ case (#ok x) x; case (#err _) Prim.trap("RSA benchmark error") }}
  }};
  func getKey() : RSA.{kind} {{
    switch key {{ case (?x) x; case null Prim.trap("RSA key not prepared") }}
  }};'''
        if mode == 'prepare':
            run = prepare
            output = f'let checked = unwrap({prepared_call}); ' + (
                'checked' if signing else 'if (checked) "\\01" else "\\00"')
        else:
            call = direct_call if mode == 'direct' else prepared_call
            assignment = f'result := unwrap({call})'
            run = assignment if reuse == 1 else f'var i = 0; while (i < {reuse}) {{ {assignment}; i += 1 }}'
            output = 'result' if signing else 'if (result) "\\01" else "\\00"'
        source = actor('import RSA "mo:fast/RSA";', setup,
            prepare if mode == 'prepared' else '', run + ';',
            output_expr=output, output_type='Blob' if signing else 'Bool',
            initial='""' if signing else 'false', memory_metrics=True)
        target = HERE / 'cases' / name / 'main.mo'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source)
        cases.append({
            'name': name, 'implementation': 'native', 'family': 'rsa',
            'plugins': ['rsa'], 'source': target.relative_to(HERE.parents[1]).as_posix(),
            'expected_hex': expected, 'memory_metrics': True,
            'prepared': {
                'scheme': 'rsa', 'profile': 'RSA3072/e65537/PSS-SHA256/MGF1SHA256/salt32',
                'operation': operation, 'fixture': 'openssl3072',
                'fixture_source': 'prepared/rsa/fixture.json', 'comparison_group': group,
                'mode': mode, 'reuse': reuse, 'payload_bytes': 0 if mode == 'direct' else payload,
            },
        })
(HERE / 'cases.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
print(f'{len(cases)} RSA cases generated')
