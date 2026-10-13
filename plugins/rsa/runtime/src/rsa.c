/* PSS/MGF1 adaptation derived from BearSSL, Copyright (c)2018 Thomas Pornin.
 * MIT permission notice is retained in vendor/bearssl/LICENSE.txt.
 */
/* RSA-3072 / e=65537 / PSS-SHA256, fixed-width checked adapter for BearSSL.
 * Only upstream i31 operations handle secret multiprecision arithmetic.
 * Input blobs are borrowed, never modified or retained. Scratch is bounded.
 */
#include "inner.h"

#define NBYTES 384
#define FBYTES 192
#define KEYBYTES (5 * FBYTES)
#define WORDS 52
#define INVALID_SECRET -1
#define INVALID_PUBLIC -2
#define INVALID_DIGEST -3
#define INVALID_SALT -4
#define INVALID_SIGNATURE -5
static const unsigned char exponent[] = { 1, 0, 1 };

static void clear(void *p, size_t n) {
    volatile unsigned char *q = p;
    while (n --) { *q ++ = 0; }
}
static uint32_t equal(const unsigned char *a, const unsigned char *b, size_t n) {
    uint32_t diff = 0;
    for (size_t i = 0; i < n; i ++) { diff |= a[i] ^ b[i]; }
    return EQ0(diff);
}
static uint32_t less(const unsigned char *a, const unsigned char *b, size_t n) {
    uint32_t borrow = 0;
    while (n > 0) { n --; borrow = ((uint32_t)a[n] - b[n] - borrow) >> 31; }
    return borrow;
}
static uint32_t is_one(const uint32_t *a) {
    uint32_t diff = a[1] ^ 1;
    for (size_t i = 2; i <= ((a[0] + 31) >> 5); i ++) { diff |= a[i]; }
    return EQ0(diff);
}

/* Check 0<x<modulus and x*factor == 1 (mod modulus). Fixed-size metadata
 * prevents the leading zero count in private exponents from changing loops.
 * br_i31_decode_reduce works for both odd p and even p-1.
 */
static uint32_t inverse_relation(const unsigned char *x, const unsigned char *factor,
    size_t factor_len, const unsigned char *modulus)
{
    uint32_t m[WORDS] = {0}, a[WORDS] = {0}, b[WORDS] = {0};
    uint32_t product[2 * WORDS] = {0}, reduced[WORDS] = {0};
    unsigned char encoded[NBYTES];
    br_i31_decode(m, modulus, FBYTES);
    br_i31_decode(a, x, FBYTES); a[0] = m[0];
    br_i31_decode(b, factor, factor_len);
    /* factor_len is either a public3 or a fixed192. */
    if (factor_len == FBYTES) { b[0] = m[0]; }
    br_i31_mulacc(product, a, b);
    br_i31_encode(encoded, sizeof encoded, product);
    br_i31_decode_reduce(reduced, encoded, sizeof encoded, m);
    uint32_t result = less(x, modulus, FBYTES) & is_one(reduced);
    clear(m, sizeof m); clear(a, sizeof a); clear(b, sizeof b);
    clear(product, sizeof product); clear(reduced, sizeof reduced); clear(encoded, sizeof encoded);
    return result;
}

static uint32_t private_key(const unsigned char *bytes, size_t len,
    br_rsa_private_key *sk, unsigned char *modulus)
{
    if (len != KEYBYTES) { return 0; }
    const unsigned char *p = bytes, *q = p + FBYTES;
    if ((p[0] & q[0] & 128) == 0 || (p[FBYTES-1] & q[FBYTES-1] & 1) == 0
        || equal(p, q, FBYTES)) { return 0; }
    /* BearSSL does not mutate key components; its historical API predates const. */
    sk->n_bitlen = 3072;
    sk->p = (unsigned char *)p; sk->plen = FBYTES;
    sk->q = (unsigned char *)q; sk->qlen = FBYTES;
    sk->dp = (unsigned char *)bytes + 2*FBYTES; sk->dplen = FBYTES;
    sk->dq = (unsigned char *)bytes + 3*FBYTES; sk->dqlen = FBYTES;
    sk->iq = (unsigned char *)bytes + 4*FBYTES; sk->iqlen = FBYTES;
    br_rsa_i31_compute_modulus(modulus, sk);
    if ((modulus[0] & 128) == 0) { return 0; }
    unsigned char pm1[FBYTES], qm1[FBYTES];
    memcpy(pm1, p, FBYTES); pm1[FBYTES-1] --;
    memcpy(qm1, q, FBYTES); qm1[FBYTES-1] --;
    uint32_t valid = inverse_relation(sk->dp, exponent, sizeof exponent, pm1)
        & inverse_relation(sk->dq, exponent, sizeof exponent, qm1)
        & inverse_relation(sk->iq, q, FBYTES, p);
    clear(pm1, sizeof pm1); clear(qm1, sizeof qm1);
    return valid;
}
static uint32_t public_key(const unsigned char *bytes, size_t len, br_rsa_public_key *pk) {
    if (len != NBYTES || (bytes[0] & 128) == 0 || (bytes[NBYTES-1] & 1) == 0) { return 0; }
    pk->n = (unsigned char *)bytes; pk->nlen = len;
    pk->e = (unsigned char *)exponent; pk->elen = sizeof exponent;
    return 1;
}
/* This public-only profile fixes e = 65537 = 2^16 + 1. Reuse BearSSL's
 * unchanged Montgomery arithmetic, skipping the generic secret-exponent
 * window/conditional-multiply path and leading zero bits. */
static uint32_t public_65537(unsigned char *x, size_t len, const br_rsa_public_key *pk) {
    if (len != NBYTES || pk->nlen != NBYTES) { return 0; }
    uint32_t modulus[102] = {0}, base[102] = {0};
    uint32_t left[102] = {0}, right[102] = {0};
    br_i31_decode(modulus, pk->n, NBYTES);
    uint32_t inverse = br_i31_ninv31(modulus[1]);
    uint32_t valid = (inverse & 1) & br_i31_decode_mod(left, x, len, modulus);
    br_i31_to_monty(left, modulus); memcpy(base, left, sizeof base);
    uint32_t *current = left, *next = right;
    for (size_t i = 0; i < 16; i ++) {
        /* montymul zeroes its destination: it cannot alias either input. */
        br_i31_montymul(next, current, current, modulus, inverse);
        uint32_t *swap = current; current = next; next = swap;
    }
    br_i31_montymul(next, current, base, modulus, inverse);
    br_i31_from_monty(next, modulus, inverse);
    br_i31_encode(x, len, next);
    clear(modulus, sizeof modulus); clear(base, sizeof base);
    clear(left, sizeof left); clear(right, sizeof right);
    return valid;
}

static void digest(const unsigned char *message, size_t len, unsigned char hash[32]) {
    br_sha256_context context;
    br_sha256_init(&context); br_sha256_update(&context, message, len); br_sha256_out(&context, hash);
    clear(&context, sizeof context);
}

/* Fixed-profile RFC8017 EMSA-PSS, specialized from BearSSL's generic
 * rsa_pss_sig_pad/unpad and mgf1. Direct SHA256 calls avoid function-pointer
 * tables and their dynamic relocations, which the plugin ABI excludes. */
static void mask_xor(unsigned char *out, const unsigned char seed[32]) {
    unsigned char block[32], counter[4] = {0};
    br_sha256_context context;
    for (size_t offset = 0; offset < 351; offset += 32) {
        counter[3] = (unsigned char)(offset / 32);
        br_sha256_init(&context); br_sha256_update(&context, seed, 32);
        br_sha256_update(&context, counter, 4); br_sha256_out(&context, block);
        for (size_t i = 0; i < 32 && offset+i < 351; i ++) { out[offset+i] ^= block[i]; }
    }
    clear(block, sizeof block); clear(&context, sizeof context);
}
static void pss_hash(const unsigned char hash[32], const unsigned char salt[32], unsigned char out[32]) {
    const unsigned char zero[8] = {0};
    br_sha256_context context;
    br_sha256_init(&context); br_sha256_update(&context, zero, 8);
    br_sha256_update(&context, hash, 32); br_sha256_update(&context, salt, 32);
    br_sha256_out(&context, out); clear(&context, sizeof context);
}
static void pss_pad(const unsigned char hash[32], const unsigned char salt[32], unsigned char out[NBYTES]) {
    memset(out, 0, 318); out[318] = 1; memcpy(out+319, salt, 32);
    pss_hash(hash, salt, out+351); mask_xor(out, out+351);
    out[0] &= 127; out[383] = 0xbc;
}
static uint32_t pss_unpad(const unsigned char hash[32], unsigned char em[NBYTES]) {
    uint32_t bad = (em[0] & 128) | (em[383] ^ 0xbc);
    mask_xor(em, em+351); em[0] &= 127;
    for (size_t i = 0; i < 318; i ++) { bad |= em[i]; }
    bad |= em[318] ^ 1;
    unsigned char expected[32]; pss_hash(hash, em+319, expected);
    for (size_t i = 0; i < 32; i ++) { bad |= expected[i] ^ em[351+i]; }
    clear(expected, sizeof expected);
    return EQ0(bad);
}

int64_t rsa_impl_public_key(const unsigned char *key, size_t len, unsigned char *out) {
    br_rsa_private_key sk;
    if (!private_key(key, len, &sk, out)) { memset(out, 0, NBYTES); return INVALID_SECRET; }
    return NBYTES;
}
int64_t rsa_impl_validate_private_key(const unsigned char *key, size_t len) {
    unsigned char modulus[NBYTES]; br_rsa_private_key sk;
    return private_key(key, len, &sk, modulus) ? 1 : INVALID_SECRET;
}
int64_t rsa_impl_validate_public_key(const unsigned char *key, size_t len) {
    br_rsa_public_key pk;
    return public_key(key, len, &pk) ? 1 : INVALID_PUBLIC;
}
int64_t rsa_impl_sign(const unsigned char *key, size_t key_len,
    const unsigned char *message, size_t message_len, const unsigned char *salt,
    size_t salt_len, unsigned char *out, uint32_t prehash)
{
    br_rsa_private_key sk; unsigned char modulus[NBYTES], hash[32], expected[NBYTES];
    if (!private_key(key, key_len, &sk, modulus)) { return INVALID_SECRET; }
    if (prehash && message_len != 32) { return INVALID_DIGEST; }
    if (salt_len != 32) { return INVALID_SALT; }
    if (prehash) { memcpy(hash, message, 32); } else { digest(message, message_len, hash); }
    pss_pad(hash, salt, expected);
    uint32_t valid = 1;
    memcpy(out, expected, NBYTES);
    valid &= br_rsa_i31_private(out, &sk);
    /* Recompute with the public exponent before releasing any signature.
     * Catches invalid CRT parameters and private-operation faults. */
    unsigned char checked[NBYTES]; memcpy(checked, out, NBYTES);
    br_rsa_public_key pk; public_key(modulus, NBYTES, &pk);
    valid &= public_65537(checked, NBYTES, &pk);
    valid &= equal(checked, expected, NBYTES);
    clear(hash, sizeof hash); clear(expected, sizeof expected); clear(checked, sizeof checked);
    if (!valid) { memset(out, 0, NBYTES); return INVALID_SECRET; }
    return NBYTES;
}
int64_t rsa_impl_verify(const unsigned char *key, size_t key_len,
    const unsigned char *message, size_t message_len, const unsigned char *signature,
    size_t signature_len, uint32_t prehash)
{
    br_rsa_public_key pk; unsigned char hash[32];
    if (!public_key(key, key_len, &pk)) { return INVALID_PUBLIC; }
    if (prehash && message_len != 32) { return INVALID_DIGEST; }
    if (signature_len != NBYTES || !less(signature, key, NBYTES)) { return INVALID_SIGNATURE; }
    if (prehash) { memcpy(hash, message, 32); } else { digest(message, message_len, hash); }
    unsigned char encoded[NBYTES]; memcpy(encoded, signature, NBYTES);
    uint32_t valid = public_65537(encoded, NBYTES, &pk);
    valid &= pss_unpad(hash, encoded);
    clear(encoded, sizeof encoded);
    clear(hash, sizeof hash);
    return valid;
}
