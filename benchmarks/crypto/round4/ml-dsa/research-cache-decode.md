# Prepared ML-DSA cache decoding candidate

**Proposal only; not applied, compiled or benchmarked.** Replace the nested
`array::from_fn` in `Reader::vector` with an explicitly initialized destination
filled through borrowed iterators. Leave `Reader::matrix` and all cryptographic
arithmetic unchanged. This targets existing redundant copies and coefficient
bounds checks, with no unsafe code or prepared-layout change.

## Pinned evidence

- Source baseline: plugins commit `0e1e96a`.
- Source: `plugins/ml-dsa/runtime/vendor/fips204/src/motoko_prepared.rs`, lines 37–48;
  SHA-256 `ea2d339d4e57e0e1f438b18111ba598b4ab282ef8fd84a1df17b3e264dd214e9`.
- Inspected delivered baseline runtime:
  `_build/prepared-crypto/integration/dist/ml-dsa/runtime.wasm`;
  SHA-256 `07ae75432d55ddcbb4741f0d0aa40bb0d086f365d1c68c0648bde3dd20850c3f`.
- Read-only disassembly: WABT `wasm2wat --enable-memory64`, version 1.0.36,
  and `wasm-objdump -d`. No build or measurement was run.

`Reader::vector` is Wasm function 22,
`_RNvMs_NtCsl148ggKCHvF_7fips20415motoko_preparedNtB4_6Reader6vector`.
Its body begins at file offset `0x01951a`; the next function begins at `0x019991`.
The stack subtraction at `0x019523` requests **9,216 bytes**.
The corresponding WAT function occupies lines **46,590–47,127**.

There are **21 `memory.copy` instructions**: twenty copies of 1,024 bytes and a
final 4,096-byte copy, totaling **24,576 bytes copied to return a 4,096-byte vector**.
Their file offsets are:

```text
0195f9 01960c 01961f 019632 019641
0196e9 0196fc 01970f 019722 019735
0197c4 0197d7 0197ea 0197fd 019810
0198a2 0198b5 0198c8 0198db 0198ee
0198f9  (the final 4,096-byte copy)
```

The coefficient loop also checks each four-byte subrange and retains calls to
`core::slice::index::slice_index_fail`. Prepared verification invokes this vector
decoder five times (one key vector plus four matrix rows), and signing invokes
it seven times (three key vectors plus four matrix rows). Thus these vector
return copies alone total 120 KiB and 168 KiB respectively, excluding other
caller/matrix copies. These are static code facts, not measured cost savings.

The specialized `ntt<4>` and `inv_ntt<4>` functions contain no calls or
`unreachable` instructions in this baseline. Rewriting their indexed loops just
to remove bounds checks therefore lacks the concrete opportunity seen here.
Montgomery arithmetic should remain untouched in this candidate.

## Exact proposed production diff

```diff
--- a/plugins/ml-dsa/runtime/vendor/fips204/src/motoko_prepared.rs
+++ b/plugins/ml-dsa/runtime/vendor/fips204/src/motoko_prepared.rs
@@ -43,7 +43,20 @@
         value
     }
     fn vector(&mut self) -> [T; 4] {
-        core::array::from_fn(|_| T(core::array::from_fn(|_| i32::from_le_bytes(self.bytes()))))
+        const VECTOR_BYTES: usize = 4 * 256 * 4;
+        let encoded = &self.bytes[self.offset..self.offset + VECTOR_BYTES];
+        self.offset += VECTOR_BYTES;
+        let mut value = [crate::types::T0; 4];
+        for (coefficient, bytes) in value
+            .iter_mut()
+            .flat_map(|polynomial| polynomial.0.iter_mut())
+            .zip(encoded.chunks_exact(4))
+        {
+            *coefficient = i32::from_le_bytes(
+                bytes.try_into().expect("fixed coefficient size"),
+            );
+        }
+        value
     }
     fn matrix(&mut self) -> Matrix { core::array::from_fn(|_| self.vector()) }
 }
```

One checked 4,096-byte slice feeds exactly 1,024 signed little-endian
coefficients in the original polynomial/element order. `chunks_exact(4)` makes
the conversion's size requirement explicit. The initialized `[T; 4]` retains
its existing `ZeroizeOnDrop` behavior; no native-layout casts, uninitialized
references or removal of secret cleanup are introduced. The input remains
immutable and protected by the existing factory/type boundary. Public/secret
payloads remain 20,576/28,800 bytes.

After applying, first inspect generated Wasm to verify that the compiler really
removes the copy chain and inner slice checks; source simplification alone does
not establish a win. Run existing native/reference/official-vector and prepared
GC tests, then compare hot verification and signing for cases 4, 6, 11 and 362,
plus representative cold/direct controls. Record instructions, allocation,
runtime Wasm size and stack frame size. The intended gains are confined to
prepared consumers; no direct-path speedup or percentage is claimed in advance.
