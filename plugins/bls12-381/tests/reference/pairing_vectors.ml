(* Algebraic regression tests for the portable pairing-product reference.
   These assertions test nondegeneracy, bilinearity and the product identity;
   expected results do not depend on the Rust implementation. *)
let checks = ref 0

let check name expected pairs =
  let started = Sys.time () in
  let actual = Bls_pairing.pairing_check pairs in
  Printf.printf "%s: %b (%0.3fs)\n%!" name actual (Sys.time () -. started);
  if actual <> expected then failwith name;
  incr checks

let () =
  let open Bls_group in
  let p = G1.generator and q = G2.generator in
  check "empty" true [];
  check "G1 infinity" true [G1.Infinity, q];
  check "G2 infinity" true [p, G2.Infinity];
  check "generator nontrivial" false [p, q];
  check "inverse G1 cancellation" true [p, q; G1.neg p, q];
  check "inverse G2 cancellation" true [p, q; p, G2.neg q];
  check "bilinearity scalar 2" true
    [G1.mul p (Z.of_int 2), q; G1.neg p, G2.mul q (Z.of_int 2)];
  check "bilinearity scalar 17" true
    [G1.mul p (Z.of_int 17), q; G1.neg p, G2.mul q (Z.of_int 17)];
  check "mismatched scalar 17/18" false
    [G1.mul p (Z.of_int 17), q; G1.neg p, G2.mul q (Z.of_int 18)];
  let a = Z.of_string
      "0x102030405060708090a0b0c0d0e0f101112131415161718192021222324252627" in
  let b = Z.of_string
      "0x42434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f6061" in
  let ab = Z.erem (Z.mul a b) Bls_field.r in
  check "large scalar bilinearity" true
    [G1.mul p a, G2.mul q b; G1.neg (G1.mul p ab), q];
  check "large scalar mismatch" false
    [G1.mul p a, G2.mul q b; G1.neg (G1.mul p (Z.succ ab)), q];
  check "three-pair product" true
    [G1.mul p a, q; G1.mul p b, q; G1.neg (G1.mul p (Z.add a b)), q];
  Printf.printf "Pairing: all %d algebraic regression cases passed\n" !checks
