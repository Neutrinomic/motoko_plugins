(* The small arbitrary-precision API required by the portable BLS references.
   It uses the Num library already linked into the Motoko compiler host. *)
type t = Big_int.big_int
val zero : t
val one : t
val minus_one : t
val of_int : int -> t
val to_int : t -> int
val of_string : string -> t
val to_string : t -> string
val add : t -> t -> t
val sub : t -> t -> t
val mul : t -> t -> t
val neg : t -> t
val succ : t -> t
val pred : t -> t
val sign : t -> int
val compare : t -> t -> int
val equal : t -> t -> bool
val erem : t -> t -> t
val div : t -> t -> t
val pow : t -> int -> t
val shift_left : t -> int -> t
val shift_right : t -> int -> t
val extract : t -> int -> int -> t
val testbit : t -> int -> bool
val numbits : t -> int
val invert : t -> t -> t
val powm : t -> t -> t -> t
val ( + ) : t -> t -> t
val ( - ) : t -> t -> t
val ( * ) : t -> t -> t
