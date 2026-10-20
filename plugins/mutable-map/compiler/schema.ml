open Mo_types
module T = Type

type operation = Get | Get_entry | Contains | Add | Insert | Swap | Replace
  | Remove | Delete | Take | Min_entry | Max_entry
type ordering = Callback | Static
let entry k v = T.Tup [k; v]
let node_constructor =
  let con = Cons.fresh "PluginMutableBTreeNode" (T.Abs ([], T.Pre)) in
  let k = T.Var ("K", 0) and v = T.Var ("V", 1) in
  let binds = List.map (fun var -> T.{var; sort = Type; bound = Any}) ["K"; "V"] in
  let node = T.Con (con, [k; v]) in
  T.set_kind con (T.Def (binds, T.obj T.Object [
    "count", T.Mut T.nat32;
    "entries", T.Array (T.Mut (T.Opt (entry k v)));
    "children", T.Array (T.Mut (T.Opt node));
  ])); con
let node k v = T.Con (node_constructor, [k; v])
let tree k v = T.Opt (node k v)
let map k v = T.obj T.Object [
  "root", T.Mut (tree k v); "size", T.Mut T.nat;
]
let order = T.Variant (List.map (fun lab -> T.{lab; typ = unit; src = empty_src}) ["equal"; "greater"; "less"])
let compare k = T.Func (T.Local, T.Returns, [], [k; k], [order])
let scalar = function
  | T.Prim (T.Nat | T.Int | T.Nat8 | T.Nat16 | T.Nat32 | T.Nat64
    | T.Int8 | T.Int16 | T.Int32 | T.Int64 | T.Bool | T.Char
    | T.Text | T.Blob | T.Principal) -> true
  | _ -> false
let types ordering = function
  | [k; v] when ordering = Callback || scalar (T.promote k) -> Ok (k, v)
  | [_; _] -> Error "mutable map static ordering requires an integer, Bool, Char, Text, Blob, or Principal key"
  | _ -> Error "mutable map operations require explicit key and value types"
let arguments operation ordering ts = Result.map (fun (k, v) ->
  let args = match operation with
    | Min_entry | Max_entry -> [map k v]
    | _ -> if ordering = Callback then [map k v; compare k; k] else [map k v; k] in
  match operation with Add | Insert | Swap | Replace -> args @ [v] | _ -> args) (types ordering ts)
let result operation ordering ts _ = Result.map (fun (k, v) -> match operation with
  | Get | Swap | Replace | Take -> T.Opt v
  | Get_entry | Min_entry | Max_entry -> T.Opt (entry k v)
  | Contains | Insert | Delete -> T.bool
  | Add | Remove -> T.unit) (types ordering ts)
let name = function
  | Get -> "get" | Get_entry -> "get_entry" | Contains -> "contains"
  | Add -> "add" | Insert -> "insert" | Swap -> "swap" | Replace -> "replace"
  | Remove -> "remove" | Delete -> "delete" | Take -> "take"
  | Min_entry -> "min_entry" | Max_entry -> "max_entry"
