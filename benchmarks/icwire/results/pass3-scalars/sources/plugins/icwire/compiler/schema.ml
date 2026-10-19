open Mo_types
open Type

let max_bytes = 16 * 1024 * 1024
let error_type = Type.obj Type.Object ["kind", Type.text; "offset", Type.Prim Type.Nat64]
let result_type typ = Type.sum ["err", error_type; "ok", typ]

(* Candid's unsigned field identifiers, including Motoko's escaped numeric
   labels. Heap field hashes discard a bit and must not be used on the wire. *)
let field_id label =
  Int64.logand
    (Int64.of_int32 (Lib.Uint32.to_int32 (Idllib.Escape.unescape_hash label)))
    0xffff_ffffL

let sort_fields fields =
  List.sort (fun a b -> Int64.compare (field_id a.Type.lab) (field_id b.Type.lab)) fields

module Seen = Set.Make (Type.Ord)

let validate typ =
  let rec visit seen typ =
    let typ = Type.normalize typ in
    if Seen.mem typ seen then Ok () else
    let seen = Seen.add typ seen in
    let rec all = function
      | [] -> Ok ()
      | typ :: rest -> (match visit seen typ with Ok () -> all rest | Result.Error e -> Result.Error e)
    in
    let fields fs =
      let rec distinct = function
        | a :: (b :: _ as rest) ->
          if field_id a.Type.lab = field_id b.Type.lab then
            Result.Error ("ICWire field identifiers collide: " ^ a.lab ^ " and " ^ b.lab)
          else distinct rest
        | _ -> all (List.map (fun f -> f.Type.typ) fs)
      in
      distinct (sort_fields fs)
    in
    match typ with
    | Type.Prim (Null | Bool | Nat | Int | Nat8 | Nat16 | Nat32 | Nat64 |
        Int8 | Int16 | Int32 | Int64 | Float | Float32 | Char | Text | Blob | Principal) -> Ok ()
    | Type.Non -> Ok ()
    | Type.Opt typ | Type.Array typ -> visit seen typ
    | Type.Tup ts -> all ts
    | Type.Obj (Type.Object, fs, _) | Type.Variant fs -> fields fs
    | _ -> Result.Error "ICWire supports immutable data types, not functions, actors, mutable fields, Any, or runtime handles"
  in
  visit Seen.empty typ
