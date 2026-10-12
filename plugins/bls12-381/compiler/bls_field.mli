(* Portable BLS12-381 reference arithmetic. Elements produced here are reduced. *)
val p : Z.t
val r : Z.t
val z_of_be : string -> Z.t
val be_of_z : int -> Z.t -> string

module type FIELD = sig
  type t
  val zero : t
  val one : t
  val of_z : Z.t -> t
  val of_int : int -> t
  val equal : t -> t -> bool
  val is_zero : t -> bool
  val add : t -> t -> t
  val sub : t -> t -> t
  val neg : t -> t
  val mul : t -> t -> t
  val square : t -> t
  val inv : t -> t
  val div : t -> t -> t
  val pow : t -> Z.t -> t
  val sqrt : t -> t option
  (* Lexicographically largest sign used by compressed encodings. *)
  val sign : t -> bool
  (* RFC 9380 sgn0, based on parity, real component first for Fp2. *)
  val sgn0 : t -> bool
end

module Fp : sig
  include FIELD with type t = Z.t
  val modulus : Z.t
  val of_bytes : string -> (t, string) result
  val to_bytes : t -> string
end

module Fp2 : sig
  include FIELD with type t = Fp.t * Fp.t
  (* Input is canonical real component followed by imaginary component. *)
  val of_bytes : string -> (t, string) result
  val to_bytes : t -> string
end
