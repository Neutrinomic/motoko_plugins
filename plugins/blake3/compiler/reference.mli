(* Portable BLAKE3 interpreter semantics. State blobs use the same canonical
   versioned representation as the Wasm runtime, not native hasher memory. *)
val run : int -> string -> string -> int64 -> int -> (string, string) result
