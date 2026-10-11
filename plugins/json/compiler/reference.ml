(* Executable specification for moc -r and the IR interpreters. The compiled
   path uses the streaming Rust parser and specialized heap visitors. *)
open Mo_types
open Type
open Mo_values
module V = Value
module N = Numerics

type error = { kind : string; message : string; path : string; offset : int }
exception Invalid of error
type state = { input : string; mutable at : int; mutable depth : int;
  mutable items : int; mutable path : string }
let max_bytes = Schema.max_bytes
let max_items = 1_000_000
let max_depth = 128
let max_digits = 4096
let fail (s : state) kind message = raise (Invalid { kind; message; path = s.path; offset = s.at })
let ws s = while s.at < String.length s.input && String.contains " \n\r\t" s.input.[s.at] do s.at <- s.at + 1 done
let peek s = ws s; if s.at = String.length s.input then '\000' else s.input.[s.at]
let expect s c = if peek s <> c then fail s "syntax" "Unexpected JSON token"; s.at <- s.at + 1
let enter s = s.depth <- s.depth + 1; s.items <- s.items + 1;
  if s.depth > max_depth || s.items > max_items then fail s "limit" "JSON nesting or item limit exceeded"
let leave s = s.depth <- s.depth - 1
let path_component text =
  let b = Buffer.create (String.length text) in
  String.iter (function '~' -> Buffer.add_string b "~0" | '/' -> Buffer.add_string b "~1" | c -> Buffer.add_char b c) text;
  Buffer.contents b
let at_path (s : state) name action = let saved = s.path in s.path <- saved ^ "/" ^ path_component name;
  let value = action () in s.path <- saved; value
let literal s text =
  ws s;
  if s.at + String.length text > String.length s.input || String.sub s.input s.at (String.length text) <> text
    then fail s "type" "Unexpected JSON literal";
  s.at <- s.at + String.length text
let digit c = c >= '0' && c <= '9'
let hex4 s =
  let value = ref 0 in
  for _ = 1 to 4 do
    if s.at >= String.length s.input then fail s "syntax" "Invalid Unicode escape";
    let n = match s.input.[s.at] with
      | '0'..'9' as c -> Char.code c - 48 | 'a'..'f' as c -> Char.code c - 87
      | 'A'..'F' as c -> Char.code c - 55 | _ -> fail s "syntax" "Invalid Unicode escape" in
    value := !value * 16 + n; s.at <- s.at + 1
  done; !value
let add_unicode b n =
  let put n = Buffer.add_char b (Char.chr n) in
  if n < 0x80 then put n
  else if n < 0x800 then (put (0xc0 lor (n lsr 6)); put (0x80 lor (n land 63)))
  else if n < 0x10000 then (put (0xe0 lor (n lsr 12)); put (0x80 lor ((n lsr 6) land 63)); put (0x80 lor (n land 63)))
  else (put (0xf0 lor (n lsr 18)); put (0x80 lor ((n lsr 12) land 63)); put (0x80 lor ((n lsr 6) land 63)); put (0x80 lor (n land 63)))
let string s =
  if peek s <> '"' then fail s "type" "Expected a JSON string";
  s.at <- s.at + 1;
  let b = Buffer.create 16 in
  let rec loop () =
    if s.at = String.length s.input then fail s "syntax" "Unterminated JSON string";
    let c = s.input.[s.at] in s.at <- s.at + 1;
    match c with
    | '"' -> Buffer.contents b
    | '\\' ->
      if s.at = String.length s.input then fail s "syntax" "Incomplete JSON escape";
      let c = s.input.[s.at] in s.at <- s.at + 1;
      (match c with
       | '"' | '\\' | '/' -> Buffer.add_char b c
       | 'b' -> Buffer.add_char b '\008' | 'f' -> Buffer.add_char b '\012'
       | 'n' -> Buffer.add_char b '\n' | 'r' -> Buffer.add_char b '\r' | 't' -> Buffer.add_char b '\t'
       | 'u' ->
         let high = hex4 s in
         let cp = if high >= 0xd800 && high <= 0xdbff then begin
           if s.at + 2 > String.length s.input || String.sub s.input s.at 2 <> "\\u"
             then fail s "syntax" "Unpaired Unicode surrogate";
           s.at <- s.at + 2;
           let low = hex4 s in
           if low < 0xdc00 || low > 0xdfff then fail s "syntax" "Unpaired Unicode surrogate";
           0x10000 + ((high - 0xd800) lsl 10) + low - 0xdc00
         end else high in
         if cp >= 0xd800 && cp <= 0xdfff then fail s "syntax" "Unpaired Unicode surrogate";
         add_unicode b cp
       | _ -> fail s "syntax" "Invalid JSON escape"); loop ()
    | c when Char.code c < 32 -> s.at <- s.at - 1; fail s "syntax" "Unescaped control character"
    | c -> Buffer.add_char b c; loop ()
  in loop ()
let number s =
  ws s; let start = s.at in
  let at () = if s.at = String.length s.input then '\000' else s.input.[s.at] in
  let digits () = while digit (at ()) do s.at <- s.at + 1 done in
  if at () = '-' then s.at <- s.at + 1;
  (match at () with '0' -> s.at <- s.at + 1 | '1'..'9' -> digits () | _ -> fail s "type" "Expected a JSON number");
  if at () = '.' then begin s.at <- s.at + 1; let p = s.at in digits (); if p = s.at then fail s "syntax" "Invalid JSON number" end;
  if at () = 'e' || at () = 'E' then begin
    s.at <- s.at + 1; if at () = '+' || at () = '-' then s.at <- s.at + 1;
    let p = s.at in digits (); if p = s.at then fail s "syntax" "Invalid JSON number"
  end;
  String.sub s.input start (s.at - start)
let integer s signed quoted =
  let text = if quoted && peek s = '"' then string s else number s in
  let start = if String.length text > 0 && text.[0] = '-' && signed then 1 else 0 in
  if String.length text = start || not (String.for_all digit (String.sub text start (String.length text - start))) ||
      (String.length text > start + 1 && text.[start] = '0') then fail s "range" "Expected an exact decimal integer";
  if String.length text - start > max_digits then fail s "limit" "JSON integer digit limit exceeded";
  Big_int.big_int_of_string text
let object_fields s action =
  if peek s <> '{' then fail s "type" "Expected a JSON object";
  s.at <- s.at + 1;
  let seen = Hashtbl.create 8 in
  let rec loop first =
    if peek s = '}' then s.at <- s.at + 1 else begin
      if not first then expect s ',';
      let key = string s in
      if Hashtbl.mem seen key then fail s "duplicate" "Duplicate JSON object key";
      Hashtbl.add seen key ();
      expect s ':';
      at_path s key (fun () -> action key);
      loop false
    end
  in loop true
let array_elements s action =
  if peek s <> '[' then fail s "type" "Expected a JSON array";
  s.at <- s.at + 1;
  let rec loop i =
    if peek s = ']' then s.at <- s.at + 1 else begin
      if i > 0 then expect s ',';
      at_path s (string_of_int i) (fun () -> action i);
      loop (i + 1)
    end
  in loop 0
let rec skip s =
  enter s;
  (match peek s with
  | '"' -> ignore (string s)
  | '{' -> object_fields s (fun _ -> skip s)
  | '[' -> array_elements s (fun _ -> skip s)
  | 't' -> literal s "true" | 'f' -> literal s "false" | 'n' -> literal s "null"
  | _ -> ignore (number s));
  leave s

(* Match the runtime's bounded array pre-scan, including error precedence: an
   array's syntax is checked before its typed elements are constructed. *)
let count_array s =
  if peek s <> '[' then fail s "type" "Expected a JSON array";
  s.at <- s.at + 1;
  let start = s.at and items = s.items in
  let rec loop i =
    if peek s = ']' then i else begin
      if i > 0 then expect s ',';
      at_path s (string_of_int i) (fun () -> skip s);
      loop (i + 1)
    end
  in
  let count = loop 0 in s.at <- start; s.items <- items; count
let typed_elements s count action =
  for i = 0 to count - 1 do
    if i > 0 then expect s ',';
    at_path s (string_of_int i) (fun () -> action i)
  done;
  expect s ']'

let b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
let base64 input =
  let b = Buffer.create ((String.length input + 2) / 3 * 4) in
  let at i = if i < String.length input then Char.code input.[i] else 0 in
  for group = 0 to (String.length input + 2) / 3 - 1 do
    let i = group * 3 in let n = (at i lsl 16) lor (at (i + 1) lsl 8) lor at (i + 2) in
    Buffer.add_char b b64.[n lsr 18]; Buffer.add_char b b64.[(n lsr 12) land 63];
    Buffer.add_char b (if i + 1 < String.length input then b64.[(n lsr 6) land 63] else '=');
    Buffer.add_char b (if i + 2 < String.length input then b64.[n land 63] else '=')
  done; Buffer.contents b
let unbase64 s input =
  let bad () = fail s "base64" "Invalid padded base64 string" in
  if String.length input mod 4 <> 0 then bad ();
  let b = Buffer.create (String.length input / 4 * 3) in
  let at i = match String.index_opt b64 input.[i] with Some n -> n | None -> bad () in
  for group = 0 to String.length input / 4 - 1 do
    let i = group * 4 in let a = at i and d = at (i + 1) in
    Buffer.add_char b (Char.chr ((a lsl 2) lor (d lsr 4)));
    let last = i + 4 = String.length input in
    if input.[i + 2] = '=' then begin
      if not last || input.[i + 3] <> '=' || d land 15 <> 0 then bad ()
    end else begin
      let c = at (i + 2) in Buffer.add_char b (Char.chr (((d lsl 4) lor (c lsr 2)) land 255));
      if input.[i + 3] = '=' then (if not last || c land 3 <> 0 then bad ())
      else Buffer.add_char b (Char.chr (((c lsl 6) lor at (i + 3)) land 255))
    end
  done; Buffer.contents b

let integer_value s prim =
  let signed, bits = match prim with
    | Type.Nat -> false, 0 | Int -> true, 0
    | Nat8 -> false, 8 | Nat16 -> false, 16 | Nat32 -> false, 32 | Nat64 -> false, 64
    | Int8 -> true, 8 | Int16 -> true, 16 | Int32 -> true, 32 | Int64 -> true, 64
    | _ -> invalid_arg "JSON integer_value" in
  let n = integer s signed (bits = 0 || bits = 64) in
  if bits > 0 then begin
    let open Big_int in
    let bound = power_int_positive_int 2 (if signed then bits - 1 else bits) in
    if ge_big_int n bound || lt_big_int n (if signed then minus_big_int bound else zero_big_int)
      then fail s "range" "Integer is outside the requested type's range"
  end;
  match prim with
  | Type.Nat | Int -> V.Int (N.Int.of_big_int n)
  | Nat8 -> V.Nat8 (N.Nat8.of_big_int n) | Nat16 -> V.Nat16 (N.Nat16.of_big_int n)
  | Nat32 -> V.Nat32 (N.Nat32.of_big_int n) | Nat64 -> V.Nat64 (N.Nat64.of_big_int n)
  | Int8 -> V.Int8 (N.Int_8.of_big_int n) | Int16 -> V.Int16 (N.Int_16.of_big_int n)
  | Int32 -> V.Int32 (N.Int_32.of_big_int n) | Int64 -> V.Int64 (N.Int_64.of_big_int n)
  | _ -> invalid_arg "JSON integer_value"

let rec decode_value s typ =
  enter s;
  let value = match Type.normalize typ with
  | Type.Prim Null -> literal s "null"; V.Null
  | Prim Bool -> if peek s = 't' then (literal s "true"; V.Bool true) else (literal s "false"; V.Bool false)
  | Prim Text -> V.Text (string s)
  | Prim Blob -> V.Blob (unbase64 s (string s))
  | Prim Principal ->
    let text = string s in
    (match Ic.Url.decode_principal text with
     | Ok bytes when String.length bytes <= 29 && Ic.Url.encode_principal bytes = text -> V.Blob bytes
     | _ -> fail s "principal" "Invalid principal text")
  | Prim Char ->
    let text = string s in
    (match Lib.Utf8.decode text with [ch] -> V.Char ch | _ -> fail s "type" "Expected exactly one Unicode scalar")
  | Prim (Nat | Int | Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) -> integer_value s p
  | Prim (Float | Float32 as p) ->
    let n = if peek s = '"' then match string s with
      | "NaN" -> nan | "Infinity" -> infinity | "-Infinity" -> neg_infinity
      | _ -> fail s "type" "Expected a number or special float string"
      else let raw = number s in
        let value = try (if p = Float32 then N.Float32.to_float (N.Float32.of_string raw) else float_of_string raw)
          with Failure _ -> fail s "range" "Float is outside the finite range" in
        if Float.is_finite value then value
        else fail s "range" "Float is outside the finite range" in
    if p = Float then V.Float (N.Float.of_float n) else V.Float32 (N.Float32.of_float n)
  | Opt payload ->
    if peek s = 'n' then (literal s "null"; V.Null)
    else if not (Schema.tagged_option payload) then V.Opt (decode_value s payload)
    else begin
      let result = ref None in
      object_fields s (fun label ->
        if Option.is_some !result then fail s "type" "Expected exactly one object field";
        if label <> "some" then fail s "type" "Unexpected JSON variant case";
        result := Some (decode_value s payload));
      match !result with Some value -> V.Opt value | None -> fail s "type" "Expected exactly one object field"
    end
  | Tup ts ->
    let count = count_array s in
    if count <> List.length ts then fail s "type" "Unexpected JSON tuple length";
    let values = ref [] in
    typed_elements s count (fun i -> match List.nth_opt ts i with
      | Some typ -> values := decode_value s typ :: !values
      | None -> fail s "type" "Unexpected JSON tuple length");
    if List.length !values <> List.length ts then fail s "type" "Unexpected JSON tuple length";
    V.Tup (List.rev !values)
  | Array typ ->
    let count = count_array s in
    let values = ref [] in typed_elements s count (fun _ -> values := decode_value s typ :: !values);
    V.Array (Array.of_list (List.rev !values))
  | Non -> fail s "type" "Unexpected JSON value"
  | Obj (Object, fields, _) ->
    let values = ref V.Env.empty in
    object_fields s (fun label ->
      match List.find_opt (fun f -> f.Type.lab = label) fields with
      | None -> skip s
      | Some f -> values := V.Env.add label (decode_value s f.typ) !values);
    List.iter (fun f -> if not (V.Env.mem f.Type.lab !values) then
      match Type.normalize f.typ with
      | Opt _ -> values := V.Env.add f.lab V.Null !values
      | _ -> at_path s f.lab (fun () -> fail s "missing" "Missing required JSON field")) fields;
    V.Obj !values
  | Variant fields ->
    let value = ref None in
    object_fields s (fun label ->
      if Option.is_some !value then fail s "type" "Expected exactly one object field";
      match List.find_opt (fun f -> f.Type.lab = label) fields with
      | None -> fail s "type" "Unexpected JSON variant case"
      | Some f -> value := Some (V.Variant (label, decode_value s f.typ)));
    (match !value with Some value -> value | None -> fail s "type" "Expected exactly one object field")
  | _ -> invalid_arg "JSON unsupported reference decoder type"
  in leave s; value

let json_string text =
  let b = Buffer.create (String.length text + 2) in Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r" | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) text;
  Buffer.add_char b '"'; Buffer.contents b
let float_text n =
  if Float.is_nan n then "\"NaN\"" else if n = infinity then "\"Infinity\"" else if n = neg_infinity then "\"-Infinity\""
  else let text = Printf.sprintf "%.16e" n in
    match String.index_opt text 'e' with None -> text | Some i ->
      String.sub text 0 (i + 1) ^ string_of_int (int_of_string (String.sub text (i + 1) (String.length text - i - 1)))

let rec encode_value s out typ value =
  enter s;
  let append text =
    if String.length text > max_bytes - Buffer.length out then fail s "limit" "JSON byte limit exceeded";
    Buffer.add_string out text in
  let child name typ value = at_path s name (fun () -> encode_value s out typ value) in
  let text s = append (json_string s) in
  (match Type.normalize typ, value with
  | Type.Prim Null, V.Null -> append "null"
  | Prim Bool, V.Bool b -> append (string_of_bool b)
  | Prim Text, V.Text s -> text s
  | Prim Blob, V.Blob b -> text (base64 b)
  | Prim Principal, V.Blob b -> text (Ic.Url.encode_principal b)
  | Prim Char, V.Char ch -> let b = Buffer.create 4 in add_unicode b ch; text (Buffer.contents b)
  | Prim (Nat | Int), V.Int n ->
    let raw = Big_int.string_of_big_int (N.Int.to_big_int n) in
    if String.length raw - (if raw.[0] = '-' then 1 else 0) > max_digits then fail s "limit" "JSON integer digit limit exceeded";
    text raw
  | Prim Nat8, V.Nat8 n -> append (Big_int.string_of_big_int (N.Nat8.to_big_int n))
  | Prim Nat16, V.Nat16 n -> append (Big_int.string_of_big_int (N.Nat16.to_big_int n))
  | Prim Nat32, V.Nat32 n -> append (Big_int.string_of_big_int (N.Nat32.to_big_int n))
  | Prim Nat64, V.Nat64 n -> text (Big_int.string_of_big_int (N.Nat64.to_big_int n))
  | Prim Int8, V.Int8 n -> append (Big_int.string_of_big_int (N.Int_8.to_big_int n))
  | Prim Int16, V.Int16 n -> append (Big_int.string_of_big_int (N.Int_16.to_big_int n))
  | Prim Int32, V.Int32 n -> append (Big_int.string_of_big_int (N.Int_32.to_big_int n))
  | Prim Int64, V.Int64 n -> text (Big_int.string_of_big_int (N.Int_64.to_big_int n))
  | Prim Float, V.Float f -> append (float_text (N.Float.to_float f))
  | Prim Float32, V.Float32 f -> append (float_text (N.Float32.to_float f))
  | Opt _, V.Null -> append "null"
  | Opt typ, V.Opt value ->
    if Schema.tagged_option typ then begin
      append "{\"some\":";
      at_path s "some" (fun () -> encode_value s out typ value);
      append "}"
    end else encode_value s out typ value
  | Tup ts, V.Tup values ->
    append "["; List.iteri (fun i (typ,value) -> if i > 0 then append ","; child (string_of_int i) typ value) (List.combine ts values); append "]"
  | Array typ, V.Array values ->
    if Array.length values > max_items - s.items then
      fail s "limit" "JSON nesting or item limit exceeded";
    append "["; Array.iteri (fun i value -> if i > 0 then append ","; child (string_of_int i) typ value) values; append "]"
  | Obj (Object, fs, _), V.Obj values ->
    append "{"; List.iteri (fun i f -> if i > 0 then append ",";
      text f.Type.lab; append ":"; child f.lab f.typ (V.Env.find f.lab values)) fs; append "}"
  | Variant fs, V.Variant (label,value) ->
    let f = List.find (fun f -> f.Type.lab = label) fs in
    append "{"; text label; append ":"; child label f.typ value; append "}"
  | _ -> invalid_arg "JSON unsupported reference encoder value");
  leave s

let error_value error = V.Variant ("err", V.Obj (List.fold_left (fun env (name,value) -> V.Env.add name value env) V.Env.empty [
  "kind", V.Text error.kind; "message", V.Text error.message; "path", V.Text error.path;
  "offset", V.Nat64 (N.Nat64.of_int error.offset);
]))
let protect action = try Ok (V.Variant ("ok", action ())) with Invalid error -> Ok (error_value error)
let state input = {input; at = 0; path = ""; depth = 0; items = 0}
let encode _type_arguments types values = match types, values with
  | [typ], [value] -> protect (fun () -> let s = state "" in let out = Buffer.create 128 in
      encode_value s out typ value; V.Text (Buffer.contents out))
  | _ -> Error "to_json expects one argument"
let decode type_arguments _types values = match type_arguments, values with
  | [typ], [V.Text input] -> protect (fun () ->
      let s = state input in
      if String.length input > max_bytes then fail s "limit" "JSON byte limit exceeded";
      let value = decode_value s typ in ws s;
      if s.at <> String.length input then fail s "syntax" "Trailing JSON input";
      value)
  | _ -> Error "from_json expects one explicit type argument and one Text argument"
