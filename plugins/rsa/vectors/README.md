# Independent RSA3072 vector

`openssl3072.json` contains an explicitly public **test-only** RSA private key,
public modulus, message, SHA256 digest, salt and signature. Node.js's OpenSSL
backend generated a 3072-bit/e65537 key and a PSS-SHA256/MGF1-SHA256 signature
with 32-byte salt. The salt was recovered from the signature through the public
RSA operation and standard MGF1, independently of this plugin. Both the portable
interpreter and native implementation must reproduce the exact signature when
supplied that recovered salt.

The runtime crate, Motoko module tests, and benchmark use this same fixed vector.
Do not generate new keys when rerunning tests or benchmarks. The audit suite
adds an independently generated key and pinned Wycheproof vectors.
