#!/usr/bin/env python3
"""Round-four Montgomery delta audit; prior RSA corpus/evidence stay read-only.

All keys are public test fixtures. Heavy stages require a coordinator slot.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import shutil
import struct
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PREVIOUS = ROOT / 'tests/crypto-audit/prepared/rsa'
OUT = HERE / '_out'
RUNTIME = ROOT / 'plugins/rsa/runtime'
VENDOR = RUNTIME / 'vendor/bearssl'
spec = importlib.util.spec_from_file_location('prepared_audit', PREVIOUS / 'audit.py')
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
previous.OUT = OUT


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    summary = previous.generate()
    upstream = json.loads((VENDOR / 'UPSTREAM.json').read_text())
    # Both independent whole-exponentiation oracles use the unchanged kernel,
    # rather than silently following the changed primitive in the candidate.
    sources = [
        ('int/i31_montmul.c', HERE / 'oracle/i31_montmul.c', 'original-montmul.c',
         {'br_i31_montymul': 'audit_upstream_montymul'}),
        ('int/i31_modpow.c', VENDOR / 'src/int/i31_modpow.c', 'original-modpow.c',
         {'br_i31_modpow': 'audit_upstream_modpow', 'br_i31_montymul': 'audit_upstream_montymul'}),
        ('int/i31_modpow2.c', VENDOR / 'src/int/i31_modpow2.c', 'original-modpow2.c',
         {'br_i31_modpow_opt': 'audit_upstream_modpow_opt', 'br_i31_montymul': 'audit_upstream_montymul'}),
        ('rsa/rsa_i31_pub.c', VENDOR / 'src/rsa/rsa_i31_pub.c', 'original-public.c',
         {'br_rsa_i31_public': 'audit_upstream_public', 'br_i31_modpow_opt': 'audit_upstream_modpow_opt'}),
    ]
    oracle_hashes = {}
    for name, path, target, replacements in sources:
        assert sha(path) == upstream['files']['src/' + name], name
        oracle_hashes[name] = sha(path)
        text = path.read_text()
        # Define symbol aliases before inner.h so declarations agree too.
        aliases = ''.join(f'#define {a} {b}\n' for a, b in replacements.items())
        (OUT / target).write_text(aliases + text)
    original_private = OUT / 'original8u.c'
    original_private.write_text('#define br_i31_modpow_opt audit_upstream_modpow_opt\n' + original_private.read_text())
    candidate = VENDOR / 'src/int/i31_montmul.c'
    (OUT / 'candidate.c').write_text('#define br_i31_montymul audit_candidate_montymul\n' + candidate.read_text())
    original_text = (HERE/'oracle/i31_montmul.c').read_text()
    candidate_text = candidate.read_text()
    def body(text):
        return text[text.index('\n{')+1:text.index('\n}\n')+2]
    expected_body = body(original_text)
    specialized = 'montymul_len(' in candidate_text
    if specialized:
        expected_body = expected_body.replace('size_t len, len4, u, v;', 'size_t len4, u, v;')
        expected_body = expected_body.replace('\tlen = (m[0] + 31) >> 5;\n', '')
    assert body(candidate_text) == expected_body, 'Unexpected arithmetic-body change'
    rng = random.Random(0x4A65537)
    bits_list = [2, 30, 31, 32, 62, 63, 123, 124, 125,
                 1519, 1520, 1536, 1550, 1551, 3069, 3070, 3072, 3100, 3101]
    records = []
    for bits in bits_list:
        limbs = (bits + 30) // 31
        header = bits // 31 * 32 + bits % 31
        moduli = [(1 << (bits-1)) | 1, (1 << bits)-1]
        moduli += [rng.getrandbits(bits) | (1 << (bits-1)) | 1 for _ in range(4)]
        for modulus in moduli:
            operands = [0, 1, modulus-1] + [rng.randrange(modulus) for _ in range(5)]
            for x in operands:
                for same in [False, True]:
                    y = x if same else rng.randrange(modulus)
                    expected = x * y * pow(1 << (31*limbs), -1, modulus) % modulus
                    values = [limbs, int(same)]
                    for n in [x, y, modulus, expected]:
                        values += [header] + [(n >> (31*k)) & 0x7fffffff for k in range(limbs)]
                    records.append(struct.pack('<' + 'I'*len(values), *values))
    (OUT / 'montgomery.bin').write_bytes(struct.pack('<I', len(records)) + b''.join(records))
    summary.update(raw_montgomery_cases=len(records), destination_orderings_per_case=4,
                   announced_bit_lengths=bits_list, upstream_kernel_hashes=oracle_hashes,
                   specialized_public_lengths=specialized,
                   normalized_arithmetic_body_sha256=hashlib.sha256(expected_body.encode()).hexdigest())
    return summary


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native', action='store_true')
    p.add_argument('--motoko', action='store_true')
    p.add_argument('--imports', action='store_true')
    p.add_argument('--cc', default='cc')
    p.add_argument('--moc', default='/srv/shared/code/motoko_experiments/prepared-crypto/sdk/bin/moc')
    p.add_argument('--plugin', type=Path, default=ROOT / 'dist/rsa')
    p.add_argument('--wasmtime', default='wasmtime')
    p.add_argument('--openssl', default='openssl')
    args = p.parse_args()
    summary = inputs()
    before = previous.source_hashes()
    report = {'fixtures': summary, 'source_hashes': before,
              'audit_sources': {str(x.relative_to(ROOT)): sha(x) for x in
                                [HERE/'audit.py', HERE/'driver.c', HERE/'montgomery.c',
                                 PREVIOUS/'audit.py', PREVIOUS/'driver.c']}}
    if args.native:
        sources = [x for x in sorted((VENDOR/'src').rglob('*.c')) if x.name != 'i31_montmul.c']
        flags = [args.cc, '-std=c11', '-O3', '-g', '-fno-strict-aliasing', '-fno-omit-frame-pointer',
                 '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                 '-DBR_MAX_RSA_SIZE=3072', '-DBR_MAX_RSA_FACTOR=1536',
                 '-I'+str(RUNTIME/'src'), '-I'+str(VENDOR/'inc'), '-I'+str(VENDOR/'src')]
        oracles = [OUT/x for x in ['original8u.c', 'original-montmul.c', 'original-modpow.c',
                                   'original-modpow2.c', 'original-public.c']]
        previous.run(flags + [HERE/'driver.c', HERE/'montgomery.c', OUT/'candidate.c',
                             *oracles, *sources, '-o', OUT/'driver'], 'native-build')
        for name in ['vectors', 'public', 'private']:
            print(previous.run([OUT/'driver', name, OUT/(name+'.bin')], 'native-'+name).decode(), end='')
        raw_sources = [VENDOR/'src/int/i31_sub.c', VENDOR/'src/int/i31_ninv31.c']
        previous.run(flags + ['-DAUDIT_RAW_MAIN', HERE/'montgomery.c', OUT/'candidate.c',
                             OUT/'original-montmul.c', *raw_sources, '-o', OUT/'raw'], 'raw-build')
        print(previous.run([OUT/'raw', OUT/'montgomery.bin'], 'raw').decode(), end='')
        report['native_asan_ubsan_O3'] = 'pass'
        report['native_compile_flags'] = flags
        report['native_compiler_sha256'] = sha(Path(shutil.which(args.cc) or args.cc).resolve())
        report['native_compiler_version'] = previous.run([args.cc, '--version'], 'cc-version').decode().splitlines()[0]
        report['native_binary_hashes'] = {name: sha(OUT/name) for name in ['driver', 'raw']}
        (OUT/'native-round4.json').write_text(json.dumps(report, indent=2)+'\n')
    if args.motoko or args.imports:
        sys.argv = [str(PREVIOUS/'audit.py'), '--moc', args.moc, '--plugin', str(args.plugin),
                    '--wasmtime', args.wasmtime, '--openssl', args.openssl]
        if args.motoko: sys.argv.append('--motoko')
        if args.imports: sys.argv.append('--imports')
        previous.main()
        report['portable_and_imports'] = json.loads((OUT/'report.json').read_text())
    assert before == previous.source_hashes(), 'Implementation changed during audit'
    (OUT/'round4-report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'native': report.get('native_asan_ubsan_O3'), 'fixtures': summary}))


if __name__ == '__main__':
    main()
