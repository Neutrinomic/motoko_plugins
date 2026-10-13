/* Independent test instrumentation; never linked into the plugin. */
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include "inner.h"

extern void audit_candidate_montymul(uint32_t *, const uint32_t *,
    const uint32_t *, const uint32_t *, uint32_t);
extern void audit_upstream_montymul(uint32_t *, const uint32_t *,
    const uint32_t *, const uint32_t *, uint32_t);
static uint64_t calls, squares, adjacent, sizes[128];

/* Address-range comparison is test instrumentation for this native platform;
 * do not use relational pointer comparisons across unrelated C objects. */
static int disjoint(const void *a, const void *b, size_t bytes) {
    uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
    return x > y ? x - y >= bytes : y - x >= bytes;
}
void br_i31_montymul(uint32_t *d, const uint32_t *x, const uint32_t *y,
    const uint32_t *m, uint32_t m0i) {
    size_t limbs = (m[0] + 31) >> 5, bytes = (limbs + 1) * sizeof *d;
    assert(limbs < 128);
    assert(disjoint(d, x, bytes) && disjoint(d, y, bytes) && disjoint(d, m, bytes));
    calls++; squares += x == y; sizes[limbs]++;
    uintptr_t dest = (uintptr_t)d, input = (uintptr_t)x;
    adjacent += dest > input ? dest - input <= bytes + 4 : input - dest <= bytes + 4;
    audit_candidate_montymul(d, x, y, m, m0i);
}
void audit_alias_counts(void) {
    printf("Montgomery alias checks: %" PRIu64 " calls, %" PRIu64
        " same-input squares, %" PRIu64 " adjacent destination/input ranges\n",
        calls, squares, adjacent);
    for (size_t i = 0; i < 128; i++) if (sizes[i])
        printf("  %zu limbs: %" PRIu64 " calls\n", i, sizes[i]);
}

#ifdef AUDIT_RAW_MAIN
static uint32_t read32(FILE *f) {
    unsigned char b[4]; assert(fread(b, 1, 4, f) == 4);
    return (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}
int main(int argc, char **argv) {
    assert(argc == 2); FILE *f = fopen(argv[1], "rb"); assert(f);
    unsigned count = read32(f), checked = 0;
    for (unsigned i = 0; i < count; i++) {
        size_t limbs = read32(f), same = read32(f), words = limbs + 1;
        uint32_t input[3][128] = {{0}}, expected[128] = {0}, original[128];
        assert(limbs && limbs < 128);
        for (size_t j = 0; j < 3; j++) for (size_t k = 0; k < words; k++) input[j][k] = read32(f);
        for (size_t k = 0; k < words; k++) expected[k] = read32(f);
        uint32_t inverse = br_i31_ninv31(input[2][1]);
        audit_upstream_montymul(original, input[0], same ? input[0] : input[1], input[2], inverse);
        assert(!memcmp(original, expected, words * sizeof *expected));
        /* Every destination ordering in one enclosing allocation, including
         * exact adjacency. Shared enclosing arrays are legal under restrict. */
        for (size_t dest = 0; dest < 4; dest++) {
            uint32_t storage[4 * 128 + 2], saved[4 * 128 + 2];
            for (size_t k = 0; k < sizeof storage / sizeof storage[0]; k++) storage[k] = 0xa5a5a5a5;
            uint32_t *d = storage + 1 + dest * words;
            const uint32_t *in[3]; size_t next = 0;
            for (size_t slot = 0; slot < 4; slot++) if (slot != dest) {
                uint32_t *p = storage + 1 + slot * words;
                memcpy(p, input[next], words * sizeof *p); in[next++] = p;
            }
            memcpy(saved, storage, sizeof saved);
            br_i31_montymul(d, in[0], same ? in[0] : in[1], in[2], inverse);
            assert(!memcmp(d, expected, words * sizeof *d));
            memcpy(saved + (d - storage), expected, words * sizeof *d);
            assert(!memcmp(saved, storage, sizeof saved)); checked++;
        }
    }
    assert(fgetc(f) == EOF); fclose(f);
    printf("%u raw Montgomery cases, %u destination orderings: Python/upstream/candidate, guards and inputs pass\n", count, checked);
    audit_alias_counts(); return 0;
}
#endif
