#!/usr/bin/env python3
"""Independent RSA fixed-profile tests (RFC 8017, OpenSSL and Wycheproof).

Preparation saves PUBLIC TEST KEYS: never use these keys outside this audit.
Generate fixtures with --prepare, run C sanitizers with --native, and compare
portable OCaml and compiled Wasm with --motoko --plugin DIR. All artifacts and
logs are isolated below this directory. Supply compiler/tool paths explicitly.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
VECTORS = HERE / "vectors"
BUILD = HERE / "_out"


def run(command, name):
    command = [str(x) for x in command]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (BUILD / (name + ".log")).write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}: {result.stdout.decode(errors='replace')[-6000:]}")
    return result.stdout


def read_der(data):
    """Small independent definite-length DER reader, only for oracle fixtures."""
    tag, size, offset = data[0], data[1], 2
    if size & 128:
        width = size & 127
        assert 1 <= width <= 3
        size = int.from_bytes(data[2:2 + width], "big")
        offset += width
    assert offset + size <= len(data)
    return tag, data[offset:offset + size], data[offset + size:]


def key_numbers(der):
    tag, body, rest = read_der(der)
    assert tag == 48 and not rest
    values = []
    while body:
        tag, value, body = read_der(body)
        assert tag == 2 and value[0] < 128
        values.append(int.from_bytes(value, "big"))
    assert len(values) == 9 and values[0] == 0
    _, n, e, d, p, q, dp, dq, qi = values
    assert e == 65537 and n == p * q and n.bit_length() == 3072
    assert e * d % math.lcm(p - 1, q - 1) == 1
    assert dp == d % (p - 1) and dq == d % (q - 1) and qi * q % p == 1
    return n, e, d, p, q, dp, dq, qi


def fixed(value, length=192):
    return value.to_bytes(length, "big")


def mgf(seed, length, hashfn=hashlib.sha256):
    return b"".join(hashfn(seed + i.to_bytes(4, "big")).digest()
                    for i in range((length + hashfn().digest_size - 1) // hashfn().digest_size))[:length]


def pss(digest, salt, mgf_hash=hashlib.sha256):
    h = hashlib.sha256(bytes(8) + digest + salt).digest()
    data = bytes(350 - len(salt)) + b"\1" + salt
    masked = bytearray(a ^ b for a, b in zip(data, mgf(h, 351, mgf_hash)))
    masked[0] &= 127
    return bytes(masked) + h + b"\xbc"


def add(cases, name, op, args, expected, prehash=False):
    cases.append(dict(name=name, op=op, args=[a.hex() for a in args],
                      expected=expected.hex() if isinstance(expected, bytes) else expected,
                      prehash=prehash))


def prepare(openssl):
    pem = VECTORS / "PUBLIC-TEST-ONLY-private.pem"
    der = VECTORS / "PUBLIC-TEST-ONLY-private.der"
    if not pem.exists():
        run([openssl, "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072",
             "-pkeyopt", "rsa_keygen_pubexp:65537", "-out", pem], "openssl-keygen")
    run([openssl, "rsa", "-in", pem, "-traditional", "-outform", "DER", "-out", der], "openssl-private-der")
    pubpem = VECTORS / "public.pem"
    run([openssl, "pkey", "-in", pem, "-pubout", "-out", pubpem], "openssl-public-pem")
    n, e, d, p, q, dp, dq, qi = key_numbers(der.read_bytes())
    sk = b"".join(fixed(x) for x in [p, q, dp, dq, qi])
    pk = fixed(n, 384)
    importer = ROOT / "plugins/rsa/tools/import_key.py"
    conversions = [("pkcs8-pem", pem, True), ("pkcs1-der", der, True), ("spki-pem", pubpem, False)]
    pkcs8der, pkcs1pem = BUILD / 'pkcs8.der', BUILD / 'pkcs1.pem'
    spkider, pkcs1pub = BUILD / 'spki.der', BUILD / 'pkcs1-public.der'
    run([openssl, 'pkcs8', '-topk8', '-nocrypt', '-in', pem, '-outform', 'DER', '-out', pkcs8der], 'openssl-pkcs8')
    run([openssl, 'rsa', '-in', pem, '-traditional', '-out', pkcs1pem], 'openssl-pkcs1-pem')
    run([openssl, 'pkey', '-in', pem, '-pubout', '-outform', 'DER', '-out', spkider], 'openssl-spki-der')
    run([openssl, 'rsa', '-in', pem, '-RSAPublicKey_out', '-outform', 'DER', '-out', pkcs1pub], 'openssl-pkcs1-public')
    conversions += [('pkcs8-der', pkcs8der, True), ('pkcs1-pem', pkcs1pem, True),
                    ('spki-der', spkider, False), ('pkcs1-public-der', pkcs1pub, False)]
    for label, source, private in conversions:
        publicout, secretout = BUILD / (label + '.public'), BUILD / (label + '.secret')
        for output in [publicout, secretout]:
            output.unlink(missing_ok=True)
        command = ['python3', importer, '--openssl', openssl,
                   '--private-key' if private else '--public-key', source, '--public-out', publicout]
        if private:
            command += ['--private-out', secretout]
        run(command, 'import-' + label)
        assert publicout.read_bytes() == pk
        if private:
            assert secretout.read_bytes() == sk
            assert os.stat(secretout).st_mode & 0o777 == 0o600
    cases = []
    add(cases, "validate-private", "validatePrivateKey", [sk], 1)
    add(cases, "validate-public", "validatePublicKey", [pk], 1)
    add(cases, "derive-public", "publicKey", [sk], pk)
    swapped = b"".join(fixed(x) for x in [q, p, dq, dp, pow(p, -1, q)])
    add(cases, "swapped-factor-order", "publicKey", [swapped], pk)
    messages = [b"", b"independent RSA-PSS audit", bytes(range(256)) * 4]
    messages += [bytes((j * 37 + 11) % 256 for j in range(size)) for size in [1, 55, 56, 63, 64, 65, 127, 128, 129]]
    for i, message in enumerate(messages):
        salt = bytes((x + 17 * i) % 256 for x in range(32))
        digest = hashlib.sha256(message).digest()
        encoded = pss(digest, salt)
        signature = fixed(pow(int.from_bytes(encoded, "big"), d, n), 384)
        for prehash in [False, True]:
            data = digest if prehash else message
            add(cases, f"sign-oracle-{i}-{prehash}", "sign", [sk, data, salt], signature, prehash)
            add(cases, f"verify-oracle-{i}-{prehash}", "verify", [pk, data, signature], 1, prehash)
        add(cases, f"wrong-message-{i}", "verify", [pk, message + b"!", signature], 0)
        msgfile, sigfile = BUILD / f"message-{i}.bin", BUILD / f"signature-{i}.bin"
        msgfile.write_bytes(message); sigfile.write_bytes(signature)
        run([openssl, "dgst", "-sha256", "-verify", pubpem, "-signature", sigfile,
             "-sigopt", "rsa_padding_mode:pss", "-sigopt", "rsa_pss_saltlen:32", msgfile], f"openssl-verify-{i}")
        run([openssl, "dgst", "-sha256", "-sign", pem, "-out", sigfile,
             "-sigopt", "rsa_padding_mode:pss", "-sigopt", "rsa_pss_saltlen:32", msgfile], f"openssl-sign-{i}")
        add(cases, f"openssl-signature-{i}", "verify", [pk, message, sigfile.read_bytes()], 1)
    for index, part in enumerate([p, q, dp, dq, qi]):
        for label, value in [("zero", 0), ("one", 1), ("changed", part ^ 2), ("max", 2 ** 1536 - 1)]:
            components = [p, q, dp, dq, qi]
            components[index] = value
            bad = b"".join(fixed(x) for x in components)
            add(cases, f"bad-component-{index}-{label}", "validatePrivateKey", [bad], -1)
            add(cases, f"bad-component-sign-{index}-{label}", "sign", [bad, b"", bytes(32)], -1)
    for index, value in [(0, q), (2, p - 1), (3, q - 1), (4, p)]:
        components = [p, q, dp, dq, qi]; components[index] = value
        add(cases, f"component-bound-{index}", "publicKey", [b"".join(fixed(x) for x in components)], -1)
    # Raw validation explicitly checks consistency, not primality. Exercise
    # the final public-operation fault check with consistent composite factors.
    cp, cq = 2 ** 1536 - 1, 2 ** 1536 - 3
    cdp, cdq, cqi = pow(e, -1, cp - 1), pow(e, -1, cq - 1), pow(cq, -1, cp)
    composite = b''.join(fixed(x) for x in [cp, cq, cdp, cdq, cqi])
    em = int.from_bytes(pss(hashlib.sha256(b'fault self-check').digest(), bytes(32)), 'big')
    cm1, cm2 = pow(em, cdp, cp), pow(em, cdq, cq)
    faulty = cm2 + cq * ((cm1 - cm2) * cqi % cp)
    assert pow(faulty, e, cp * cq) != em
    add(cases, 'composite-crt-consistency-only', 'validatePrivateKey', [composite], 1)
    add(cases, 'fault-self-check', 'sign', [composite, b'fault self-check', bytes(32)], -1)
    for length in [0, 1, 191, 192, 383, 384, 959, 961, 1920]:
        add(cases, f"private-length-{length}", "validatePrivateKey", [(sk + sk)[:length]], -1)
    for value in [b"", pk[:-1], b"\0" + pk, bytes(384), bytes([pk[0] & 127]) + pk[1:], pk[:-1] + bytes([pk[-1] & 254])]:
        add(cases, f"public-malformed-{len(cases)}", "validatePublicKey", [value], -2)
    message = b"PSS malformed encoding"
    digest = hashlib.sha256(message).digest()
    encoded = pss(digest, bytes(32))
    bad_encodings = {}
    for salt_size in [0, 1, 31, 33, 64]:
        bad_encodings[f"salt-{salt_size}"] = pss(digest, bytes(salt_size))
    bad_encodings["mgf-sha512"] = pss(digest, bytes(32), hashlib.sha512)
    for offset, label in [(0, "masked-ps"), (318, "delimiter"), (351, "hash"), (383, "trailer")]:
        value = bytearray(encoded); value[offset] ^= 1; bad_encodings[label] = bytes(value)
    value = bytearray(encoded); value[0] |= 128
    if int.from_bytes(value, "big") < n:
        bad_encodings["forbidden-top-bit"] = bytes(value)
    else:
        bad_encodings["forbidden-top-bit"] = fixed(2 ** 3071, 384)
    for label, value in bad_encodings.items():
        signature = fixed(pow(int.from_bytes(value, "big"), d, n), 384)
        add(cases, f"malformed-pss-{label}", "verify", [pk, message, signature], 0)
    for value, expected in [(bytes(384), 0), (fixed(n - 1, 384), 0), (pk, -5), (fixed(n + 1, 384), -5),
                            (bytes([255]) * 384, -5), (b"", -5), (bytes(383), -5), (bytes(385), -5)]:
        add(cases, f"signature-range-{len(cases)}", "verify", [pk, b"", value], expected)
    add(cases, "private-error-precedence", "sign", [b"", b"", b""], -1, True)
    add(cases, "digest-before-salt", "sign", [sk, b"", b""], -3, True)
    add(cases, "salt-error", "sign", [sk, bytes(32), b""], -4, True)
    add(cases, "public-error-precedence", "verify", [b"", b"", b""], -2, True)
    add(cases, "digest-before-signature", "verify", [pk, b"", b""], -3, True)
    corpus = json.loads((VECTORS / "wycheproof-rsa-pss-3072-sha256.json").read_text())
    for group in corpus["testGroups"]:
        assert group["keySize"] == 3072 and group["sLen"] == 32
        n2 = int(group["publicKey"]["modulus"], 16)
        assert int(group["publicKey"]["publicExponent"], 16) == 65537
        key = fixed(n2, 384)
        for vector in group["tests"]:
            signature = bytes.fromhex(vector["sig"])
            expected = int(vector["result"] == "valid")
            if len(signature) != 384 or int.from_bytes(signature, "big") >= n2:
                assert not expected
                expected = -5
            add(cases, f"wycheproof-{vector['tcId']}", "verify",
                [key, bytes.fromhex(vector["msg"]), signature], expected)
    other_n = int(corpus['testGroups'][0]['publicKey']['modulus'], 16)
    wrong_key_signature = fixed(pow(int.from_bytes(pss(hashlib.sha256(b'wrong key').digest(), bytes(32)), 'big'), d, n), 384)
    add(cases, 'mismatched-independent-public-key', 'verify',
        [fixed(other_n, 384), b'wrong key', wrong_key_signature],
        0 if int.from_bytes(wrong_key_signature, 'big') < other_n else -5)
    (VECTORS / "cases.json").write_text(json.dumps(cases, indent=2) + "\n")
    (VECTORS / "oracle-provenance.json").write_text(json.dumps({
        "test_keys_are_public_never_use_in_production": True,
        "openssl_version": run([openssl, "version"], "openssl-version").decode().strip(),
        "private_pkcs1_sha256": hashlib.sha256(der.read_bytes()).hexdigest(),
        "cases": len(cases), "wycheproof_cases": corpus["numberOfTests"],
        "openssl_key_import_formats": [label for label, _, _ in conversions],
        "scheme": "RFC 8017 EMSA-PSS emBits=3071, SHA256, MGF1-SHA256, salt32",
        "oracle": "Python integer pow and hashlib, independently verified by OpenSSL"}, indent=2) + "\n")
    print(f"Prepared {len(cases)} independent cases")


def blob(value):
    return '"' + ''.join('\\' + value[i:i + 2] for i in range(0, len(value), 2)) + '"'


def fixtures():
    cases = json.loads((VECTORS / "cases.json").read_text())
    mo = ['import RSA "mo:fast/RSA";']
    errors = {-1: "invalidSecretKey", -2: "invalidPublicKey", -3: "invalidDigest", -4: "invalidSalt", -5: "invalidSignature"}
    declarations = '''#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern int64_t rsa_impl_validate_private_key(const unsigned char*,size_t);
extern int64_t rsa_impl_validate_public_key(const unsigned char*,size_t);
extern int64_t rsa_impl_public_key(const unsigned char*,size_t,unsigned char*);
extern int64_t rsa_impl_sign(const unsigned char*,size_t,const unsigned char*,size_t,const unsigned char*,size_t,unsigned char*,uint32_t);
extern int64_t rsa_impl_verify(const unsigned char*,size_t,const unsigned char*,size_t,const unsigned char*,size_t,uint32_t);
'''
    native = [declarations, "int main(void) {"]
    for i, case in enumerate(cases):
        op, expected, args = case["op"], case["expected"], case["args"]
        label = case["name"]
        mo_name = op + ("Prehash" if case["prehash"] else "")
        mo_expected = (f"#ok({blob(expected)})" if isinstance(expected, str) else
                       f"#err(#{errors[expected]})" if expected < 0 else
                       "#ok(true)" if expected else "#ok(false)")
        mo += [f'// {label}', f'assert RSA.{mo_name}({", ".join(map(blob, args))}) == {mo_expected};']
        native += ["{", f'  /* {label} */']
        cargs = []
        for j, value in enumerate(args):
            values = ','.join('0x' + value[k:k + 2] for k in range(0, len(value), 2)) or '0'
            native += [f"  unsigned char a{j}[] = {{{values}}};", f"  unsigned char before{j}[sizeof a{j}]; memcpy(before{j},a{j},sizeof a{j});"]
            cargs += [f"a{j}", str(len(value) // 2)]
        native += ["  unsigned char out[400]; memset(out,0xa5,sizeof out);"]
        c_name = {"validatePrivateKey": "validate_private_key", "validatePublicKey": "validate_public_key", "publicKey": "public_key"}.get(op, op)
        if op in ["publicKey", "sign"]:
            cargs += ["out+8"]
        if op in ["sign", "verify"]:
            cargs += [str(int(case["prehash"]))]
        native += [f"  int64_t result = rsa_impl_{c_name}({','.join(cargs)});"]
        expected_status = 384 if isinstance(expected, str) else expected
        native += [f'  if (result != {expected_status}) {{ fprintf(stderr,"case {i} {label}: expected {expected_status}, got %lld\\n",(long long)result); return 1; }}']
        if isinstance(expected, str):
            values = ','.join('0x' + expected[k:k + 2] for k in range(0, len(expected), 2))
            native += [f"  const unsigned char expected[] = {{{values}}};", "  assert(memcmp(out+8,expected,sizeof expected)==0);"]
        if label == 'fault-self-check':
            native += ["  for (int pos=8;pos<392;pos++) assert(out[pos]==0);"]
        native += ["  for (int guard=0;guard<8;guard++) { assert(out[guard]==0xa5); assert(out[392+guard]==0xa5); }"]
        for j in range(len(args)):
            native += [f"  assert(memcmp(a{j},before{j},sizeof a{j})==0);"]
        native += ["}"]
    native += [f'puts("{len(cases)} independent RSA cases passed; input immutability and output bounds passed");', "return 0; }"]
    (BUILD / "audit.mo").write_text('\n'.join(mo) + '\n')
    (BUILD / "native.c").write_text('\n'.join(native) + '\n')
    return cases


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prepare', action='store_true')
    p.add_argument('--native', action='store_true')
    p.add_argument('--motoko', action='store_true')
    p.add_argument('--openssl', default='openssl')
    p.add_argument('--cc', default='cc')
    p.add_argument('--moc', default=str(ROOT.parent / 'motoko_sha/bin/moc'))
    p.add_argument('--wasmtime', default='wasmtime')
    p.add_argument('--plugin', type=Path)
    args = p.parse_args()
    BUILD.mkdir(exist_ok=True)
    if args.prepare:
        prepare(args.openssl)
    cases = fixtures()
    source_paths = [p for p in (ROOT / 'plugins/rsa').rglob('*') if p.is_file() and '_out' not in p.parts]
    source_paths += [ROOT / 'packages/fast/src/RSA.mo', HERE / 'audit.py']
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_paths)}
    report = {"cases": len(cases), "source_sha256": hashlib.sha256((VECTORS / "cases.json").read_bytes()).hexdigest(),
              "source_hashes": source_hashes}
    if args.native:
        runtime = ROOT / 'plugins/rsa/runtime'
        sources = [runtime / 'src/rsa.c'] + sorted((runtime / 'vendor/bearssl/src').rglob('*.c'))
        command = [args.cc, '-std=c99', '-O1', '-g', '-fno-omit-frame-pointer', '-fsanitize=address,undefined',
                   '-fno-sanitize-recover=all', '-DBR_MAX_RSA_SIZE=3072', '-DBR_MAX_RSA_FACTOR=1536',
                   '-I' + str(runtime / 'vendor/bearssl/inc'), '-I' + str(runtime / 'vendor/bearssl/src'),
                   BUILD / 'native.c', *sources, '-o', BUILD / 'native']
        run(command, 'native-build')
        print(run([BUILD / 'native'], 'native').decode(), end='')
        report['native_asan_ubsan'] = 'pass'
    if args.motoko:
        assert args.plugin
        common = [args.moc, '--package', 'fast', ROOT / 'packages/fast/src', '--plugin', args.plugin]
        run(common + ['-r', BUILD / 'audit.mo'], 'interpreter')
        run(common + ['-wasi-system-api', '--sanity-checks', '-o', BUILD / 'audit.wasm', BUILD / 'audit.mo'], 'compile')
        run([args.wasmtime, '-W', 'memory64=y', BUILD / 'audit.wasm'], 'wasm')
        report.update(interpreter='pass', wasm_sanity='pass', wasm_sha256=hashlib.sha256((BUILD/'audit.wasm').read_bytes()).hexdigest())
        report['plugin_artifacts'] = {name: hashlib.sha256((args.plugin / name).read_bytes()).hexdigest()
                                      for name in ['runtime.wasm', 'plugin.cmxs']}
        report['compiler_version'] = run([args.moc, '--version'], 'moc-version').decode().strip()
        print('Portable interpreter and compiled Wasm passed')
    assert source_hashes == {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_paths)}, 'source changed during audit'
    (BUILD / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
