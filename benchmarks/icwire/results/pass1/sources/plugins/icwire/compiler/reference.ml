(* Independent executable wire specification for source and IR interpreters.
   Compiled programs use the streaming Rust runtime and generated heap visitors. *)
open Mo_types
open Type
open Mo_values
open Big_int
module V = Value
module N = Numerics

type error = {kind : string; offset : int}
exception Invalid of error
type state = {input : string; mutable at : int; mutable bound : int;
  mutable depth : int; mutable items : int}
let max_bytes = Schema.max_bytes
let max_items = 1_000_000
let max_depth = 128
let max_integer_bytes = 4096
let state input = {input; at = 0; bound = String.length input; depth = 0; items = 0}
let fail_at offset kind = raise (Invalid {kind; offset})
let fail s kind = fail_at s.at kind
let charge s = s.items <- s.items + 1; if s.items > max_items then fail s "limit"
let enter s = charge s; s.depth <- s.depth + 1; if s.depth > max_depth then fail s "limit"
let leave s = s.depth <- s.depth - 1
let collection s n = if n > max_items - s.items then fail s "limit"
let take (s : state) n =
  if n > s.bound - s.at then fail s "truncated";
  let data = String.sub s.input s.at n in s.at <- s.at + n; data
let byte s = Char.code (take s 1).[0]
let read_word s width =
  let data = take s width in
  let result = ref 0L in
  String.iteri (fun i ch -> result := Int64.logor !result (Int64.shift_left (Int64.of_int (Char.code ch)) (8 * i))) data;
  !result
let read_length s = Int64.to_int (read_word s 4)
let read_bool s = let start = s.at in match byte s with
  | 0 -> false | 1 -> true | _ -> fail_at start "bool"
let valid_utf8 data = try ignore (Lib.Utf8.decode data); true with Lib.Utf8.Utf8 -> false
let read_bytes s kind =
  let start = s.at in
  let count = read_length s in
  if count > max_bytes then fail_at start "limit";
  let data = take s count in
  if kind = 1 && not (valid_utf8 data) then fail_at start "utf8";
  if kind = 2 && count > 29 then fail_at start "principal";
  data
let leb n signed =
  let out = Buffer.create 8 in
  let rec loop n =
    let b = int_of_big_int (mod_big_int n (big_int_of_int 128)) in
    let next = shift_right_big_int n 7 in
    let done_ = if signed then
      (eq_big_int next zero_big_int && b < 64) ||
      (eq_big_int next (minus_big_int unit_big_int) && b >= 64)
      else eq_big_int next zero_big_int in
    Buffer.add_char out (Char.chr (b lor if done_ then 0 else 128));
    if not done_ then loop next
  in loop n; Buffer.contents out
let read_bigint s signed =
  let start = s.at in
  let rec loop count value =
    if count = max_integer_bytes then fail_at start "limit";
    let b = byte s in
    let value = add_big_int value (shift_left_big_int (big_int_of_int (b land 127)) (7 * count)) in
    if b land 128 <> 0 then loop (count + 1) value else
    let value = if signed && b land 64 <> 0 then
      sub_big_int value (shift_left_big_int unit_big_int (7 * (count + 1))) else value in
    if leb value signed <> String.sub s.input start (s.at - start) then fail_at start "canonical";
    value
  in loop 0 zero_big_int
let unsigned_bigint bits =
  if bits >= 0L then big_int_of_int64 bits
  else add_big_int (big_int_of_int64 bits) (power_int_positive_int 2 64)
let integer_value s prim =
  let signed, width = match prim with
    | Nat -> false, 0 | Int -> true, 0
    | Nat8 -> false, 1 | Nat16 -> false, 2 | Nat32 -> false, 4 | Nat64 -> false, 8
    | Int8 -> true, 1 | Int16 -> true, 2 | Int32 -> true, 4 | Int64 -> true, 8
    | _ -> invalid_arg "ICWire integer_value" in
  let n = if width = 0 then read_bigint s signed else
    let bits = read_word s width in
    let n = unsigned_bigint bits in
    if signed && Int64.logand bits (Int64.shift_left 1L (width * 8 - 1)) <> 0L
      then sub_big_int n (power_int_positive_int 2 (width * 8)) else n in
  match prim with
  | Nat | Int -> V.Int (N.Int.of_big_int n)
  | Nat8 -> V.Nat8 (N.Nat8.of_big_int n) | Nat16 -> V.Nat16 (N.Nat16.of_big_int n)
  | Nat32 -> V.Nat32 (N.Nat32.of_big_int n) | Nat64 -> V.Nat64 (N.Nat64.of_big_int n)
  | Int8 -> V.Int8 (N.Int_8.of_big_int n) | Int16 -> V.Int16 (N.Int_16.of_big_int n)
  | Int32 -> V.Int32 (N.Int_32.of_big_int n) | Int64 -> V.Int64 (N.Int_64.of_big_int n)
  | _ -> invalid_arg "ICWire integer_value"
let rec decode_value s typ =
  enter s;
  let value = match Type.normalize typ with
  | Prim Null -> V.Null
  | Prim Bool -> V.Bool (read_bool s)
  | Prim Text -> V.Text (read_bytes s 1)
  | Prim Blob -> V.Blob (read_bytes s 0)
  | Prim Principal -> V.Blob (read_bytes s 2)
  | Prim Char -> let start = s.at in let code = read_word s 4 in
    if code > 0x10ffffL || (code >= 0xd800L && code <= 0xdfffL) then fail_at start "char";
    V.Char (Int64.to_int code)
  | Prim (Nat | Int | Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) -> integer_value s p
  | Prim (Float | Float32 as p) -> let start = s.at in
    let value = if p = Float then Int64.float_of_bits (read_word s 8)
      else Int32.float_of_bits (Int64.to_int32 (read_word s 4)) in
    if not (Float.is_finite value) then fail_at start "float";
    if p = Float then V.Float (N.Float.of_float value) else V.Float32 (N.Float32.of_float value)
  | Opt typ -> if read_bool s then V.Opt (decode_value s typ) else V.Null
  | Tup ts -> V.Tup (List.map (decode_value s) ts)
  | Array typ -> let count = read_length s in collection s count;
    V.Array (Array.init count (fun _ -> decode_value s typ))
  | Non -> fail s "type"
  | Obj (Object, fields, _) ->
    let count = read_length s in
    if count > s.bound - s.at then fail s "truncated";
    let enclosing = s.bound in
    let ending = s.at + count in s.bound <- ending;
    let values = ref V.Env.empty and previous = ref (-1L) in
    while s.at < ending do
      charge s;
      let tag = read_word s 4 in
      if tag <= !previous then fail s "canonical";
      previous := tag;
      let count = read_length s in
      if count > ending - s.at then fail s "truncated";
      let field_end = s.at + count in
      s.bound <- field_end;
      (match List.find_opt (fun f -> Schema.field_id f.Type.lab = tag) fields with
      | None -> s.at <- field_end
      | Some f ->
        let value = decode_value s f.typ in
        (match Type.normalize f.typ, value with Opt _, V.Null -> fail s "canonical" | _ -> ());
        if s.at <> field_end then fail s "length";
        values := V.Env.add f.lab value !values);
      s.bound <- ending
    done;
    s.bound <- enclosing;
    List.iter (fun f -> if not (V.Env.mem f.Type.lab !values) then match Type.normalize f.typ with
      | Opt _ -> values := V.Env.add f.lab V.Null !values
      | _ -> fail s "missing") fields;
    V.Obj !values
  | Variant fields -> let tag = read_word s 4 in
    (match List.find_opt (fun f -> Schema.field_id f.Type.lab = tag) fields with
      | Some f -> V.Variant (f.lab, decode_value s f.typ)
      | None -> fail s "variant")
  | _ -> invalid_arg "ICWire unsupported reference decoder type"
  in leave s; value

type writer = {out : Buffer.t; mutable patches : (int * int) list}
let append s out data =
  if String.length data > max_bytes - s.at then fail s "limit";
  Buffer.add_string out.out data; s.at <- s.at + String.length data
let write_byte s out value = append s out (String.make 1 (Char.chr value))
let write_word s out width bits =
  append s out (String.init width (fun i -> Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bits (8 * i)) 255L))))
let write_length s out n = write_word s out 4 (Int64.of_int n)
let write_start s out = let start = s.at in write_length s out 0; start
let write_end s out start = out.patches <- (start, s.at - start - 4) :: out.patches
let write_bytes s out kind data =
  if kind = 1 && not (valid_utf8 data) then fail s "utf8";
  if kind = 2 && String.length data > 29 then fail s "principal";
  if String.length data > max_bytes - s.at then fail s "limit";
  write_length s out (String.length data); append s out data
let write_integer s out width signed n =
  if width = 0 then begin
    if num_bits_big_int n > max_integer_bytes * 7 then fail s "limit";
    let data = leb n signed in
    if String.length data > max_integer_bytes then fail s "limit";
    append s out data
  end else
    append s out (String.init width (fun i -> Char.chr (int_of_big_int
      (mod_big_int (shift_right_big_int n (i * 8)) (big_int_of_int 256)))))
let rec encode_value s out typ value =
  enter s;
  (match Type.normalize typ, value with
  | Prim Null, V.Null -> ()
  | Prim Bool, V.Bool value -> write_byte s out (if value then 1 else 0)
  | Prim Text, V.Text value -> write_bytes s out 1 value
  | Prim Blob, V.Blob value -> write_bytes s out 0 value
  | Prim Principal, V.Blob value -> write_bytes s out 2 value
  | Prim Char, V.Char value -> write_word s out 4 (Int64.of_int value)
  | Prim (Nat | Int as p), V.Int n -> write_integer s out 0 (p = Int) (N.Int.to_big_int n)
  | Prim Nat8, V.Nat8 n -> write_integer s out 1 false (N.Nat8.to_big_int n)
  | Prim Nat16, V.Nat16 n -> write_integer s out 2 false (N.Nat16.to_big_int n)
  | Prim Nat32, V.Nat32 n -> write_integer s out 4 false (N.Nat32.to_big_int n)
  | Prim Nat64, V.Nat64 n -> write_integer s out 8 false (N.Nat64.to_big_int n)
  | Prim Int8, V.Int8 n -> write_integer s out 1 true (N.Int_8.to_big_int n)
  | Prim Int16, V.Int16 n -> write_integer s out 2 true (N.Int_16.to_big_int n)
  | Prim Int32, V.Int32 n -> write_integer s out 4 true (N.Int_32.to_big_int n)
  | Prim Int64, V.Int64 n -> write_integer s out 8 true (N.Int_64.to_big_int n)
  | Prim Float, V.Float n -> let value = N.Float.to_float n in
    if not (Float.is_finite value) then fail s "float";
    write_word s out 8 (Int64.bits_of_float value)
  | Prim Float32, V.Float32 n -> let value = N.Float32.to_float n in
    if not (Float.is_finite value) then fail s "float";
    write_word s out 4 (Int64.of_int32 (Int32.bits_of_float value))
  | Opt _, V.Null -> write_byte s out 0
  | Opt typ, V.Opt value -> write_byte s out 1; encode_value s out typ value
  | Tup ts, V.Tup values -> List.iter2 (encode_value s out) ts values
  | Array typ, V.Array values -> collection s (Array.length values);
    write_length s out (Array.length values); Array.iter (encode_value s out typ) values
  | Obj (Object, fields, _), V.Obj values ->
    let start = write_start s out in
    List.iter (fun f ->
      let value = V.Env.find f.Type.lab values in
      match Type.normalize f.typ, value with
      | Opt _, V.Null -> ()
      | _ -> charge s; write_word s out 4 (Schema.field_id f.lab);
        let field_start = write_start s out in
        encode_value s out f.typ value; write_end s out field_start)
      (Schema.sort_fields fields);
    write_end s out start
  | Variant fields, V.Variant (label, value) ->
    let f = List.find (fun f -> f.Type.lab = label) fields in
    write_word s out 4 (Schema.field_id label); encode_value s out f.typ value
  | _ -> invalid_arg "ICWire unsupported reference encoder value");
  leave s
let error_value error = V.Variant ("err", V.Obj (V.Env.empty
  |> V.Env.add "kind" (V.Text error.kind)
  |> V.Env.add "offset" (V.Nat64 (N.Nat64.of_int error.offset))))
let protect action = try Ok (V.Variant ("ok", action ())) with Invalid error -> Ok (error_value error)
let encode _type_arguments types values = match types, values with
  | [typ], [value] -> protect (fun () ->
    let s = state "" and out = {out = Buffer.create 128; patches = []} in
    append s out "ICW1"; encode_value s out typ value;
    let data = Bytes.of_string (Buffer.contents out.out) in
    List.iter (fun (at, n) -> for i = 0 to 3 do Bytes.set data (at + i) (Char.chr ((n lsr (i * 8)) land 255)) done) out.patches;
    V.Blob (Bytes.to_string data))
  | _ -> Result.Error "to_icwire expects exactly one argument (parenthesize a tuple argument)"
let decode type_arguments _types values = match type_arguments, values with
  | [typ], [V.Blob input] -> protect (fun () ->
    let s = state input in
    if String.length input > max_bytes then fail s "limit";
    if take s 4 <> "ICW1" then fail_at 0 "header";
    let value = decode_value s typ in
    if s.at <> String.length input then fail s "trailing";
    value)
  | _ -> Result.Error "from_icwire expects one explicit type argument and one Blob argument"
