module V = Mo_values.Value
module N = Mo_values.Numerics
module C = Mo_values.Compute_plugin
open Schema

exception Invalid
let invalid () = raise Invalid
let fields = function V.Obj fields -> fields | _ -> invalid ()
let field obj label = try V.Env.find label (fields obj) with Not_found -> invalid ()
let read obj label = match field obj label with V.Mut slot -> !slot | value -> value
let write obj label value = match field obj label with
  | V.Mut slot -> slot := value | _ -> invalid ()
let object_ items = V.Obj (List.fold_left
  (fun env (label, value) -> V.Env.add label value env) V.Env.empty items)
let nat n = V.Int (N.Int.of_int n)
let index limit = function
  | V.Int n when N.Int.le N.Int.zero n && N.Int.le n (N.Int.of_int limit) -> N.Int.to_int n
  | _ -> invalid ()
let array = function V.Array slots -> slots | _ -> invalid ()
let slots queue = array (read queue "slots")
let size queue = index (Array.length (slots queue)) (read queue "size")
let get_slot slots i =
  if i < 0 || i >= Array.length slots then invalid ();
  match slots.(i) with V.Mut slot -> !slot | _ -> invalid ()
let set_slot slots i value =
  if i < 0 || i >= Array.length slots then invalid ();
  match slots.(i) with V.Mut slot -> slot := value | _ -> invalid ()
let entry_at queue i = match get_slot (slots queue) i with
  | V.Opt entry -> entry | _ -> invalid ()
let result entry = V.Opt (V.Tup [read entry "priority"; read entry "value"])
let entry priority value handle = object_ [
  "priority", V.Mut (ref priority); "value", V.Mut (ref value); "handle", handle;
]
let invalidate entry = write (read entry "handle") "owner" V.Null
let place queue i entry =
  set_slot (slots queue) i (V.Opt entry);
  write (read entry "handle") "index" (nat i)
let swap queue i j =
  let left = entry_at queue i and right = entry_at queue j in
  place queue i right; place queue j left
let resize queue capacity =
  let old = slots queue and count = size queue in
  if capacity < count then invalid ();
  write queue "slots" (V.Array (Array.init capacity
    (fun i -> V.Mut (ref (if i < count then get_slot old i else V.Null)))))
let shrink queue =
  let capacity = Array.length (slots queue) and count = size queue in
  if count = 0 then resize queue 0
  else if capacity > 8 && count <= capacity / 4 then resize queue (capacity / 2)
let active handle = match read handle "owner" with
  | V.Null -> None
  | V.Opt queue ->
      let count = size queue in
      if count = 0 then invalid ();
      let i = index (count - 1) (read handle "index") in
      let item = entry_at queue i in
      Some (queue, i, item)
  | _ -> invalid ()

let evaluate operation context ts _types args continuation =
  let protect f = try f () with Invalid ->
    continuation (Error "indexed-priority-queue: malformed storage") in
  protect (fun () ->
    let kt = match ts with [kt; _] -> kt | _ -> invalid () in
    let finish value = continuation (Ok value) in
    let comparator = match operation, args with
      | (Push | Pop | Remove | Reschedule | Replace), _ :: comparator :: _ -> comparator
      | (Peek | Get | Clear), _ -> V.Null
      | _ -> invalid () in
    let less left right cont =
      context.C.call (Schema.compare kt) comparator
        [read left "priority"; read right "priority"] (function
          | Error message -> continuation (Error message)
          | Ok order -> protect (fun () -> match order with
              | V.Variant ("less", _) -> cont true
              | V.Variant (("equal" | "greater"), _) -> cont false
              | _ -> invalid ())) in
    let rec sift_up queue i cont =
      if i = 0 then cont () else
      let parent = (i - 1) / 2 in
      less (entry_at queue i) (entry_at queue parent) (fun move ->
        if move then (swap queue i parent; sift_up queue parent cont) else cont ()) in
    let rec sift_down queue i cont =
      let count = size queue in
      (* This form also avoids overflowing the child-index calculation. *)
      if count < 2 || i > (count - 2) / 2 then cont () else
      let left = i * 2 + 1 in
      let choose child = less (entry_at queue child) (entry_at queue i) (fun move ->
        if move then (swap queue i child; sift_down queue child cont) else cont ()) in
      if left + 1 = count then choose left else
      less (entry_at queue (left + 1)) (entry_at queue left)
        (fun right_less -> choose (if right_less then left + 1 else left)) in
    let repair queue i cont =
      if i = 0 then sift_down queue i cont else
      let parent = (i - 1) / 2 in
      less (entry_at queue i) (entry_at queue parent) (fun move_up ->
        if move_up then (swap queue i parent; sift_up queue parent cont)
        else sift_down queue i cont) in
    let remove queue i old =
      let count = size queue in
      let last = count - 1 in
      invalidate old;
      if i <> last then place queue i (entry_at queue last);
      set_slot (slots queue) last V.Null;
      write queue "size" (nat last);
      let finish_remove () = shrink queue; finish (result old) in
      if i = last then finish_remove ()
      else repair queue i finish_remove in
    match operation, args with
    | Push, [queue; _; priority; value] ->
        let count = size queue and capacity = Array.length (slots queue) in
        if count = capacity then begin
          if capacity > Sys.max_array_length / 2 then invalid ();
          resize queue (if capacity = 0 then 8 else capacity * 2)
        end;
        let handle = object_ [
          "owner", V.Mut (ref (V.Opt queue)); "index", V.Mut (ref (nat count));
        ] in
        place queue count (entry priority value handle);
        write queue "size" (nat (count + 1));
        sift_up queue count (fun () -> finish handle)
    | Peek, [queue] ->
        finish (if size queue = 0 then V.Null else result (entry_at queue 0))
    | Pop, [queue; _] ->
        if size queue = 0 then finish V.Null else remove queue 0 (entry_at queue 0)
    | Get, [handle] -> finish (match active handle with
        | None -> V.Null | Some (_, _, item) -> result item)
    | Remove, [handle; _] -> (match active handle with
        | None -> finish V.Null | Some (queue, i, old) -> remove queue i old)
    | (Reschedule | Replace), handle :: _ :: priority :: rest ->
        (match active handle with
        | None -> finish (if operation = Reschedule then V.Bool false else V.Null)
        | Some (queue, i, old) ->
            let value = match operation, rest with
              | Reschedule, [] -> read old "value"
              | Replace, [value] -> value
              | _ -> invalid () in
            let previous = if operation = Replace then result old else V.Bool true in
            write old "priority" priority;
            write old "value" value;
            repair queue i (fun () ->
              finish previous))
    | Clear, [queue] ->
        for i = 0 to size queue - 1 do invalidate (entry_at queue i) done;
        write queue "size" (nat 0);
        write queue "slots" (V.Array [||]);
        finish (V.Tup [])
    | _ -> invalid ())
