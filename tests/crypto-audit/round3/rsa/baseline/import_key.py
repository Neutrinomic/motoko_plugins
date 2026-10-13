#!/usr/bin/env python3
"""Convert OpenSSL RSA PEM/DER to the fixed mo:fast/RSA component blobs.

Private input is checked by OpenSSL (including primes) before conversion.
Secret bytes go only to the explicitly requested new mode0600 file, not stdout.
"""
import argparse
import os
from pathlib import Path
import subprocess


def tlv(data, offset, expected):
    if offset >= len(data) or data[offset] != expected:
        raise ValueError('unexpected DER tag')
    offset += 1
    length = data[offset]
    offset += 1
    if length >= 128:
        count = length & 127
        if count == 0 or count > 4 or offset + count > len(data):
            raise ValueError('invalid DER length')
        if data[offset] == 0:
            raise ValueError('nonminimal DER length')
        length = int.from_bytes(data[offset:offset+count], 'big')
        offset += count
        if length < 128:
            raise ValueError('nonminimal DER length')
    if offset + length > len(data):
        raise ValueError('truncated DER')
    return data[offset:offset+length], offset+length


def integers(der):
    body, end = tlv(der, 0, 0x30)
    if end != len(der):
        raise ValueError('trailing DER')
    offset, values = 0, []
    while offset < len(body):
        value, offset = tlv(body, offset, 2)
        if not value or value[0] & 128 or (len(value) > 1 and value[0] == 0 and value[1] < 128):
            raise ValueError('invalid DER integer')
        values.append(int.from_bytes(value, 'big'))
    return values


def components(values, private):
    if private:
        if len(values) != 9 or values[0] != 0:
            raise ValueError('requires a two-prime PKCS#1 RSA key')
        _, n, e, d, p, q, dp, dq, iq = values
        if p == q or p.bit_length() != 1536 or q.bit_length() != 1536 or not p & q & 1:
            raise ValueError('requires distinct odd 1536-bit RSA factors')
        if n != p*q or dp != d % (p-1) or dq != d % (q-1) or (e*dp) % (p-1) != 1 or (e*dq) % (q-1) != 1:
            raise ValueError('inconsistent private key')
        if not 0 < iq < p or iq*q % p != 1:
            raise ValueError('qInv must be q^-1 modulo p')
        secret = b''.join(v.to_bytes(192, 'big') for v in [p, q, dp, dq, iq])
    else:
        if len(values) != 2:
            raise ValueError('invalid RSA public key')
        n, e = values
        secret = None
    if n.bit_length() != 3072 or not n & 1 or e != 65537:
        raise ValueError('requires RSA-3072 with public exponent65537')
    return secret, n.to_bytes(384, 'big')


def new_file(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--private-key', type=Path)
    group.add_argument('--public-key', type=Path)
    parser.add_argument('--private-out', type=Path)
    parser.add_argument('--public-out', type=Path, required=True)
    parser.add_argument('--openssl', default='openssl')
    args = parser.parse_args()
    private = args.private_key is not None
    if private != (args.private_out is not None):
        parser.error('--private-key requires --private-out; public import does not accept it')
    if args.public_out.exists() or (args.private_out and args.private_out.exists()):
        parser.error('output files must not already exist')
    try:
        if private:
            subprocess.run([args.openssl, 'pkey', '-in', str(args.private_key), '-check', '-noout'],
                           check=True, stdout=subprocess.DEVNULL)
            command = [args.openssl, 'rsa', '-in', str(args.private_key), '-traditional', '-outform', 'DER']
        else:
            command = [args.openssl, 'rsa', '-pubin', '-in', str(args.public_key), '-RSAPublicKey_out', '-outform', 'DER']
        der = subprocess.run(command, check=True, capture_output=True).stdout
        secret, public = components(integers(der), private)
        if secret is not None:
            new_file(args.private_out, secret)
        new_file(args.public_out, public)
    except (ValueError, IndexError, OverflowError, OSError, subprocess.CalledProcessError) as error:
        # Never include DER, key components or subprocess output in diagnostics.
        parser.exit(1, f'RSA import failed ({type(error).__name__}); check input profile and paths.\n')


if __name__ == '__main__':
    main()
