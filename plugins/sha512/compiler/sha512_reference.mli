(* Portable interpreter semantics for SHA-512 and SHA-384. *)
val digest : string -> string
val digest384 : string -> string

(* Low-level helpers for other portable SHA-2 constructions such as HMAC.
   [initial] returns a fresh array. [compress state input offset] mutates eight
   chaining words in [state] using 128 bytes of [input] starting at [offset]. *)
val initial : bool -> int64 array
val compress : int64 array -> string -> int -> unit

(* [init true] selects SHA-384; [init false] selects SHA-512. States are
   canonical 216-byte strings; malformed states and length overflow return
   [None]. [sum] leaves the serialized state available for further updates. *)
val init : bool -> string
val update : string -> string -> string option
val sum : string -> string option
