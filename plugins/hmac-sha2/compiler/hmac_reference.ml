(* Canonical, bounded HMAC contexts matching runtime/src/lib.rs exactly. *)
type algorithm = {
  tag : int;
  block : int;
  length_bytes : int;
  initial : string;
  compress : string -> string -> int -> string;
  hash : string -> string;
}
let words32 words =
  let out = Bytes.create 32 in
  Array.iteri (fun i w -> Bytes.set_int32_be out (i * 4) w) words;
  Bytes.unsafe_to_string out
let words64 words =
  let out = Bytes.create 64 in
  Array.iteri (fun i w -> Bytes.set_int64_be out (i * 8) w) words;
  Bytes.unsafe_to_string out
let alg bits =
  if bits = 256 then {
    tag = 32; block = 64; length_bytes = 8;
    initial = words32 (Sha256_core.initial ());
    compress = (fun state input offset ->
      let words = Array.init 8 (fun i -> String.get_int32_be state (i * 4)) in
      Sha256_core.compress words input offset; words32 words);
    hash = Sha256_reference.digest;
  } else {
    tag = 64; block = 128; length_bytes = 16;
    initial = words64 (Sha512_reference.initial false);
    compress = (fun state input offset ->
      let words = Array.init 8 (fun i -> String.get_int64_be state (i * 8)) in
      Sha512_reference.compress words input offset; words64 words);
    hash = Sha512_reference.digest;
  }
let read_count input offset length =
  let n = ref Big_int.zero_big_int in
  for i = 0 to length - 1 do
    n := Big_int.add_big_int (Big_int.shift_left_big_int !n 8) (Big_int.big_int_of_int (Char.code input.[offset + i]))
  done; !n
let write_count out offset length count =
  for i = 0 to length - 1 do
    Bytes.set out (offset + i)
      (Char.chr (Big_int.int_of_big_int (Big_int.extract_big_int count ((length - 1 - i) * 8) 8)))
  done
let max_count a = Big_int.pred_big_int (Big_int.shift_left_big_int Big_int.unit_big_int (a.length_bytes * 8 - 3))
type context = { inner : string; outer : string; count : Big_int.big_int; tail : string }
let encode a ctx =
  let out = Bytes.make (a.tag * 2 + a.length_bytes + a.block) '\x00' in
  Bytes.blit_string ctx.inner 0 out 0 a.tag;
  Bytes.blit_string ctx.outer 0 out a.tag a.tag;
  write_count out (a.tag * 2) a.length_bytes ctx.count;
  Bytes.blit_string ctx.tail 0 out (a.tag * 2 + a.length_bytes) (String.length ctx.tail);
  Bytes.unsafe_to_string out
let decode a input =
  if String.length input <> a.tag * 2 + a.length_bytes + a.block then None else
  let count = read_count input (a.tag * 2) a.length_bytes in
  if Big_int.lt_big_int count (Big_int.big_int_of_int a.block) || Big_int.gt_big_int count (max_count a) then None else
  let used = Big_int.int_of_big_int (Big_int.mod_big_int count (Big_int.big_int_of_int a.block)) in
  let offset = a.tag * 2 + a.length_bytes in
  let valid = ref true in
  for i = used to a.block - 1 do if input.[offset + i] <> '\x00' then valid := false done;
  if not !valid then None else Some {
    inner = String.sub input 0 a.tag;
    outer = String.sub input a.tag a.tag;
    count;
    tail = String.sub input offset used;
  }
let init bits key =
  let a = alg bits in
  let key = if String.length key > a.block then a.hash key else key in
  let pad byte = String.init a.block (fun i ->
    Char.chr ((if i < String.length key then Char.code key.[i] else 0) lxor byte)) in
  encode a {inner = a.compress a.initial (pad 0x36) 0;
    outer = a.compress a.initial (pad 0x5c) 0;
    count = Big_int.big_int_of_int a.block; tail = ""}
let update_context a ctx input =
  let count = Big_int.add_big_int ctx.count (Big_int.big_int_of_int (String.length input)) in
  if Big_int.gt_big_int count (max_count a) then None else
  let inner = ref ctx.inner in
  let pos = ref 0 in
  let tail = ref ctx.tail in
  if String.length !tail > 0 then begin
    let take = min (a.block - String.length !tail) (String.length input) in
    tail := !tail ^ String.sub input 0 take;
    pos := take;
    if String.length !tail = a.block then begin
      inner := a.compress !inner !tail 0; tail := ""
    end
  end;
  while !pos + a.block <= String.length input do
    inner := a.compress !inner input !pos; pos := !pos + a.block
  done;
  if !pos < String.length input then
    tail := !tail ^ String.sub input !pos (String.length input - !pos);
  Some {ctx with inner = !inner; count; tail = !tail}
let update bits state input =
  let a = alg bits in
  Option.bind (decode a state) (fun ctx -> Option.map (encode a) (update_context a ctx input))
let finish a state count tail =
  let size = if String.length tail < a.block - a.length_bytes then a.block else a.block * 2 in
  let padding = Bytes.make size '\x00' in
  Bytes.blit_string tail 0 padding 0 (String.length tail);
  Bytes.set padding (String.length tail) '\x80';
  write_count padding (size - a.length_bytes) a.length_bytes (Big_int.shift_left_big_int count 3);
  let padding = Bytes.unsafe_to_string padding in
  let state = a.compress state padding 0 in
  if size = a.block then state else a.compress state padding a.block
let sum_context a ctx =
  let inner = finish a ctx.inner ctx.count ctx.tail in
  finish a ctx.outer (Big_int.big_int_of_int (a.block + a.tag)) inner
let sum bits state =
  let a = alg bits in Option.map (sum_context a) (decode a state)
let prepared bits state input =
  let a = alg bits in
  Option.bind (decode a state) (fun ctx -> Option.map (sum_context a) (update_context a ctx input))
let digest bits key input =
  match prepared bits (init bits key) input with
  | Some value -> value
  | None -> invalid_arg "HMAC input too long"
