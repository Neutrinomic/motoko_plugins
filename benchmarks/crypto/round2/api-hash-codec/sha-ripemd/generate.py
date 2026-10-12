#!/usr/bin/env python3
"""Per-call SHA and RIPEMD fixtures; independent expected bytes use hashlib."""
from pathlib import Path
import hashlib
import json
import sys

HERE = Path(__file__).resolve().parent
CRYPTO = HERE.parents[2]
ROOT = CRYPTO.parents[1]
sys.path.insert(0, str(CRYPTO))
from common import actor, blob

cases = []
rows = []
existing = json.loads((CRYPTO / 'all-cases.json').read_text())['cases']

def digest(algorithm, data):
    return hashlib.new(algorithm, data).digest()

def pattern(size):
    return bytes(i % 251 for i in range(size))

def ref(case):
    return {k: case[k] for k in ['name', 'implementation', 'source']}

def inventory(module, function, workload, size, plugin_case, native_case, notes=''):
    rows.append({
        'id': f'{module}.{function}:{workload}:{size}', 'module': module,
        'function': function, 'public_function': f'{module}.{function}',
        'workload': workload, 'size': size,
        'plugin_case': ref(plugin_case),
        'native_case': ref(native_case) if native_case else None,
        'notes': notes,
        'source_module': f'packages/fast/src/{module}.mo',
    })

def emit(name, module, implementation, source, expected, notes=''):
    plugin = {'SHA512': 'sha512', 'RIPEMD160': 'ripemd160'}[module]
    path = HERE / 'cases' / name / implementation / 'main.mo'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source)
    case = {
        'name': name, 'family': plugin, 'implementation': implementation,
        'comparison': 'isolated-public-method',
        'plugins': [plugin] if implementation == 'native' else [],
        'expected_hex': expected.hex(), 'notes': notes,
        'source': path.relative_to(CRYPTO).as_posix(),
        'oracle': 'Python hashlib / OpenSSL, independent of both Motoko implementations',
    }
    cases.append(case)
    return case

# Reuse the complete existing one-shot size sweep without duplicating sources.
for module, function, prefix in [
    ('SHA256', 'digest', 'sha256'), ('SHA512', 'digest', 'sha512'),
    ('SHA512', 'digest384', 'sha384'), ('RIPEMD160', 'digest', 'ripemd160'),
]:
    for size in [0, 32, 64, 1024, 16384]:
        cohort = [c for c in existing if c['name'] == f'{prefix}-{size}']
        plugin_case = next(c for c in cohort if c['implementation'] == 'native')
        native_case = next(c for c in cohort if not c['plugins'])
        inventory(module, function, 'one-shot', size, plugin_case, native_case,
                  'Existing exact-output one-shot fixture. ' + native_case.get('notes', ''))

# A class operation is the only operation in the measured interval. State setup
# and result inspection happen in configure / bytesResult, respectively.
for module, algorithm, cls, pure_import, pure_constructor in [
    ('SHA512', 'sha512', 'Digest', 'sha2/Sha512', 'H.Digest(#sha512)'),
    ('SHA512', 'sha384', 'Digest384', 'sha2/Sha512', 'H.Digest(#sha384)'),
    ('RIPEMD160', 'ripemd160', 'Digest', 'bitcoin/Ripemd160', 'H.Digest()'),
]:
    for method, sizes in [('constructor', [0]), ('write', [32, 1024]),
                          ('sum', [32, 1024]), ('reset', [1024])]:
        for size in sizes:
            name = f'api-{algorithm}-{cls.lower()}-{method}-{size}'
            expected = digest(algorithm, pattern(size) if method in ['write', 'sum'] else b'')
            pair = []
            common_notes = (
                'Only the named call and result assignment are timed; input/state preparation '
                'and output verification are outside counters. '
            )
            for impl in ['native', 'mops-sha2' if module == 'SHA512' else 'mops-bitcoin']:
                if module == 'RIPEMD160' and method == 'sum' and impl != 'native':
                    continue
                fast = impl == 'native'
                constructor = f'H.{cls}()' if fast else pure_constructor
                imp = f'import H "mo:{"fast/" + module if fast else pure_import}";'
                declarations = (f'transient let input : Blob = {blob(pattern(size))};\n'
                                f'transient var state = {constructor};')
                configure = f'state := {constructor};'
                write = ('ignore state.write(input)' if module == 'RIPEMD160' and fast else
                         'state.write(Prim.blobToArray(input))' if module == 'RIPEMD160' else
                         'state.write(input)' if fast else 'state.writeBlob(input)')
                sum_expr = 'state.sum()' if fast or module == 'SHA512' else 'Prim.arrayToBlob(state.sum())'
                notes = common_notes
                if method == 'constructor':
                    operation, query = f'state := {constructor};', sum_expr
                elif method == 'write':
                    operation, query = write + ';', sum_expr
                    if module == 'RIPEMD160' and not fast:
                        notes += 'Required public Blob-to-array input conversion is included.'
                elif method == 'reset':
                    configure += write + ';'
                    operation, query = 'state.reset();', sum_expr
                    notes += 'Reset a stream after 1024 bytes; query checks the empty-message digest.'
                else:
                    configure += write + ';'
                    operation, query = 'result := state.sum();', 'assert state.sum() == result; result'
                    if not fast:
                        declarations += (f'\nfunc sumPreserving() : Blob {{\n'
                                         f'  let copy = {constructor};\n'
                                         '  copy.unshare(state.share());\n'
                                         '  copy.sum()\n};')
                        operation = 'result := sumPreserving();'
                        notes += ('The pure Motoko sum mutates its receiver. The timed adapter constructs '
                                  'a clone with share/unshare and sums it, preserving the original state '
                                  'like the plugin API. Query checks that original state still hashes identically.')
                    else:
                        notes += 'Query repeats sum to verify the measured sum preserved the stream.'
                pair.append(emit(name, module, impl,
                                 actor(imp, declarations, configure, operation, query), expected, notes))
            function = cls if method == 'constructor' else f'{cls}.{method}'
            inventory(module, function, method, size, pair[0], pair[1] if len(pair) > 1 else None,
                      common_notes + ('Bitcoin RIPEMD Digest.sum consumes and locks state; no public clone/share '
                                      'operation exists, so no equivalent non-destructive native Motoko '
                                      'counterpart is claimed.' if len(pair) == 1 else pair[1]['notes']))

# Immutable RIPEMD state functions have no corresponding public immutable-state
# interface in bitcoin/Ripemd160. Keep the original state live and inspect it
# outside the counter interval to verify the non-consuming contract.
for method, sizes in [('init', [0]), ('update', [32, 1024]), ('finalize', [32, 1024])]:
    for size in sizes:
        name = f'api-ripemd160-{method}-{size}'
        data = pattern(size)
        prefix = pattern(17) if method == 'update' else b''
        declarations = (f'transient let input : Blob = {blob(data)};\n'
                        'transient var state : Blob = "";\n'
                        'transient var next : ?Blob = null;\n'
                        'func unwrap(value : ?Blob) : Blob { switch value { case (?v) v; case null Prim.trap("invalid state"); } };')
        configure = 'state := H.init();'
        if method == 'init':
            operation, query = 'state := H.init();', 'unwrap(H.finalize(state))'
            expected = digest('ripemd160', b'')
        elif method == 'update':
            configure += f'state := unwrap(H.update(state, {blob(prefix)}));'
            operation = 'next := H.update(state, input);'
            query = (f'assert unwrap(H.finalize(state)) == {blob(digest("ripemd160", prefix))}; '
                     'unwrap(H.finalize(unwrap(next)))')
            expected = digest('ripemd160', prefix + data)
        else:
            configure += 'state := unwrap(H.update(state, input));'
            operation = 'next := H.finalize(state);'
            query = 'assert H.finalize(state) == next; unwrap(next)'
            expected = digest('ripemd160', data)
        notes = ('Only the named raw-state call and result assignment are timed; state construction and '
                 'digest inspection are excluded. Bitcoin RIPEMD has no public immutable-state equivalent. '
                 + ('Update appends to a prepared 17-byte prefix; query also verifies the original state.'
                    if method == 'update' else ''))
        case = emit(name, 'RIPEMD160', 'native',
                    actor('import H "mo:fast/RIPEMD160";', declarations, configure, operation, query), expected, notes)
        inventory('RIPEMD160', method, 'immutable-state-' + method, size, case, None, notes)

(HERE / 'cases.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
(HERE / 'inventory.json').write_text(json.dumps({
    'api_rows': rows,
    'module_source_sha256': {
        module: hashlib.sha256((ROOT / '_build/crypto-optimization-round2/baseline/packages/fast/src' / (module + '.mo')).read_bytes()).hexdigest()
        for module in ['SHA256', 'SHA512', 'RIPEMD160']
    },
    'callable_count': len({row['public_function'] for row in rows}),
    'new_case_count': len(cases),
    'oracle': 'Python hashlib / OpenSSL, independent of both Motoko implementations',
}, indent=2) + '\n')
print(f'{len(cases)} new fixtures; {len(rows)} inventory rows; {len(set(r["public_function"] for r in rows))} callables')
