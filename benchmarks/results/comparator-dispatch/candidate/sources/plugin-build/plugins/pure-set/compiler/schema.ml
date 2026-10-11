open Mo_types
module T = Type

type operation =
  | Get | Contains | Add | Insert | Remove | Delete
  | Join | Concat | Split | Rank | Select | From_sorted

type ordering = Callback | Static

let set_constructor =
  let con = Cons.fresh "PluginSet" (T.Abs ([], T.Pre)) in
  let k = T.Var ("T", 0) in
  let binds = [T.{var = "T"; sort = Type; bound = Any}] in
  let self = T.Con (con, [k]) in
  T.set_kind con (T.Def (binds, T.Opt (T.Tup [T.nat32; T.nat; k; self; self])));
  con

let set k = T.Con (set_constructor, [k])
let order = T.Variant (List.map
  (fun lab -> T.{lab; typ = unit; src = empty_src})
  ["equal"; "greater"; "less"])
let compare k = T.Func (T.Local, T.Returns, [], [k; k], [order])
let scalar = function
  | T.Prim (T.Nat | T.Int | T.Nat8 | T.Nat16 | T.Nat32 | T.Nat64
    | T.Int8 | T.Int16 | T.Int32 | T.Int64 | T.Bool | T.Char
    | T.Text | T.Blob | T.Principal) -> true
  | _ -> false

let types ordering = function
  | [k] when ordering = Callback || scalar (T.promote k) -> Ok k
  | [_] -> Error "pure set static ordering requires an integer, Bool, Char, Text, Blob, or Principal element"
  | _ -> Error "pure set operations require an explicit element type"

let arguments operation ordering ts =
  Result.map (fun k ->
    let tree = set k in
    let search = if ordering = Callback then [tree; compare k; k]
      else [tree; k] in
    match operation with
    | Get | Contains | Add | Insert | Remove | Delete | Split | Rank -> search
    | Join -> [tree; k; tree]
    | Concat -> [tree; tree]
    | Select -> [tree; T.nat]
    | From_sorted -> [T.Array k]) (types ordering ts)

let result operation ordering ts _arguments =
  Result.map (fun k ->
    let tree = set k in
    match operation with
    | Get | Select -> T.Opt k
    | Contains -> T.bool
    | Add | Remove | Join | Concat | From_sorted -> tree
    | Insert | Delete -> T.Tup [tree; T.bool]
    | Split -> T.Tup [tree; T.Opt k; tree]
    | Rank -> T.Tup [T.nat; T.bool]) (types ordering ts)

let name = function
  | Get -> "get" | Contains -> "contains" | Add -> "add"
  | Insert -> "insert" | Remove -> "remove" | Delete -> "delete"
  | Join -> "join" | Concat -> "concat" | Split -> "split"
  | Rank -> "rank" | Select -> "select" | From_sorted -> "from_sorted"
