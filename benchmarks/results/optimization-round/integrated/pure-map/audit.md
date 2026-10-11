Independent review completed 2026-10-11. The [proof](proof.json) correctly identifies a startup-only executable difference between the measured `f1ccbba5e445df9db03bbc35be557187ade9b436` builds and the final `c320bf90d0b63a058b5de2c41a42c96e8b82243f` builds. The full Wasm binaries and executable sections are **not byte-identical**. Every benchmark function body is unchanged; this review adds no new PocketIC measurements.

Checked the original and final binary hashes against their provenance, identical actor source and plugin source hashes, and identical pinned dependencies. Independently parsed the Wasm sections and code bodies without applying a generalized normalization:

| Actor | Code-section function bodies | Sole changed initializer | Version data segment |
| --- | ---: | --- | ---: |
| functions | 1,528 | `$alloc_484` | 234 |
| bulk | 824 | `$alloc_146` | 83 |
| point | 824 | `$alloc_146` | 83 |

Each changed function body has identical length and exactly two changed bytes, at body offsets 9 and 32: the `i64.const` allocation length and `i32.const` copy length change from 18 to 19. The data section changes only the length-prefixed compiler version from `2.0.0-9-gf1ccbba5e` to `2.0.0-10-gc320bf90d`; the compiler custom section changes the same string. Every other section and function body is identical.

Independently checked the exclusive direct caller chain in all three disassemblies: module start → `$link_start.2` → `$link_start.1` → `$link_start` → `$rts_start` → `$initialize_root_array` → the initializer above. These calls execute before the timed benchmark methods. The RTS rounds both string lengths to three 64-bit payload words, so the static blob occupies the same heap allocation extent. Installation instruction cost is outside this conclusion.

The [raw differences and initialization excerpts](README.md) support the narrow conclusion. The [111-case function table](../../pure-map/functions/costs.md), [bulk table](../../pure-map/bulk/costs.md), and [point table](../../pure-map/point/costs.md) retain their original frozen-`f1ccbba5e` measurement provenance. They must not be relabeled as newly measured final-compiler results.
