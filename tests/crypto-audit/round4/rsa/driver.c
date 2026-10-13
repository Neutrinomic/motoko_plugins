/* Reuse the prior corpus read-only. The generic public and original-8U
 * private oracles are linked to original Montgomery arithmetic this round. */
#define main prepared_corpus_main
#define br_rsa_i31_public audit_upstream_public
#include "../../prepared/rsa/driver.c"
#undef br_rsa_i31_public
#undef main
extern void audit_alias_counts(void);
int main(int argc, char **argv) {
    int result = prepared_corpus_main(argc, argv);
    audit_alias_counts();
    return result;
}
