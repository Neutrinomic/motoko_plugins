(* Portable reference semantics for the Motoko interpreters. *)
val digest : string -> string

(* Streaming states are canonical 104-byte values. These operations never mutate
   their input, so a saved state can be finalized or branched more than once.
   Malformed states return Error "RIPEMD160: invalid state". update returns
   Error "RIPEMD160: message too long" if the total would exceed 2^61 - 1 bytes. *)
val init : unit -> string
val update : string -> string -> (string, string) result
val finalize : string -> (string, string) result
