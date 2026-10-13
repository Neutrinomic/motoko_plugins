(** SHAKE extendable-output functions from FIPS 202. Each context owns its
    sponge state; successive [squeeze] calls continue the same byte stream. *)
type t

val create128 : string -> t
val create256 : string -> t
val squeeze : t -> int -> string
val digest128 : string -> int -> string
val digest256 : string -> int -> string
