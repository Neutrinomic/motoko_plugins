open Mo_types
module T = Type

type operation = Contains | Add | Insert | Remove | Delete
type ordering = Callback | Static
let node_constructor =
  let con = Cons.fresh "PluginMutableSetNode" (T.Abs ([], T.Pre)) in
  let k = T.Var ("T", 0) in
  let binds = [T.{var = "T"; sort = Type; bound = Any}] in
  let node = T.Con (con, [k]) in
  T.set_kind con (T.Def (binds, T.obj T.Object [
    "count", T.Mut T.nat32;
    "entries", T.Array (T.Mut (T.Opt k));
    "children", T.Array (T.Mut (T.Opt node));
  ])); con
let node k = T.Con (node_constructor, [k])
let set k = T.obj T.Object [
  "root", T.Mut (T.Opt (node k)); "size", T.Mut T.nat;
]
let order = T.Variant (List.map (fun lab ->
  T.{lab; typ = unit; src = empty_src}) ["equal"; "greater"; "less"])
let compare k = T.Func (T.Local, T.Returns, [], [k; k], [order])
let scalar = function
  | T.Prim (T.Nat | T.Int | T.Nat8 | T.Nat16 | T.Nat32 | T.Nat64
    | T.Int8 | T.Int16 | T.Int32 | T.Int64 | T.Bool | T.Char
    | T.Text | T.Blob | T.Principal) -> true
  | _ -> false
let types ordering = function
  | [k] when ordering = Callback || scalar (T.promote k) -> Ok k
  | [_] -> Error "mutable set static ordering requires an integer, Bool, Char, Text, Blob, or Principal element"
  | _ -> Error "mutable set operations require an explicit element type"
let arguments _operation ordering ts = Result.map (fun k ->
  if ordering = Callback then [set k; compare k; k] else [set k; k])
  (types ordering ts)
let result operation ordering ts _ = Result.map (fun _ -> match operation with
  | Contains | Insert | Delete -> T.bool
  | Add | Remove -> T.unit) (types ordering ts)
let name = function
  | Contains -> "contains" | Add -> "add" | Insert -> "insert"
  | Remove -> "remove" | Delete -> "delete"
