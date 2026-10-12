val scalar_of_bytes : string -> (Z.t, string) result
val scalar_to_bytes : Z.t -> string

module G1 : sig
  type t = Infinity | Point of Bls_field.Fp.t * Bls_field.Fp.t
  val infinity : t
  val generator : t
  val is_infinity : t -> bool
  val is_on_curve : t -> bool
  val is_in_subgroup : t -> bool
  val equal : t -> t -> bool
  val add : t -> t -> t
  val neg : t -> t
  (* Multiplication does not reduce scalars, permitting subgroup tests. *)
  val mul : t -> Z.t -> t
  val msm : (t * Z.t) list -> t
  val to_compressed : t -> string
  val of_compressed : string -> (t, string) result
  (* Canonical and on-curve decoding without a subgroup check; internal only. *)
  val of_compressed_unchecked : string -> (t, string) result
end

module G2 : sig
  type t = Infinity | Point of Bls_field.Fp2.t * Bls_field.Fp2.t
  val infinity : t
  val generator : t
  val is_infinity : t -> bool
  val is_on_curve : t -> bool
  val is_in_subgroup : t -> bool
  val equal : t -> t -> bool
  val add : t -> t -> t
  val neg : t -> t
  val mul : t -> Z.t -> t
  val msm : (t * Z.t) list -> t
  (* IETF compressed encoding: imaginary x component precedes real x. *)
  val to_compressed : t -> string
  val of_compressed : string -> (t, string) result
  val of_compressed_unchecked : string -> (t, string) result
end
