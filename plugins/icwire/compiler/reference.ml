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
type state = {input : string; mutable at : int;
  mutable depth : int; mutable items : int; output_limit : int}
let max_bytes = Schema.max_bytes
let max_items = 1_000_000
let max_depth = 128
let max_integer_bytes = 4096
let state ?(output_limit = max_bytes) input = {input; at = 0; depth = 0; items = 0; output_limit}
let fail_at offset kind = raise (Invalid {kind; offset})
let fail s kind = fail_at s.at kind
let charge s = s.items <- s.items + 1; if s.items > max_items then fail s "limit"
let enter s = charge s; s.depth <- s.depth + 1; if s.depth > max_depth then fail s "limit"
let leave s = s.depth <- s.depth - 1
let collection s n = if n > max_items - s.items then fail s "limit"
let take (s : state) n =
  if n > String.length s.input - s.at then fail s "truncated";
  let data = String.sub s.input s.at n in s.at <- s.at + n; data
let byte s = Char.code (take s 1).[0]
let read_word s width =
  let data = take s width in
  let result = ref 0L in
  String.iteri (fun i ch -> result := Int64.logor !result (Int64.shift_left (Int64.of_int (Char.code ch)) (8 * i))) data;
  !result
let read_length s =
  let start = s.at in
  let rec loop count value =
    let b = byte s in
    if count = 4 && b > 15 then fail_at start "canonical";
    let value = value lor ((b land 127) lsl (7 * count)) in
    if b land 128 <> 0 then loop (count + 1) value else begin
      if count > 0 && b = 0 then fail_at start "canonical";
      value
    end
  in loop 0 0
let read_bool s = let start = s.at in match byte s with
  | 0 -> false | 1 -> true | _ -> fail_at start "bool"
let valid_utf8 data = try ignore (Lib.Utf8.decode data); true with Lib.Utf8.Utf8 -> false
let read_bytes s kind =
  let start = s.at in
  let count = read_length s in
  if count > max_bytes then fail_at start "limit";
  if kind = 2 && count > 29 then fail_at start "principal";
  let data = take s count in
  if kind = 1 && not (valid_utf8 data) then fail_at start "utf8";
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
  | Prim Principal | Obj (Actor, _, _) -> V.Blob (read_bytes s 2)
  | Func (Shared _, _, _, _, _) ->
    let principal = decode_value s (Obj (Actor, [], [])) in
    let method_name = decode_value s (Prim Text) in
    V.Tup [principal; method_name]
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
    V.Obj (List.fold_left (fun values f ->
      V.Env.add f.Type.lab (decode_value s f.typ) values)
      V.Env.empty (Schema.sort_fields fields))
  | Variant fields -> let ordinal = read_length s in
    (match List.nth_opt (Schema.sort_fields fields) ordinal with
      | Some f -> V.Variant (f.lab, decode_value s f.typ)
      | None -> fail s "variant")
  | _ -> invalid_arg "ICWire unsupported reference decoder type"
  in leave s; value

type writer = Buffer.t
let append s out data =
  if String.length data > s.output_limit - s.at then fail s "limit";
  Buffer.add_string out data; s.at <- s.at + String.length data
let write_byte s out value = append s out (String.make 1 (Char.chr value))
let write_word s out width bits =
  append s out (String.init width (fun i -> Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bits (8 * i)) 255L))))
let write_length s out n = append s out (leb (big_int_of_int n) false)
let write_bytes s out kind data =
  if kind = 1 && not (valid_utf8 data) then fail s "utf8";
  if kind = 2 && String.length data > 29 then fail s "principal";
  let prefix = leb (big_int_of_int (String.length data)) false in
  if String.length data + String.length prefix > s.output_limit - s.at then fail s "limit";
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
  | (Prim Principal | Obj (Actor, _, _)), V.Blob value -> write_bytes s out 2 value
  | Func (Shared _, _, _, _, _), V.Tup [principal; method_name] ->
    encode_value s out (Obj (Actor, [], [])) principal;
    encode_value s out (Prim Text) method_name
  | Func (Shared _, _, _, _, _), V.Func _ -> fail s "type"
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
    List.iter (fun f -> encode_value s out f.Type.typ (V.Env.find f.lab values))
      (Schema.sort_fields fields)
  | Variant fields, V.Variant (label, value) ->
    let ordinal, f = List.find (fun (_, f) -> f.Type.lab = label)
      (List.mapi (fun i f -> i, f) (Schema.sort_fields fields)) in
    write_length s out ordinal; encode_value s out f.typ value
  | _ -> invalid_arg "ICWire unsupported reference encoder value");
  leave s
let error_value error = V.Variant ("err", V.Obj (V.Env.empty
  |> V.Env.add "kind" (V.Text error.kind)
  |> V.Env.add "offset" (V.Nat64 (N.Nat64.of_int error.offset))))
let protect action = try Ok (V.Variant ("ok", action ())) with Invalid error -> Ok (error_value error)
let encode _type_arguments types values = match types, values with
  | [typ], [value] -> protect (fun () ->
    let s = state "" and out = Buffer.create 128 in
    encode_value s out typ value;
    V.Blob (Buffer.contents out))
  | _ -> Result.Error "to_icwire expects exactly one argument (parenthesize a tuple argument)"
let encode_bounded _type_arguments types values = match types, values with
  | [typ; _], [value; V.Int limit] -> protect (fun () ->
    let limit = N.Int.to_big_int limit in
    if sign_big_int limit < 0 || gt_big_int limit (big_int_of_int max_bytes) then fail_at 0 "limit";
    let s = state ~output_limit:(int_of_big_int limit) "" and out = Buffer.create 128 in
    encode_value s out typ value;
    V.Blob (Buffer.contents out))
  | _ -> Result.Error "to_icwire_bounded expects a value and a Nat byte bound"
let decode type_arguments _types values = match type_arguments, values with
  | [typ], [V.Blob input] -> protect (fun () ->
    let s = state input in
    if String.length input > max_bytes then fail s "limit";
    let value = decode_value s typ in
    if s.at <> String.length input then fail s "trailing";
    value)
  | _ -> Result.Error "from_icwire expects one explicit type argument and one Blob argument"

(* A counting visitor is independent of both the byte writer and generated
   measurement. It never builds encoded bytes and deliberately accepts all
   float values, because their finite-value check cannot affect wire width. *)
let leb_size n = max 1 ((num_bits_big_int n + 6) / 7)
let rec measure_value s typ value =
  enter s;
  let add n = if n > max_bytes - s.at then fail s "limit" else s.at <- s.at + n in
  let bytes n = add (leb_size (big_int_of_int n) + n) in
  (match Type.normalize typ, value with
  | Prim Null, V.Null -> ()
  | Prim (Bool | Nat8 | Int8), _ -> add 1
  | Prim (Nat16 | Int16), _ -> add 2
  | Prim (Nat32 | Int32 | Char | Float32), _ -> add 4
  | Prim (Nat64 | Int64 | Float), _ -> add 8
  | Prim Text, V.Text value | Prim Blob, V.Blob value -> bytes (String.length value)
  | (Prim Principal | Obj (Actor, _, _)), V.Blob value ->
    if String.length value > 29 then fail s "principal";
    bytes (String.length value)
  | Func (Shared _, _, _, _, _), V.Tup [principal; method_name] ->
    measure_value s (Obj (Actor, [], [])) principal;
    measure_value s (Prim Text) method_name
  | Func (Shared _, _, _, _, _), V.Func _ -> fail s "type"
  | Prim (Nat | Int as p), V.Int value ->
    let n = N.Int.to_big_int value in
    if num_bits_big_int n > max_integer_bytes * 7 then fail s "limit";
    let length = if p = Nat then leb_size n else
      let signless = if sign_big_int n < 0 then pred_big_int (abs_big_int n) else n in
      max 1 ((num_bits_big_int signless + 7) / 7) in
    if length > max_integer_bytes then fail s "limit";
    add length
  | Opt _, V.Null -> add 1
  | Opt typ, V.Opt value -> add 1; measure_value s typ value
  | Tup ts, V.Tup values -> List.iter2 (measure_value s) ts values
  | Array typ, V.Array values ->
    collection s (Array.length values);
    add (leb_size (big_int_of_int (Array.length values)));
    Array.iter (measure_value s typ) values
  | Obj (Object, fields, _), V.Obj values ->
    List.iter (fun f -> measure_value s f.Type.typ (V.Env.find f.lab values))
      (Schema.sort_fields fields)
  | Variant fields, V.Variant (label, value) ->
    let ordinal, f = List.find (fun (_, f) -> f.Type.lab = label)
      (List.mapi (fun i f -> i, f) (Schema.sort_fields fields)) in
    add (leb_size (big_int_of_int ordinal)); measure_value s f.typ value
  | _ -> invalid_arg "ICWire unsupported reference size value");
  leave s

let estimate _type_arguments types values = match types, values with
  | [typ], [value] ->
    let size = try
      let s = state "" in measure_value s typ value; Int64.of_int s.at
      with Invalid _ -> 0x1fffffffffffffffL in
    Ok (V.Int (N.Int.of_big_int (big_int_of_int64 size)))
  | _ -> Result.Error "icwire_estimate_size expects exactly one argument (parenthesize a tuple argument)"
