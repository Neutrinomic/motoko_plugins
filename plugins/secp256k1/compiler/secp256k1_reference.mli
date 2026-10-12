(* Variable-time portable interpreter semantics, with strict SEC1/DER parsing. *)
module Z : sig
  type t = Big_int.big_int
  val zero : t
  val of_int : int -> t
  val of_string : string -> t
  val add : t -> t -> t
  val shift_left : t -> int -> t
  val sign : t -> int
  val compare : t -> t -> int
end
type curve = { p : Z.t; n : Z.t; a : Z.t; b : Z.t; gx : Z.t; gy : Z.t }
val secp256k1 : curve
val ec_public_key : curve -> string -> bool -> string option
val ec_public_key_convert : curve -> string -> bool -> string option
val ec_point_add : curve -> string -> string -> bool -> string option
val ec_point_mul : curve -> string -> string -> bool -> string option
val ec_public_key_tweak_add : curve -> string -> string -> bool -> string option
val ec_ecdsa_sign : ?low_s:bool -> curve -> string -> string -> string option
val ec_ecdsa_verify : ?low_s:bool -> curve -> string -> string -> string -> bool
val ec_normalize_signature : curve -> string -> string option
val ec_compact_to_der : curve -> string -> string option
val ec_der_to_compact : curve -> string -> string option
val public_key : string -> bool -> (string, string) result
val public_key_convert : string -> bool -> (string, string) result
val point_add : string -> string -> bool -> (string, string) result
val point_mul : string -> string -> bool -> (string, string) result
val base_multiply : string -> bool -> (string, string) result
val public_key_tweak_add : string -> string -> bool -> (string, string) result
val ecdsa_sign : string -> string -> (string, string) result
val ecdsa_verify : string -> string -> string -> (bool, string) result
val compact_to_der : string -> (string, string) result
val der_to_compact : string -> (string, string) result
val normalize_signature : string -> (string, string) result
val xonly_public_key : string -> (string, string) result
val xonly_tweak_add : string -> string -> (string, string) result
val xonly_tweak_secret : string -> string -> (string, string) result
val schnorr_sign : string -> string -> string -> (string, string) result
val schnorr_verify : string -> string -> string -> (bool, string) result
