#!/usr/bin/env python3
"""Emit prepared/direct actors using independently produced Ed25519 answers."""
import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--common', type=Path, default=HERE.parent / 'common.py')
a = parser.parse_args()
spec = importlib.util.spec_from_file_location('prepared_common', a.common)
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
fixtures = json.loads((HERE / 'fixtures.json').read_text())
cases = []

for fixture in fixtures['vectors']:
    fixture_id = fixture['name']
    for operation, handle, factory, payload in [
        ('sign', 'PreparedSecretKey', 'prepareSecretKey', 96),
        ('verify', 'PreparedPublicKey', 'preparePublicKey', 1056),
    ]:
        key_name = 'seed' if operation == 'sign' else 'key'
        result_type = 'Ed.Result<Blob>' if operation == 'sign' else 'Ed.Result<Bool>'
        direct_call = 'Ed.sign(seed, message)' if operation == 'sign' else 'Ed.verify(key, message, signature)'
        hot_call = '#ok(Ed.signPrepared(handle, message))' if operation == 'sign' else 'Ed.verifyPrepared(handle, message, signature)'
        # Signing hot calls return Blob directly; do not invent a Result wrapper
        # merely to normalize this benchmark's state representation.
        hot_type = 'Blob' if operation == 'sign' else result_type
        hot_init = '""' if operation == 'sign' else '#err(#invalidSignature)'
        hot_expr = 'Ed.signPrepared(handle, message)' if operation == 'sign' else hot_call
        modes = [('direct', 1), ('prepare', 1), ('prepared', 1)]
        if fixture_id == 'openssl-32':
            modes += [(mode, count) for count in [2, 10, 100] for mode in ['direct', 'prepared']]
        for mode, reuse in modes:
            name = f'ed25519-{operation}-{fixture_id}-{mode}-{reuse}'
            decls = f'''
  transient var seed : Blob = "";
  transient var key : Blob = "";
  transient var message : Blob = "";
  transient var signature : Blob = "";
  func must<T>(value : Ed.Result<T>) : T {{
    switch value {{ case (#ok result) result; case (#err _) Prim.trap("unexpected fixture error") }}
  }};'''
            configure = f'''seed := {common.blob(fixture['seed'])};
    key := {common.blob(fixture['publicKey'])};
    message := {common.blob(fixture['message'])};
    signature := {common.blob(fixture['signature'])};'''
            output_type, initial = result_type, '#err(#invalidSignature)'
            expression = 'must(result)' if operation == 'sign' else 'if (must(result)) "\\01" else "\\00"'
            if mode == 'direct':
                command = f'result := {direct_call};'
            elif mode == 'prepare':
                output_type, initial = f'Ed.Result<Ed.{handle}>', '#err(#invalidSignature)'
                command = f'result := Ed.{factory}({key_name});'
                check = 'Ed.signPrepared(must(result), message)' if operation == 'sign' else 'must(Ed.verifyPrepared(must(result), message, signature))'
                expression = check if operation == 'sign' else f'if ({check}) "\\01" else "\\00"'
            else:
                decls += f'\n  transient var prepared : ?Ed.{handle} = null;'
                configure += f'\n    prepared := ?must(Ed.{factory}({key_name}));'
                output_type, initial = hot_type, hot_init
                expression = 'result' if operation == 'sign' else expression
                command = f'result := {hot_expr};'
            if reuse > 1:
                command = f'var count = 0; while (count < {reuse}) {{ {command} count += 1 }};'
            if mode == 'prepared':
                command = 'let handle = switch prepared { case (?value) value; case null Prim.trap("configure first") };\n    ' + command
            source = common.actor('import Ed "mo:fast/Ed25519";', decls, configure, command,
                output_expr=expression, output_type=output_type, initial=initial, memory_metrics=True)
            path = HERE / 'cases' / name / 'main.mo'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("\n".join(line.rstrip() for line in source.splitlines()) + "\n")
            cases.append({
                'name': name, 'implementation': 'native', 'family': 'ed25519', 'plugins': ['ed25519'],
                'source': path.relative_to(HERE.parent.parent).as_posix(),
                'expected_hex': fixture['signature'] if operation == 'sign' else '01',
                'memory_metrics': True,
                'prepared': {
                    'scheme': 'ed25519', 'profile': 'pure Ed25519', 'operation': operation,
                    'fixture': fixture_id, 'fixture_source': 'prepared/ed25519/fixtures.json',
                    'comparison_group': f'ed25519-{operation}-{fixture_id}',
                    'mode': mode, 'reuse': reuse, 'payload_bytes': 0 if mode == 'direct' else payload,
                },
            })
(HERE / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
