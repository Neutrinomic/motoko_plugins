/* Round-five caller boundary tests. All keys are published test fixtures.
 * Prepared contexts obey the SDK's eight-byte alignment guarantee. Raw Blob
 * bytes and output bytes deliberately use unaligned storage. Outputs are fresh
 * and disjoint, as guaranteed by the compiler bridge; read-only inputs alias. */
#include <assert.h>
#include <stdio.h>
#include "rsa.c"
#include "vectors.h"

typedef struct { uint64_t prefix; unsigned char bytes[1840]; uint64_t suffix; } context;
static void sentinels(const unsigned char *p, size_t size, size_t start, size_t len) {
    for (size_t i = 0; i < size; ++i)
        if (i < start || i >= start + len) assert(p[i] == 0xa5);
}
static void sign_case(const unsigned char *key, const context *secret, const context *public,
    const unsigned char *message, size_t length, const unsigned char *salt,
    const unsigned char *digest, const unsigned char *expected, unsigned prehash, size_t offset)
{
    unsigned char out[400], other[400];
    memset(out, 0xa5, sizeof out); memset(other, 0xa5, sizeof other);
    assert(rsa_impl_sign(key, 960, message, length, salt, 32, out+offset, prehash) == 384);
    assert(rsa_impl_sign_prepared(secret->bytes, 1840, message, length, salt, 32, other+offset, prehash) == 384);
    assert(!memcmp(out+offset, expected, 384)); assert(!memcmp(other+offset, expected, 384));
    sentinels(out, sizeof out, offset, 384); sentinels(other, sizeof other, offset, 384);
    assert(rsa_impl_verify_prepared(public->bytes, 824, message, length, out+offset, 384, prehash) == 1);
    assert(rsa_impl_verify_prepared(public->bytes, 824, digest, 32, out+offset, 384, 1) == 1);
}
int main(void) {
    context public, secret;
    memset(&public, 0xa5, sizeof public); memset(&secret, 0xa5, sizeof secret);
    assert(rsa_impl_prepare_public_key(raw_public, 384, public.bytes) == 824);
    assert(rsa_impl_prepare_secret_key(raw_key, 960, secret.bytes) == 1840);
    const context saved_public = public, saved_secret = secret;
    for (size_t offset = 1; offset <= 7; offset += 6) {
        unsigned char key[976], pub[400], digest[48], salt[48], sig[400];
        memset(key, 0xa5, sizeof key); memcpy(key+offset, raw_key, 960);
        memset(pub, 0xa5, sizeof pub); memcpy(pub+offset, raw_public, 384);
        memset(digest, 0xa5, sizeof digest); memcpy(digest+offset, digest2, 32);
        memset(salt, 0xa5, sizeof salt); memcpy(salt+offset, salt1, 32);
        memset(sig, 0xa5, sizeof sig); memcpy(sig+offset, signature2, 384);
        // Key is also the message, and salt crosses the q/dP component boundary.
        sign_case(key+offset, &secret, &public, key+offset, 960, key+offset+383,
                  digest0, signature0, 0, offset);
        // The same borrowed 32 bytes serve as both message/digest and salt.
        sign_case(key+offset, &secret, &public, salt+offset, 32, salt+offset,
                  digest1, signature1, 0, offset);
        sign_case(key+offset, &secret, &public, digest+offset, 32, digest+offset,
                  digest2, signature2, 1, offset);
        sign_case(key+offset, &secret, &public, message3, sizeof message3, salt3,
                  digest3, signature3, 0, offset);
        assert(rsa_impl_verify(pub+offset, 384, digest+offset, 32, sig+offset, 384, 1) == 1);
        // Public key and signature aliases must preserve integer-range errors.
        assert(rsa_impl_verify(pub+offset, 384, pub+offset, 384, pub+offset, 384, 0) == INVALID_SIGNATURE);
        assert(rsa_impl_verify_prepared(public.bytes, 824, sig+offset, 384, sig+offset, 384, 0) == 0);
        assert(!memcmp(key+offset, raw_key, 960)); assert(!memcmp(pub+offset, raw_public, 384));
        assert(!memcmp(digest+offset, digest2, 32)); assert(!memcmp(salt+offset, salt1, 32));
        assert(!memcmp(sig+offset, signature2, 384));
        sentinels(key, sizeof key, offset, 960); sentinels(pub, sizeof pub, offset, 384);
        sentinels(digest, sizeof digest, offset, 32); sentinels(salt, sizeof salt, offset, 32);
        sentinels(sig, sizeof sig, offset, 384);
        // Factories must accept unaligned source bytes; only destinations need alignment.
        context copy; memset(&copy, 0xa5, sizeof copy);
        assert(rsa_impl_prepare_secret_key(key+offset, 960, copy.bytes) == 1840);
        assert(!memcmp(&copy, &saved_secret, sizeof copy));
        memset(&copy, 0xa5, sizeof copy);
        assert(rsa_impl_prepare_public_key(pub+offset, 384, copy.bytes) == 824);
        assert(!memcmp(&copy, &saved_public, sizeof copy));
    }
    for (size_t i = 0; i < sizeof malformed / sizeof malformed[0]; ++i) {
        assert(rsa_impl_verify(raw_public, 384, boundary_digest, 32, malformed[i], 384, 1) == 0);
        assert(rsa_impl_verify_prepared(public.bytes, 824, boundary_digest, 32, malformed[i], 384, 1) == 0);
    }
    // Invalid public lengths must reject before any input access, including SIZE_MAX.
    unsigned char out[400]; memset(out, 0xa5, sizeof out);
    for (size_t i = 0; i < 2; ++i) {
        size_t bad = i == 0 ? 0 : SIZE_MAX;
        assert(rsa_impl_validate_private_key(NULL, bad) == INVALID_SECRET);
        assert(rsa_impl_validate_public_key(NULL, bad) == INVALID_PUBLIC);
        assert(rsa_impl_sign(NULL, bad, NULL, 32, NULL, 32, out+1, 1) == INVALID_SECRET);
        assert(rsa_impl_verify(NULL, bad, NULL, 32, NULL, 384, 1) == INVALID_PUBLIC);
        assert(rsa_impl_sign(raw_key, 960, NULL, bad, NULL, 32, out+1, 1) == INVALID_DIGEST);
        assert(rsa_impl_sign_prepared(secret.bytes, 1840, NULL, bad, NULL, 32, out+1, 1) == INVALID_DIGEST);
        assert(rsa_impl_sign(raw_key, 960, NULL, 32, NULL, bad, out+1, 1) == INVALID_SALT);
        assert(rsa_impl_sign_prepared(secret.bytes, 1840, NULL, 32, NULL, bad, out+1, 1) == INVALID_SALT);
        assert(rsa_impl_verify(raw_public, 384, NULL, bad, NULL, 384, 1) == INVALID_DIGEST);
        assert(rsa_impl_verify_prepared(public.bytes, 824, NULL, bad, NULL, 384, 1) == INVALID_DIGEST);
        assert(rsa_impl_verify(raw_public, 384, NULL, 32, NULL, bad, 1) == INVALID_SIGNATURE);
        assert(rsa_impl_verify_prepared(public.bytes, 824, NULL, 32, NULL, bad, 1) == INVALID_SIGNATURE);
    }
    assert(!memcmp(&public, &saved_public, sizeof public));
    assert(!memcmp(&secret, &saved_secret, sizeof secret));
    puts("8 direct/prepared aliased signing cases, unaligned raw I/O and factory sources, 22 malformed PSS cases, 24 null-input length/precedence rejections: pass");
    return 0;
}
