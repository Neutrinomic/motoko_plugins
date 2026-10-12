(** Portable RFC 9380 random-oracle hash-to-curve, using SHA-256 XMD.
    These low-level functions also accept empty domain tags. Public wrappers
    reject them because RFC 9380 section 3.1 requires nonempty domain
    separation. Tags longer than 255 bytes use the RFC oversized-tag rule. *)
val hash_g1 : dst:string -> string -> Bls_group.G1.t
val hash_g2 : dst:string -> string -> Bls_group.G2.t

(** Simplified SWU, isogeny, and effective cofactor clearing. G1 input is a
    canonical 48-byte big-endian Fp element. G2 input consists of two such
    elements in real-then-imaginary (c0 || c1) order. *)
val map_g1 : string -> (Bls_group.G1.t, string) result
val map_g2 : string -> (Bls_group.G2.t, string) result

(** Exposed to independently validate RFC 9380 Appendix K vectors. Raises
    Invalid_argument for lengths outside 0..8160. *)
val expand_message_xmd : dst:string -> length:int -> string -> string
