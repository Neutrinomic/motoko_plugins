open Mo_types
module T = Type

type operation = Push_front | Push_back | Pop_front | Pop_back | Peek_front | Peek_back
  | To_array | To_var_array

let chunk_constructor =
  let con = Cons.fresh "PluginQueueChunk" (T.Abs ([], T.Pre)) in
  let element = T.Var ("T", 0) in
  let binds = [T.{var = "T"; sort = Type; bound = Any}] in
  let chunk = T.Con (con, [element]) in
  T.set_kind con (T.Def (binds, T.obj T.Object [
    "values", T.Array (T.Mut (T.Opt element));
    "meta", T.Mut T.nat32;
    "previous", T.Mut (T.Opt chunk);
    "next", T.Mut (T.Opt chunk);
  ]));
  con

let chunk element = T.Con (chunk_constructor, [element])
let queue element = T.obj T.Object [
  "front", T.Mut (T.Opt (chunk element));
  "back", T.Mut (T.Opt (chunk element));
  "spare", T.Mut (T.Opt (chunk element));
  "size", T.Mut T.nat;
]

let types = function
  | [element] -> Ok element
  | _ -> Error "queue operations require an explicit element type"

let arguments operation ts = Result.map (fun element ->
  match operation with
  | Push_front | Push_back -> [queue element; element]
  | Pop_front | Pop_back | Peek_front | Peek_back | To_array | To_var_array -> [queue element]) (types ts)

let result operation ts _ = Result.map (fun element ->
  match operation with
  | Push_front | Push_back -> T.unit
  | Pop_front | Pop_back | Peek_front | Peek_back -> T.Opt element
  | To_array -> T.Array element
  | To_var_array -> T.Array (T.Mut element)) (types ts)

let name = function
  | Push_front -> "push_front" | Push_back -> "push_back"
  | Pop_front -> "pop_front" | Pop_back -> "pop_back"
  | Peek_front -> "peek_front" | Peek_back -> "peek_back"
  | To_array -> "to_array" | To_var_array -> "to_var_array"
