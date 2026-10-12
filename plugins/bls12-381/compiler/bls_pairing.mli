(** Portable BLS12-381 pairing-product reference for the interpreter.

    Callers must supply points on their respective curves and in the prime-order
    subgroups. The compressed-point decoders in [Bls_group] enforce these checks.
    Infinity contributes the multiplicative identity; an empty product is true.
    This reference is variable-time and only processes public verification data. *)
val pairing_check : (Bls_group.G1.t * Bls_group.G2.t) list -> bool
