#!/usr/bin/env python3
"""Exercise the real RSA import CLI with deterministic public test keys.

All generated keys and outputs stay below --output (default: _out/imports).
The published round3 test key is public and must never be used in production.
OpenSSL-readable BER/noncanonical DER is deliberately not a rejection case:
the importer documents OpenSSL-readable input, then parses canonical exports.
"""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
VECTORS = ROOT / 'tests/crypto-audit/round3/rsa/vectors'
RSA_ALGORITHM = bytes.fromhex('300d06092a864886f70d0101010500')
PSS_OID = bytes.fromhex('06092a864886f70d01010a')


def tlv(tag, value):
    size = len(value)
    if size < 128:
        length = bytes([size])
    else:
        raw = size.to_bytes((size.bit_length() + 7) // 8, 'big')
        length = bytes([128 + len(raw)]) + raw
    return bytes([tag]) + length + value


def integer(value):
    if value < 0:
        width = 1
        while value < -(1 << (8 * width - 1)):
            width += 1
        raw = value.to_bytes(width, 'big', signed=True)
    else:
        raw = value.to_bytes(max(1, (value.bit_length() + 7) // 8), 'big')
        if raw[0] & 128:
            raw = b'\0' + raw
    return tlv(2, raw)


def sequence(values):
    return tlv(48, b''.join(integer(value) for value in values))


def pkcs8(private, algorithm=RSA_ALGORITHM):
    return tlv(48, integer(0) + algorithm + tlv(4, private))


def spki(public, algorithm=RSA_ALGORITHM):
    return tlv(48, algorithm + tlv(3, b'\0' + public))


def pem(label, der):
    encoded = base64.b64encode(der).decode('ascii')
    lines = [encoded[offset:offset + 64] for offset in range(0, len(encoded), 64)]
    return ('-----BEGIN ' + label + '-----\n' + '\n'.join(lines)
            + '\n-----END ' + label + '-----\n').encode('ascii')


def published_components(der):
    """Independent reader used solely for the checked-in canonical test key."""
    def read(data, offset, tag):
        assert data[offset] == tag
        length, offset = data[offset + 1], offset + 2
        if length & 128:
            count = length & 127
            assert 1 <= count <= 4
            length = int.from_bytes(data[offset:offset + count], 'big')
            offset += count
        assert offset + length <= len(data)
        return data[offset:offset + length], offset + length

    body, end = read(der, 0, 48)
    assert end == len(der)
    values, offset = [], 0
    while offset < len(body):
        raw, offset = read(body, offset, 2)
        assert raw and raw[0] < 128
        values.append(int.from_bytes(raw, 'big'))
    assert len(values) == 9 and values[0] == 0
    _, n, e, d, p, q, dp, dq, qi = values
    assert n == p * q and n.bit_length() == 3072 and e == 65537
    assert e * d % math.lcm(p - 1, q - 1) == 1
    assert dp == d % (p - 1) and dq == d % (q - 1) and qi * q % p == 1
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openssl', default='openssl')
    parser.add_argument('--importer', type=Path, default=ROOT / 'plugins/rsa/tools/import_key.py')
    parser.add_argument('--output', type=Path, default=HERE / '_out/imports')
    args = parser.parse_args()
    openssl = shutil.which(args.openssl)
    if openssl is None:
        parser.error('OpenSSL executable not found')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    original = (VECTORS / 'PUBLIC-TEST-ONLY-private.der').read_bytes()
    values = published_components(original)
    _, n, e, d, p, q, dp, dq, qi = values
    public = sequence([n, e])
    expected_public = n.to_bytes(384, 'big')
    expected_secret = b''.join(x.to_bytes(192, 'big') for x in [p, q, dp, dq, qi])
    results = []

    def run(name, data, private, accepted=False, secret=expected_secret, sentinel=None,
            extra_args=(), omitted_input=False):
        directory = out / name
        directory.mkdir(exist_ok=True)
        source = directory / 'input.key'
        source.write_bytes(data)
        public_out, private_out = directory / 'public.rsa', directory / 'secret.rsa'
        for target in [public_out, private_out]:
            target.unlink(missing_ok=True)
        preserved = b'pre-existing output must remain unchanged\n'
        if sentinel == 'public':
            public_out.write_bytes(preserved)
        if sentinel == 'private':
            private_out.write_bytes(preserved)
        command = [sys.executable, str(args.importer.resolve()), '--openssl', openssl,
                   '--public-out', str(public_out)]
        if not omitted_input:
            command += ['--private-key' if private else '--public-key', str(source)]
        if private:
            command += ['--private-out', str(private_out)]
        command += list(extra_args)
        result = subprocess.run(command, capture_output=True, timeout=30)
        (directory / 'stderr.log').write_bytes(result.stderr)
        checks = {'expected_exit': (result.returncode == 0) == accepted,
                  'stdout_empty': not result.stdout}
        if accepted:
            checks['public_bytes'] = public_out.exists() and public_out.read_bytes() == expected_public
            checks['public_mode_0600'] = public_out.exists() and public_out.stat().st_mode & 0o777 == 0o600
            checks['secret_bytes'] = (private_out.exists() and private_out.read_bytes() == secret) if private else not private_out.exists()
            if private:
                checks['secret_mode_0600'] = private_out.exists() and private_out.stat().st_mode & 0o777 == 0o600
        else:
            checks['public_untouched'] = (public_out.exists() and public_out.read_bytes() == preserved) if sentinel == 'public' else not public_out.exists()
            checks['secret_untouched'] = (private_out.exists() and private_out.read_bytes() == preserved) if sentinel == 'private' else not private_out.exists()
        results.append({'name': name, 'private': private, 'expected_accepted': accepted,
                        'input_sha256': hashlib.sha256(data).hexdigest(),
                        'exit_code': result.returncode, 'checks': checks,
                        'passed': all(checks.values())})

    # Every supported PKCS#1/PKCS#8/SPKI DER and PEM envelope has a positive control.
    for name, der, label, private in [
        ('pkcs1-private', original, 'RSA PRIVATE KEY', True),
        ('pkcs8-private', pkcs8(original), 'PRIVATE KEY', True),
        ('pkcs1-public', public, 'RSA PUBLIC KEY', False),
        ('spki-public', spki(public), 'PUBLIC KEY', False),
    ]:
        run(name + '-der', der, private, accepted=True)
        run(name + '-pem', pem(label, der), private, accepted=True)
    swapped = [0, n, e, d, q, p, dq, dp, pow(p, -1, q)]
    run('private-swapped-factors', sequence(swapped), True, accepted=True,
        secret=b''.join(x.to_bytes(192, 'big') for x in swapped[4:]))

    # Original input is decoded by OpenSSL, so only unequivocally malformed
    # structures are rejected here; normalization is not itself a defect.
    malformed = [
        ('empty', b''), ('tag-only', b'\x30'),
        ('truncated-length', b'\x30\x82\x07'),
        ('wrong-outer-tag', b'\x31' + original[1:]),
        ('empty-sequence', b'\x30\0'),
        ('truncated-value', original[:-1]),
        ('invalid-pem-base64', b'-----BEGIN PRIVATE KEY-----\n!!\n-----END PRIVATE KEY-----\n'),
    ]
    for name, data in malformed:
        for private in [False, True]:
            run(('private-' if private else 'public-') + name, data, private)
    for name, bad_n, bad_e in [
        ('zero-modulus', 0, e), ('negative-modulus', -n, e),
        ('even-modulus', n - 1, e), ('3071-bit-modulus', n >> 1 | 1, e),
        ('3073-bit-modulus', n << 1 | 1, e), ('2048-bit-modulus', (1 << 2047) | 1, e),
        ('4096-bit-modulus', (1 << 4095) | 1, e),
        ('zero-exponent', n, 0), ('one-exponent', n, 1),
        ('even-exponent', n, 65536), ('other-odd-exponent', n, 3),
        ('negative-exponent', n, -e), ('oversized-exponent', n, (1 << 256) + 1),
    ]:
        run('public-' + name, sequence([bad_n, bad_e]), False)
    run('public-missing-exponent', sequence([n]), False)
    run('public-extra-integer', sequence([n, e, 0]), False)

    for name, index, value in [
        ('version-one', 0, 1), ('version-two', 0, 2),
        ('n-mismatch', 1, n + 2), ('n-negative', 1, -n),
        ('e-zero', 2, 0), ('e-one', 2, 1), ('e-even', 2, 65536),
        ('d-zero', 3, 0), ('d-negative', 3, -d), ('d-changed', 3, d + 1),
        ('p-zero', 4, 0), ('p-one', 4, 1), ('p-even', 4, p - 1),
        ('p-short', 4, (p >> 1) | 1), ('p-long', 4, (p << 1) | 1),
        ('p-equals-q', 4, q), ('q-zero', 5, 0), ('q-even', 5, q - 1),
        ('q-short', 5, (q >> 1) | 1), ('q-long', 5, (q << 1) | 1),
        ('dp-zero', 6, 0), ('dp-changed', 6, dp + 1), ('dp-at-bound', 6, p - 1),
        ('dq-zero', 7, 0), ('dq-changed', 7, dq + 1), ('dq-at-bound', 7, q - 1),
        ('qinv-zero', 8, 0), ('qinv-changed', 8, qi + 1), ('qinv-at-bound', 8, p),
    ]:
        changed = values.copy()
        changed[index] = value
        run('private-' + name, sequence(changed), True)
    run('private-missing-qinv', sequence(values[:-1]), True)
    run('private-extra-integer', sequence(values + [0]), True)
    # Keep prime factors and every private relation valid while changing e;
    # rejection must come from the fixed exponent profile, not broken CRT data.
    order = math.lcm(p - 1, q - 1)
    other_e = next(value for value in [3, 17, 65539, 65543] if math.gcd(value, order) == 1)
    other_d = pow(other_e, -1, order)
    run('private-consistent-other-exponent', sequence([
        0, n, other_e, other_d, p, q, other_d % (p - 1), other_d % (q - 1), qi]), True)
    # Algebraically consistent 1536-bit factors and a 3072-bit product are
    # insufficient: these factors are composite, which pkey -check must reject.
    cp, cq = (1 << 1536) - 1, (1 << 1536) - 3
    cd = pow(e, -1, math.lcm(cp - 1, cq - 1))
    run('private-consistent-composite-factors', sequence([
        0, cp * cq, e, cd, cp, cq, cd % (cp - 1), cd % (cq - 1), pow(cq, -1, cp)]), True)

    for name, algorithm in [('pss-absent-parameters', tlv(48, PSS_OID)),
                            ('pss-default-parameters', tlv(48, PSS_OID + tlv(48, b'')))]:
        run(name + '-public', spki(public, algorithm), False)
        run(name + '-private', pkcs8(original, algorithm), True)
    for fixture in sorted((VECTORS / 'restricted').glob('*')):
        if fixture.suffix in ['.der', '.pem']:
            run('restricted-' + fixture.name, fixture.read_bytes(), '-private.' in fixture.name)
    ed_algorithm = bytes.fromhex('300506032b6570')
    run('unsupported-ed25519-public', spki(bytes(range(32)), ed_algorithm), False)
    run('unsupported-ed25519-private', pkcs8(tlv(4, bytes(range(32))), ed_algorithm), True)

    run('existing-public-output', public, False, sentinel='public')
    run('private-existing-public-output', original, True, sentinel='public')
    run('existing-private-output', original, True, sentinel='private')
    run('missing-input-option', public, False, omitted_input=True)
    run('public-rejects-private-out', public, False,
        extra_args=['--private-out', str(out / 'public-rejects-private-out/secret.rsa')])
    run('private-requires-private-out', original, False, omitted_input=True,
        extra_args=['--private-key', str(out / 'private-requires-private-out/input.key')])

    version = subprocess.run([openssl, 'version'], check=True, capture_output=True).stdout.decode().strip()
    report = {'test_keys_are_public_never_use_in_production': True,
              'openssl_version': version,
              'importer_sha256': hashlib.sha256(args.importer.read_bytes()).hexdigest(),
              'fixture_key_sha256': hashlib.sha256(original).hexdigest(),
              'cases': results, 'case_count': len(results),
              'accepted_controls': sum(item['expected_accepted'] for item in results),
              'all_passed': all(item['passed'] for item in results)}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    failed = [item['name'] for item in results if not item['passed']]
    print(json.dumps({'cases': len(results), 'accepted_controls': report['accepted_controls'],
                      'all_passed': report['all_passed'], 'failed': failed,
                      'report': str(out / 'report.json')}, indent=2))
    if failed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
