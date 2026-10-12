(** Portable interpreter semantics for BIP173 Bech32 and BIP350 Bech32m.
    Payload strings contain numeric 5-bit values, not alphabet characters.
    Error codes match the public Motoko module: 1 length, 2 HRP, 3 mixed case,
    4 character, 5 checksum, 6 data, 7 padding, and 8 bit width. *)

(** [encode hrp payload bech32m] emits lowercase text. An all-uppercase HRP
    is accepted, but a mixed-case HRP is rejected. *)
val encode : string -> string -> bool -> (string, int) result

(** Returns the lowercase HRP, payload without checksum, and [true] for
    Bech32m or [false] for Bech32. *)
val decode : string -> ((string * string * bool), int) result

(** Repack most-significant bits between widths 1 through 8. Without padding,
    reject nonzero trailing bits and a trailing group at least [from_bits]
    bits long. Input and output are limited to 16 MiB each. *)
val convert_bits : string -> int -> int -> bool -> (string, int) result
