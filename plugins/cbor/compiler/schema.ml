open Mo_types
open Type

let max_bytes = 16 * 1024 * 1024

let error_type = Type.obj Type.Object [
  "kind", Type.text; "message", Type.text; "path", Type.text;
  "offset", Type.Prim Type.Nat64;
]
let result_type typ = Type.sum ["err", error_type; "ok", typ]

module Seen = Set.Make (Type.Ord)

let validate typ =
  let rec visit seen typ =
    let typ = Type.normalize typ in
    if Seen.mem typ seen then Ok () else
    let seen = Seen.add typ seen in
    let rec all = function
      | [] -> Ok ()
      | typ :: rest -> (match visit seen typ with Ok () -> all rest | Error e -> Error e)
    in
    match typ with
    | Type.Prim (Null | Bool | Nat | Int | Nat8 | Nat16 | Nat32 | Nat64 |
        Int8 | Int16 | Int32 | Int64 | Float | Float32 | Char | Text | Blob | Principal) -> Ok ()
    | Type.Non -> Ok ()
    | Type.Opt typ | Type.Array typ -> visit seen typ
    | Type.Tup ts -> all ts
    | Type.Obj (Type.Object, fields, _) | Type.Variant fields ->
      all (List.map (fun f -> f.Type.typ) fields)
    | _ -> Error "CBOR supports immutable data types, not functions, actors, mutable fields, Any, or runtime handles"
  in
  visit Seen.empty typ

let tagged_option typ = match Type.normalize typ with
  | Type.Opt _ | Type.Prim Type.Null -> true
  | _ -> false

(* RFC 8949 core deterministic ordering: compare encoded text keys. For text
   strings this is byte length first, then bytewise UTF-8 order. *)
let sort_fields fields = List.sort (fun a b ->
  let by_length = Int.compare (String.length a.Type.lab) (String.length b.Type.lab) in
  if by_length <> 0 then by_length else String.compare a.lab b.lab) fields
