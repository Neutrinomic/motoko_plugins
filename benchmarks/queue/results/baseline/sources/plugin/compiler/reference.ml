module V = Mo_values.Value
module N = Mo_values.Numerics
open Schema

exception Invalid
let invalid () = raise Invalid
let fields = function V.Obj fields -> fields | _ -> invalid ()
let field obj label = try V.Env.find label (fields obj) with Not_found -> invalid ()
let read obj label = match field obj label with V.Mut value -> !value | value -> value
let write obj label value = match field obj label with
  | V.Mut slot -> slot := value
  | _ -> invalid ()
let unwrap = function V.Opt value -> value | _ -> invalid ()
let array obj = match read obj "values" with
  | V.Array values when Array.length values = 32 -> values
  | _ -> invalid ()
let get values index =
  if index < 0 || index >= Array.length values then invalid ();
  match values.(index) with V.Mut value -> !value | _ -> invalid ()
let set values index value =
  if index < 0 || index >= Array.length values then invalid ();
  match values.(index) with V.Mut slot -> slot := value | _ -> invalid ()
let nat32 obj label limit = match read obj label with
  | V.Nat32 value ->
      let value = N.Nat32.to_int value in
      if value < 0 || value > limit then invalid ();
      value
  | _ -> invalid ()
let set_nat32 obj label value = write obj label (V.Nat32 (N.Nat32.of_int value))
let count obj = nat32 obj "count" 32
let start obj = nat32 obj "start" 31
let object_ items = V.Obj (List.fold_left (fun env (label, value) ->
  V.Env.add label value env) V.Env.empty items)
let mutable_ value = V.Mut (ref value)
let new_chunk () = object_ [
  "values", V.Array (Array.init 32 (fun _ -> mutable_ V.Null));
  "start", mutable_ (V.Nat32 (N.Nat32.of_int 0));
  "count", mutable_ (V.Nat32 (N.Nat32.of_int 0));
  "previous", mutable_ V.Null;
  "next", mutable_ V.Null;
]
let max_size = N.Int.of_string "18446744073709551615"
let size queue = match read queue "size" with
  | V.Int value when not (N.Int.lt value N.Int.zero) -> value
  | _ -> invalid ()
let set_size queue value = write queue "size" (V.Int value)

let evaluate operation _context ts _types args continuation =
  try
    (match ts with [_] -> () | _ -> invalid ());
    let queue, value = match operation, args with
      | (Push_front | Push_back), [queue; value] -> queue, value
      | (Pop_front | Pop_back | Peek_front | Peek_back), [queue] -> queue, V.Null
      | _ -> invalid () in
    let front = match operation with
      | Push_front | Pop_front | Peek_front -> true
      | Push_back | Pop_back | Peek_back -> false in
    let endpoint = if front then "front" else "back" in
    let inward = if front then "next" else "previous" in
    let outward = if front then "previous" else "next" in
    let answer = match operation with
      | Push_front | Push_back ->
          let current = match read queue endpoint with
            | V.Null ->
                let current = new_chunk () in
                write queue "front" (V.Opt current);
                write queue "back" (V.Opt current);
                current
            | value -> unwrap value in
          ignore (start current);
          ignore (array current);
          let current = if count current = 32 then begin
              let next = new_chunk () in
              write next inward (V.Opt current);
              write current outward (V.Opt next);
              write queue endpoint (V.Opt next);
              next
            end else current in
          let offset = start current and n = count current in
          let index = (if front then offset + 31 else offset + n) land 31 in
          set (array current) index (V.Opt value);
          if front then set_nat32 current "start" index;
          set_nat32 current "count" (n + 1);
          set_size queue (N.Int.add (size queue) (N.Int.of_int 1));
          V.Tup []
      | Pop_front | Pop_back | Peek_front | Peek_back ->
          (match read queue endpoint with
          | V.Null -> V.Null
          | value ->
              let current = unwrap value in
              let n = count current and offset = start current in
              let values = array current in
              if n = 0 then V.Null else begin
                let index = (if front then offset else offset + n - 1) land 31 in
                let old = get values index in
                (match old with V.Opt _ -> () | _ -> invalid ());
                (match operation with
                | Pop_front | Pop_back ->
                    let length = size queue in
                    if N.Int.eq length N.Int.zero || N.Int.gt length max_size then invalid ();
                    set values index V.Null;
                    if front then set_nat32 current "start" ((offset + 1) land 31);
                    set_nat32 current "count" (n - 1);
                    set_size queue (N.Int.sub length (N.Int.of_int 1));
                    if n = 1 then (match read current inward with
                      | V.Null -> ()
                      | value ->
                          let adjacent = unwrap value in
                          write adjacent outward V.Null;
                          write current inward V.Null;
                          write queue endpoint value)
                | Peek_front | Peek_back -> ()
                | Push_front | Push_back -> invalid ());
                old
              end) in
    continuation (Ok answer)
  with Invalid -> continuation (Error "queue: malformed storage")
