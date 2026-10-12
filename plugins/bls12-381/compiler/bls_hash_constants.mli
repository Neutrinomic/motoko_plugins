(** RFC 9380 BLS12-381 SWU, isogeny, and effective-cofactor constants. *)
val iso_11_a : Z.t
val iso_11_b : Z.t
val iso_11_z : Z.t
val iso_3_a : Z.t * Z.t
val iso_3_b : Z.t * Z.t
val iso_3_z : Z.t * Z.t
val h_eff_g1 : Z.t
val h_eff_g2 : Z.t
val iso_11_map_coefficients : Z.t array array
val iso_3_map_coefficients : (Z.t * Z.t) array array
