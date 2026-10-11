open Mo_types
module T = Type

type operation =
  | Get | Get_entry | Contains | Add | Put | Replace | Remove | Take | Alter
  | Join | Concat | Split | Rank | Select | From_sorted

type ordering = Callback | Static

let map_constructor =
  let con = Cons.fresh "PluginMap" (T.Abs ([], T.Pre)) in
  let k = T.Var ("K", 0) and v = T.Var ("V", 1) in
  let binds = List.map (fun var -> T.{var; sort = Type; bound = Any}) ["K"; "V"] in
  let self = T.Con (con, [k; v]) in
  T.set_kind con (T.Def (binds, T.Opt (T.Tup [T.nat32; T.nat; k; v; self; self])));
  con

let map k v = T.Con (map_constructor, [k; v])
let order = T.Variant (List.map (fun lab -> T.{lab; typ = unit; src = empty_src}) ["equal"; "greater"; "less"])
let compare k = T.Func (T.Local, T.Returns, [], [k; k], [order])
let alteration v = T.Func (T.Local, T.Returns, [], [T.Opt v], [T.Opt v])
let entry k v = T.Tup [k; v]
let scalar = function
  | T.Prim (T.Nat | T.Int | T.Nat8 | T.Nat16 | T.Nat32 | T.Nat64
    | T.Int8 | T.Int16 | T.Int32 | T.Int64 | T.Bool | T.Char
    | T.Text | T.Blob | T.Principal) -> true
  | _ -> false

let types ordering = function
  | [k; v] when ordering = Callback || scalar (T.promote k) -> Ok (k, v)
  | [_; _] -> Error "pure map static ordering requires an integer, Bool, Char, Text, Blob, or Principal key"
  | _ -> Error "pure map operations require explicit key and value types"

let arguments operation ordering ts =
  Result.map (fun (k, v) ->
    let tree = map k v in
    let search = if ordering = Callback then [tree; compare k; k] else [tree; k] in
    match operation with
    | Get | Get_entry | Contains | Remove | Take | Split | Rank -> search
    | Add | Put | Replace -> search @ [v]
    | Alter -> search @ [alteration v]
    | Join -> [tree; k; v; tree]
    | Concat -> [tree; tree]
    | Select -> [tree; T.nat]
    | From_sorted -> [T.Array (entry k v)]) (types ordering ts)

let result operation ordering ts _arguments =
  Result.map (fun (k, v) ->
    let tree = map k v and entry = T.Opt (entry k v) in
    match operation with
    | Get -> T.Opt v
    | Get_entry | Select -> entry
    | Contains -> T.bool
    | Add | Remove | Join | Concat | From_sorted -> tree
    | Put | Take | Alter -> T.Tup [tree; entry]
    | Replace -> T.Tup [tree; T.Opt v]
    | Split -> T.Tup [tree; entry; tree]
    | Rank -> T.Tup [T.nat; T.bool]) (types ordering ts)

let name = function
  | Get -> "get" | Get_entry -> "get_entry" | Contains -> "contains"
  | Add -> "add" | Put -> "put" | Replace -> "replace" | Remove -> "remove" | Take -> "take"
  | Alter -> "alter" | Join -> "join" | Concat -> "concat" | Split -> "split"
  | Rank -> "rank" | Select -> "select" | From_sorted -> "from_sorted"
