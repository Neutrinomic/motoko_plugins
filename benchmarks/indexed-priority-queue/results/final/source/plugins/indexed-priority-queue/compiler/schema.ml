open Mo_types
module T = Type

type operation = Push | Peek | Peek_priority | Pop | Get | Remove | Reschedule | Replace | Clear

let queue_constructor, entry_constructor, handle_constructor =
  let queue = Cons.fresh "PluginIndexedPriorityQueue" (T.Abs ([], T.Pre))
  and entry = Cons.fresh "PluginIndexedPriorityQueueEntry" (T.Abs ([], T.Pre))
  and handle = Cons.fresh "PluginIndexedPriorityQueueHandle" (T.Abs ([], T.Pre)) in
  let k = T.Var ("K", 0) and v = T.Var ("V", 1) in
  let binds = List.map (fun var -> T.{var; sort = Type; bound = Any}) ["K"; "V"] in
  let queue_t = T.Con (queue, [k; v])
  and entry_t = T.Con (entry, [k; v])
  and handle_t = T.Con (handle, [k; v]) in
  T.set_kind queue (T.Def (binds, T.obj T.Object [
    "slots", T.Mut (T.Array (T.Mut (T.Opt entry_t)));
    "size", T.Mut T.nat;
  ]));
  T.set_kind entry (T.Def (binds, T.obj T.Object [
    "priority", k; "value", v; "handle", handle_t;
  ]));
  T.set_kind handle (T.Def (binds, T.obj T.Object [
    "owner", T.Mut (T.Opt queue_t); "index", T.Mut T.nat;
  ]));
  queue, entry, handle

let queue k v = T.Con (queue_constructor, [k; v])
let entry k v = T.Con (entry_constructor, [k; v])
let handle k v = T.Con (handle_constructor, [k; v])
let pair k v = T.Tup [k; v]
let order = T.Variant (List.map
  (fun lab -> T.{lab; typ = unit; src = empty_src})
  ["equal"; "greater"; "less"])
let compare k = T.Func (T.Local, T.Returns, [], [k; k], [order])
let types = function
  | [k; v] -> Ok (k, v)
  | _ -> Error "indexed priority queue operations require explicit priority and value types"
let arguments operation ts = Result.map (fun (k, v) ->
  match operation with
  | Push -> [queue k v; compare k; k; v]
  | Peek | Peek_priority | Clear -> [queue k v]
  | Pop -> [queue k v; compare k]
  | Get -> [handle k v]
  | Remove -> [handle k v; compare k]
  | Reschedule -> [handle k v; compare k; k]
  | Replace -> [handle k v; compare k; k; v]) (types ts)
let result operation ts _arguments = Result.map (fun (k, v) ->
  match operation with
  | Push -> handle k v
  | Peek | Pop | Get | Remove | Replace -> T.Opt (pair k v)
  | Peek_priority -> T.Opt k
  | Reschedule -> T.bool
  | Clear -> T.unit) (types ts)
let name = function
  | Push -> "push" | Peek -> "peek" | Peek_priority -> "peek_priority"
  | Pop -> "pop" | Get -> "get"
  | Remove -> "remove" | Reschedule -> "reschedule" | Replace -> "replace"
  | Clear -> "clear"
