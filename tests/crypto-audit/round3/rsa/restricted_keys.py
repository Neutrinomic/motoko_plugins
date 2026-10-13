#!/usr/bin/env python3
"""Ensure PEM/DER import never silently discards RSA-PSS key restrictions."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from audit import HERE, ROOT, VECTORS, key_numbers


def tlv(tag, value):
    length = len(value)
    size = bytes([length]) if length < 128 else (lambda b: bytes([128 + len(b)]) + b)(length.to_bytes((length.bit_length() + 7) // 8, 'big'))
    return bytes([tag]) + size + value


def integer(n):
    value = n.to_bytes((n.bit_length() + 7) // 8 or 1, 'big')
    if value[0] & 128:
        value = b'\0' + value
    return tlv(2, value)


def algorithm(hash_id, mgf_hash_id, salt):
    def sha(identifier):
        return tlv(48, bytes.fromhex('06096086480165030402') + bytes([identifier]) + b'\x05\0')
    params = tlv(0xa0, sha(hash_id))
    params += tlv(0xa1, tlv(48, bytes.fromhex('06092a864886f70d010108') + sha(mgf_hash_id)))
    params += tlv(0xa2, integer(salt))
    return tlv(48, bytes.fromhex('06092a864886f70d01010a') + tlv(48, params))


def pem(label, value):
    raw = base64.b64encode(value).decode()
    return ('-----BEGIN ' + label + '-----\n' + '\n'.join(raw[i:i+64] for i in range(0, len(raw), 64))
            + '\n-----END ' + label + '-----\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openssl', default='openssl')
    parser.add_argument('--require-rejection', action='store_true')
    parser.add_argument('--importer', type=Path, default=ROOT / 'plugins/rsa/tools/import_key.py')
    parser.add_argument('--output', type=Path, default=HERE / '_out/restricted-import')
    args = parser.parse_args()
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    private = (VECTORS / 'PUBLIC-TEST-ONLY-private.der').read_bytes()
    n, e, *_ = key_numbers(private)
    public = tlv(48, integer(n) + integer(e))
    results = []
    for profile, parameters in [('sha384', (2, 2, 48)), ('long-salt', (1, 1, 48)),
                                ('mgf-sha512', (1, 3, 32)), ('matching-profile', (1, 1, 32))]:
        alg = algorithm(*parameters)
        for kind, data, label in [('private', tlv(48, integer(0) + alg + tlv(4, private)), 'PRIVATE KEY'),
                                  ('public', tlv(48, alg + tlv(3, b'\0' + public)), 'PUBLIC KEY')]:
            for fmt in ['der', 'pem']:
                name = profile + '-' + kind + '.' + fmt
                source = out / name
                source.write_bytes(data if fmt == 'der' else pem(label, data))
                inspect = [args.openssl, 'pkey', '-in', str(source), '-text', '-noout']
                if kind == 'public':
                    inspect += ['-pubin']
                parsed = subprocess.run(inspect, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                assert parsed.returncode == 0 and b'PSS parameter restrictions' in parsed.stdout, (name, parsed.stderr)
                publicout, secretout = out / (name + '.public'), out / (name + '.secret')
                publicout.unlink(missing_ok=True); secretout.unlink(missing_ok=True)
                command = [sys.executable, str(args.importer), '--openssl', args.openssl,
                           '--' + kind + '-key', str(source), '--public-out', str(publicout)]
                if kind == 'private':
                    command += ['--private-out', str(secretout)]
                result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                item = dict(name=name, exit_code=result.returncode, rejected=result.returncode != 0,
                            openssl_parses_restrictions=True,
                            public_created=publicout.exists(), secret_created=secretout.exists(),
                            fixture_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
                assert not result.stdout, 'import command unexpectedly writes stdout'
                (out / (name + '.log')).write_bytes(result.stderr)
                results.append(item)
    report = {'importer_sha256': hashlib.sha256(args.importer.read_bytes()).hexdigest(),
              'cases': results, 'all_rejected': all(x['rejected'] and not x['public_created'] and not x['secret_created'] for x in results)}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if args.require_rejection:
        assert report['all_rejected'], 'RSA-PSS restrictions were silently removed during import'


if __name__ == '__main__':
    main()
