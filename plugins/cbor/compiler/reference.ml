(* Executable specification for the source and IR interpreters. Compiled
   programs use the streaming runtime and specialized managed heap visitors. *)
open Mo_types
open Type
open Mo_values
module V = Value
module N = Numerics
open Big_int

type error = {kind : string; message : string; path : string; offset : int}
exception Invalid of error
type state = {input : string; mutable at : int; mutable depth : int;
  mutable items : int; mutable path : string}
let max_bytes = Schema.max_bytes
let max_items = 1_000_000
let max_depth = 128
let max_integer_bytes = 4096
let fail (s : state) kind message = raise (Invalid {kind; message; path = s.path; offset = s.at})
let state input = {input; at = 0; depth = 0; items = 0; path = ""}
let enter s = s.depth <- s.depth + 1; s.items <- s.items + 1;
  if s.depth > max_depth || s.items > max_items then fail s "limit" "CBOR nesting or item limit exceeded"
let leave s = s.depth <- s.depth - 1
let collection s n = if n > max_items - s.items then fail s "limit" "CBOR nesting or item limit exceeded"
let path_component text =
  let b = Buffer.create (String.length text) in
  String.iter (function '~' -> Buffer.add_string b "~0" | '/' -> Buffer.add_string b "~1" | c -> Buffer.add_char b c) text;
  Buffer.contents b
let at_path (s : state) name action = let saved = s.path in s.path <- saved ^ "/" ^ path_component name;
  let value = action () in s.path <- saved; value
let take s n =
  if n > String.length s.input - s.at then fail s "syntax" "Unexpected end of CBOR input";
  let data = String.sub s.input s.at n in s.at <- s.at + n; data
let magnitude data = String.fold_left (fun n ch -> add_int_big_int (Char.code ch) (mult_int_big_int 256 n)) zero_big_int data
let head s =
  let byte = Char.code (take s 1).[0] in
  let major = byte lsr 5 and additional = byte land 31 in
  let n = match additional with
    | n when n < 24 -> big_int_of_int n
    | n when n < 28 -> magnitude (take s (1 lsl (n - 24)))
    | 31 -> fail s "unsupported" "Indefinite-length CBOR is unsupported"
    | _ -> fail s "syntax" "Reserved CBOR additional information" in
  if major = 7 && additional = 24 && lt_big_int n (big_int_of_int 32) then fail s "syntax" "Invalid CBOR simple value";
  major, additional, n
let typed_head s expected message =
  let major, _, n = head s in if major <> expected then fail s "type" message; n
let read_bytes s major =
  let n = typed_head s major (if major = 3 then "Expected CBOR text" else "Expected CBOR byte string") in
  if gt_big_int n (big_int_of_int max_bytes) then fail s "limit" "CBOR byte limit exceeded";
  let data = take s (int_of_big_int n) in
  if major = 3 then (try ignore (Lib.Utf8.decode data) with Lib.Utf8.Utf8 -> fail s "utf8" "Invalid UTF-8 in CBOR text");
  data
let array_start s =
  let n = typed_head s 4 "Expected CBOR array" in
  if gt_big_int n (big_int_of_int max_items) then fail s "limit" "CBOR nesting or item limit exceeded";
  let n = int_of_big_int n in collection s n;
  if n > String.length s.input - s.at then fail s "syntax" "Unexpected end of CBOR input";
  n
let object_fields s action =
  let n = typed_head s 5 "Expected CBOR map" in
  if gt_big_int n (big_int_of_int max_items) then fail s "limit" "CBOR nesting or item limit exceeded";
  let n = int_of_big_int n in collection s n;
  if n > (String.length s.input - s.at) / 2 then fail s "syntax" "Unexpected end of CBOR input";
  let seen = Hashtbl.create 8 in
  for _ = 1 to n do
    let key = read_bytes s 3 in
    if Hashtbl.mem seen key then fail s "duplicate" "Duplicate CBOR map key";
    Hashtbl.add seen key ();
    at_path s key (fun () -> action key)
  done
let integer s =
  let major, _, n = head s in
  let negative, n = match major with
    | 0 | 1 -> major = 1, n
    | 6 when eq_big_int n (big_int_of_int 2) || eq_big_int n (big_int_of_int 3) ->
      let data = read_bytes s 2 in
      if String.length data > max_integer_bytes then fail s "limit" "CBOR integer byte limit exceeded";
      eq_big_int n (big_int_of_int 3), magnitude data
    | _ -> fail s "type" "Expected CBOR integer" in
  if negative then minus_big_int (succ_big_int n) else n
let rec skip s =
  enter s;
  (if s.at = String.length s.input then fail s "syntax" "Unexpected end of CBOR input";
   match Char.code s.input.[s.at] lsr 5 with
   | 0 | 1 -> ignore (head s)
   | 2 | 3 as major -> ignore (read_bytes s major)
   | 4 -> let count = array_start s in for i = 0 to count - 1 do at_path s (string_of_int i) (fun () -> skip s) done
   | 5 -> object_fields s (fun _ -> skip s)
   | 6 -> ignore (integer s)
   | _ -> let _, additional, n = head s in
     if not (additional >= 25 && additional <= 27) && not (ge_big_int n (big_int_of_int 20) && le_big_int n (big_int_of_int 22))
       then fail s "unsupported" "Unsupported CBOR simple value");
  leave s
let integer_value s prim =
  let signed, bits = match prim with
    | Type.Nat -> false, 0 | Int -> true, 0
    | Nat8 -> false, 8 | Nat16 -> false, 16 | Nat32 -> false, 32 | Nat64 -> false, 64
    | Int8 -> true, 8 | Int16 -> true, 16 | Int32 -> true, 32 | Int64 -> true, 64
    | _ -> invalid_arg "CBOR integer_value" in
  let n = integer s in
  if (not signed && sign_big_int n < 0) || (bits > 0 && (
    let bound = power_int_positive_int 2 (if signed then bits - 1 else bits) in
    ge_big_int n bound || lt_big_int n (if signed then minus_big_int bound else zero_big_int)))
    then fail s "range" "Integer is outside the requested type's range";
  match prim with
  | Type.Nat | Int -> V.Int (N.Int.of_big_int n)
  | Nat8 -> V.Nat8 (N.Nat8.of_big_int n) | Nat16 -> V.Nat16 (N.Nat16.of_big_int n)
  | Nat32 -> V.Nat32 (N.Nat32.of_big_int n) | Nat64 -> V.Nat64 (N.Nat64.of_big_int n)
  | Int8 -> V.Int8 (N.Int_8.of_big_int n) | Int16 -> V.Int16 (N.Int_16.of_big_int n)
  | Int32 -> V.Int32 (N.Int_32.of_big_int n) | Int64 -> V.Int64 (N.Int_64.of_big_int n)
  | _ -> invalid_arg "CBOR integer_value"
let bits64 n =
  let high,low = quomod_big_int n (power_int_positive_int 2 32) in
  Int64.logor (Int64.shift_left (int64_of_big_int high) 32) (int64_of_big_int low)
let half_float bits =
  let sign = if bits land 0x8000 <> 0 then -1. else 1. in
  let exponent = (bits lsr 10) land 31 and fraction = bits land 1023 in
  match exponent with
  | 0 -> sign *. Float.ldexp (float_of_int fraction) (-24)
  | 31 -> if fraction = 0 then sign *. infinity else nan
  | _ -> sign *. Float.ldexp (float_of_int (1024 + fraction)) (exponent - 25)
let read_float s prim =
  let major, additional, n = head s in
  if major <> 7 then fail s "type" "Expected CBOR float";
  let value = match additional with
    | 25 -> half_float (int_of_big_int n)
    | 26 -> Int32.float_of_bits (Int64.to_int32 (bits64 n))
    | 27 -> Int64.float_of_bits (bits64 n)
    | _ -> fail s "type" "Expected CBOR float" in
  if prim = Float32 && Float.is_finite value && not (Float.is_finite (N.Float32.to_float (N.Float32.of_float value)))
    then fail s "range" "Float is outside the finite range";
  if prim = Float then V.Float (N.Float.of_float value) else V.Float32 (N.Float32.of_float value)
let read_null s = let major, additional, n = head s in
  if major <> 7 || additional >= 24 || not (eq_big_int n (big_int_of_int 22)) then fail s "type" "Expected CBOR null"
let rec decode_value s typ =
  enter s;
  let value = match Type.normalize typ with
  | Type.Prim Null -> read_null s; V.Null
  | Prim Bool -> let major, additional, n = head s in
    if major <> 7 || additional >= 24 || not (eq_big_int n (big_int_of_int 20) || eq_big_int n (big_int_of_int 21)) then fail s "type" "Expected CBOR bool";
    V.Bool (eq_big_int n (big_int_of_int 21))
  | Prim Text -> V.Text (read_bytes s 3)
  | Prim Blob -> V.Blob (read_bytes s 2)
  | Prim Principal -> let data = read_bytes s 2 in
    if String.length data > 29 then fail s "principal" "Invalid principal bytes"; V.Blob data
  | Prim Char -> (match Lib.Utf8.decode (read_bytes s 3) with [ch] -> V.Char ch | _ -> fail s "type" "Expected exactly one Unicode scalar")
  | Prim (Nat | Int | Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) -> integer_value s p
  | Prim (Float | Float32 as p) -> read_float s p
  | Opt payload ->
    if s.at < String.length s.input && s.input.[s.at] = '\246' then (read_null s; V.Null)
    else if not (Schema.tagged_option payload) then V.Opt (decode_value s payload)
    else begin
      let result = ref None in
      object_fields s (fun label ->
        if Option.is_some !result then fail s "type" "Expected exactly one map field";
        if label <> "some" then fail s "type" "Unexpected CBOR variant case";
        result := Some (decode_value s payload));
      match !result with Some value -> V.Opt value | None -> fail s "type" "Expected exactly one map field"
    end
  | Tup ts ->
    let n = array_start s in if n <> List.length ts then fail s "type" "Unexpected CBOR tuple length";
    V.Tup (List.mapi (fun i typ -> at_path s (string_of_int i) (fun () -> decode_value s typ)) ts)
  | Array typ -> let n = array_start s in
    V.Array (Array.init n (fun i -> at_path s (string_of_int i) (fun () -> decode_value s typ)))
  | Non -> fail s "type" "Unexpected CBOR value"
  | Obj (Object, fields, _) ->
    let values = ref V.Env.empty in
    object_fields s (fun label -> match List.find_opt (fun f -> f.Type.lab = label) fields with
      | None -> skip s | Some f -> values := V.Env.add label (decode_value s f.typ) !values);
    List.iter (fun f -> if not (V.Env.mem f.Type.lab !values) then match Type.normalize f.typ with
      | Opt _ -> values := V.Env.add f.lab V.Null !values
      | _ -> at_path s f.lab (fun () -> fail s "missing" "Missing required CBOR field")) fields;
    V.Obj !values
  | Variant fields ->
    let value = ref None in
    object_fields s (fun label ->
      if Option.is_some !value then fail s "type" "Expected exactly one map field";
      match List.find_opt (fun f -> f.Type.lab = label) fields with
      | None -> fail s "type" "Unexpected CBOR variant case"
      | Some f -> value := Some (V.Variant (label,decode_value s f.typ)));
    (match !value with Some value -> value | None -> fail s "type" "Expected exactly one map field")
  | _ -> invalid_arg "CBOR unsupported reference decoder type"
  in leave s; value
let append s out data =
  if String.length data > max_bytes - Buffer.length out then fail s "limit" "CBOR byte limit exceeded";
  Buffer.add_string out data
let byte s out b = append s out (String.make 1 (Char.chr b))
let write_head s out major n =
  let width = if lt_big_int n (big_int_of_int 24) then 0 else if lt_big_int n (power_int_positive_int 2 8) then 1
    else if lt_big_int n (power_int_positive_int 2 16) then 2 else if lt_big_int n (power_int_positive_int 2 32) then 4 else 8 in
  byte s out (major lsl 5 lor (match width with 0 -> int_of_big_int n | 1 -> 24 | 2 -> 25 | 4 -> 26 | _ -> 27));
  for i = width - 1 downto 0 do byte s out (int_of_big_int (mod_big_int (div_big_int n (power_int_positive_int 2 (i * 8))) (big_int_of_int 256))) done
let write_length s out major n = write_head s out major (big_int_of_int n)
let write_bytes s out major data = write_length s out major (String.length data); append s out data
let write_integer s out n =
  let negative = sign_big_int n < 0 in
  let n = if negative then pred_big_int (minus_big_int n) else n in
  if lt_big_int n (power_int_positive_int 2 64) then write_head s out (if negative then 1 else 0) n
  else begin
    let b = Buffer.create 16 in let remaining = ref n in
    while sign_big_int !remaining <> 0 do
      if Buffer.length b >= max_integer_bytes then fail s "limit" "CBOR integer byte limit exceeded";
      let q,r = quomod_big_int !remaining (big_int_of_int 256) in
      Buffer.add_char b (Char.chr (int_of_big_int r)); remaining := q
    done;
    let little = Buffer.contents b in
    let data = String.init (String.length little) (fun i -> little.[String.length little-1-i]) in
    write_length s out 6 (if negative then 3 else 2); write_bytes s out 2 data
  end
let exact_half value =
  let bits = Int32.bits_of_float value in
  let sign = Int32.to_int (Int32.logand (Int32.shift_right_logical bits 16) 0x8000l) in
  let exp = Int32.to_int (Int32.logand (Int32.shift_right_logical bits 23) 255l) in
  let frac = Int32.to_int (Int32.logand bits 0x7fffffl) in
  if exp = 255 then (if frac = 0 then Some (sign lor 0x7c00) else None)
  else if exp = 0 then (if frac = 0 then Some sign else None)
  else let half_exp = exp - 112 in
    if half_exp >= 1 && half_exp < 31 then (if frac land 8191 = 0 then Some (sign lor (half_exp lsl 10) lor (frac lsr 13)) else None)
    else if half_exp >= -9 && half_exp <= 0 then
      let shift = 14-half_exp in let mantissa = frac lor 0x800000 in
      if mantissa land ((1 lsl shift)-1) = 0 then Some (sign lor (mantissa lsr shift)) else None
    else None
let write_float s out value =
  let write_bits count bits = for i = count - 1 downto 0 do byte s out (Int64.to_int (Int64.logand (Int64.shift_right_logical bits (i*8)) 255L)) done in
  if Float.is_nan value then append s out "\249\126\000"
  else if Int64.bits_of_float (Int32.float_of_bits (Int32.bits_of_float value)) = Int64.bits_of_float value then
    match exact_half value with
    | Some bits -> byte s out 0xf9; write_bits 2 (Int64.of_int bits)
    | None -> byte s out 0xfa; write_bits 4 (Int64.of_int32 (Int32.bits_of_float value))
  else (byte s out 0xfb; write_bits 8 (Int64.bits_of_float value))
let rec encode_value s out typ value =
  enter s;
  let child name typ value = at_path s name (fun () -> encode_value s out typ value) in
  let text data = write_bytes s out 3 data in
  let integer n = write_integer s out n in
  (match Type.normalize typ,value with
  | Type.Prim Null,V.Null -> byte s out 0xf6
  | Prim Bool,V.Bool value -> byte s out (if value then 0xf5 else 0xf4)
  | Prim Text,V.Text value -> text value
  | Prim (Blob | Principal),V.Blob value -> write_bytes s out 2 value
  | Prim Char,V.Char ch -> text (Lib.Utf8.encode [ch])
  | Prim (Nat | Int),V.Int n -> integer (N.Int.to_big_int n)
  | Prim Nat8,V.Nat8 n -> integer (N.Nat8.to_big_int n) | Prim Nat16,V.Nat16 n -> integer (N.Nat16.to_big_int n)
  | Prim Nat32,V.Nat32 n -> integer (N.Nat32.to_big_int n) | Prim Nat64,V.Nat64 n -> integer (N.Nat64.to_big_int n)
  | Prim Int8,V.Int8 n -> integer (N.Int_8.to_big_int n) | Prim Int16,V.Int16 n -> integer (N.Int_16.to_big_int n)
  | Prim Int32,V.Int32 n -> integer (N.Int_32.to_big_int n) | Prim Int64,V.Int64 n -> integer (N.Int_64.to_big_int n)
  | Prim Float,V.Float n -> write_float s out (N.Float.to_float n)
  | Prim Float32,V.Float32 n -> write_float s out (N.Float32.to_float n)
  | Opt _,V.Null -> byte s out 0xf6
  | Opt typ,V.Opt value ->
    if Schema.tagged_option typ then begin
      write_length s out 5 1; text "some";
      at_path s "some" (fun () -> encode_value s out typ value)
    end else encode_value s out typ value
  | Tup ts,V.Tup values -> write_length s out 4 (List.length ts);
    List.iteri (fun i (typ,value) -> child (string_of_int i) typ value) (List.combine ts values)
  | Array typ,V.Array values -> collection s (Array.length values); write_length s out 4 (Array.length values);
    Array.iteri (fun i value -> child (string_of_int i) typ value) values
  | Obj (Object,fields,_),V.Obj values -> write_length s out 5 (List.length fields);
    List.iter (fun f -> text f.Type.lab; child f.lab f.typ (V.Env.find f.lab values)) (Schema.sort_fields fields)
  | Variant fields,V.Variant (label,value) ->
    let f = List.find (fun f -> f.Type.lab = label) fields in
    write_length s out 5 1; text label; child label f.typ value
  | _ -> invalid_arg "CBOR unsupported reference encoder value");
  leave s
let error_value error = V.Variant ("err",V.Obj (List.fold_left (fun env (name,value) -> V.Env.add name value env) V.Env.empty [
  "kind",V.Text error.kind; "message",V.Text error.message; "path",V.Text error.path;
  "offset",V.Nat64 (N.Nat64.of_int error.offset)
]))
let protect action = try Ok (V.Variant ("ok",action ())) with Invalid error -> Ok (error_value error)
let encode _type_arguments types values = match types,values with
  | [typ],[value] -> protect (fun () -> let s = state "" and out = Buffer.create 128 in
      encode_value s out typ value; V.Blob (Buffer.contents out))
  | _ -> Error "to_cbor expects one argument"
let decode type_arguments _types values = match type_arguments,values with
  | [typ],[V.Blob input] -> protect (fun () -> let s = state input in
      if String.length input > max_bytes then fail s "limit" "CBOR byte limit exceeded";
      let value = decode_value s typ in
      if s.at <> String.length input then fail s "syntax" "Trailing CBOR input";
      value)
  | _ -> Error "from_cbor expects one explicit type argument and one Blob argument"
