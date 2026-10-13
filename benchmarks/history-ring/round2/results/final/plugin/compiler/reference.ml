module V = Mo_values.Value
module N = Mo_values.Numerics
open Schema
exception Invalid
let invalid () = raise Invalid
let field obj label = match obj with V.Obj f -> (try V.Env.find label f with Not_found -> invalid ()) | _ -> invalid ()
let read obj label = match field obj label with V.Mut r -> !r | v -> v
let write obj label v = match field obj label with V.Mut r -> r := v | _ -> invalid ()
let nat = function V.Int n when N.Int.ge n N.Int.zero -> n | _ -> invalid ()
let number obj label = nat (read obj label)
let small v = try N.Int.to_int (nat v) with _ -> invalid ()
let integer n = V.Int (N.Int.of_int n)
let array = function V.Array a -> a | _ -> invalid ()
let get a i = if i < 0 || i >= Array.length a then invalid (); match a.(i) with V.Mut r -> !r | _ -> invalid ()
let set a i v = if i < 0 || i >= Array.length a then invalid (); match a.(i) with V.Mut r -> r := v | _ -> invalid ()
let mutable_array n f = V.Array (Array.init n (fun i -> V.Mut (ref (f i))))
let unwrap = function V.Opt v -> v | _ -> invalid ()
let chunks ring = array (read ring "chunks")
let width ring = let w = small (read ring "chunkSize") in if w < 1 || w > 64 then invalid (); w
let size ring = small (read ring "size")
let head ring = small (read ring "head")
let reset ring = write ring "chunks" (mutable_array 0 (fun _ -> V.Null)); write ring "head" (integer 0); write ring "size" (integer 0)
let slot ring physical = let w = width ring in array (unwrap (get (chunks ring) (physical / w))), physical mod w
let entry ring physical = let a, i = slot ring physical in get a i
let set_entry ring physical value = let a, i = slot ring physical in set a i value
let grow ring =
  let old = chunks ring and w = width ring in
  let old_n = Array.length old in
  let proposed = max 1 (old_n * 2) in
  let cap = number ring "capacity" in
  let n = if N.Int.lt cap (N.Int.of_int (proposed * w))
    then (N.Int.to_int cap + w - 1) / w else proposed in
  if n <= old_n then invalid ();
  let h = head ring in
  let first_chunk = h / w and offset = h mod w in
  let next = array (mutable_array n (fun i -> if i < old_n then get old ((first_chunk + i) mod old_n) else V.Null)) in
  if offset <> 0 then begin
    let first = array (unwrap (get next 0)) in
    let split = array (mutable_array w (fun i -> if i < offset then get first i else V.Null)) in
    for i = 0 to offset - 1 do set first i V.Null done;
    set next old_n (V.Opt (V.Array split))
  end;
  write ring "chunks" (V.Array next); write ring "head" (integer offset)
let physical ring offset = let cap = Array.length (chunks ring) * width ring in if cap = 0 then invalid (); (head ring + offset) mod cap
let remove ring release =
  let n = size ring in if n = 0 then V.Null else begin
    let w = width ring and h = head ring in
    let old = entry ring h in
    set_entry ring h V.Null;
    let next_h = (h + 1) mod (Array.length (chunks ring) * w) in
    write ring "head" (integer next_h); write ring "size" (integer (n - 1));
    if release then begin
      if n = 1 then reset ring
      else if next_h mod w = 0 && n - 1 <= (Array.length (chunks ring) - 1) * w
      then set (chunks ring) (h / w) V.Null
    end;
    old
  end
let evaluate operation _context _ts _types args continuation =
  try
    let result = match operation, args with
    | Append, [ring; value] ->
      let sequence = read ring "next" in
      let cap = number ring "capacity" in
      if not (N.Int.eq cap N.Int.zero) then begin
        if N.Int.eq (number ring "size") cap then ignore (remove ring false);
        if size ring = Array.length (chunks ring) * width ring then grow ring;
        let p = physical ring (size ring) in
        let w = width ring in
        if get (chunks ring) (p / w) = V.Null then
          set (chunks ring) (p / w) (V.Opt (mutable_array w (fun _ -> V.Null)));
        set_entry ring p (V.Opt value);
        write ring "size" (integer (size ring + 1))
      end;
      write ring "next" (V.Int (N.Int.add (nat sequence) N.Int.one)); sequence
    | Get, [ring; sequence] ->
      let index = nat sequence and finish = number ring "next" in
      let first = N.Int.sub finish (number ring "size") in
      if N.Int.lt index first || N.Int.ge index finish then V.Null
      else entry ring (physical ring (N.Int.to_int (N.Int.sub index first)))
    | Pop_front, [ring] -> remove ring true
    | Drop, [ring; count] ->
      let count = nat count in let n = size ring in
      let count = if N.Int.ge count (N.Int.of_int n) then n else N.Int.to_int count in
      if count = n then reset ring else for _ = 1 to count do ignore (remove ring true) done;
      integer count
    | Page, [ring; sequence; limit] ->
      let finish = number ring "next" in let first = N.Int.sub finish (number ring "size") in
      let start = if N.Int.lt (nat sequence) first then first else nat sequence in
      if N.Int.ge start finish then V.Array [||] else begin
        let available = N.Int.sub finish start in
        let n = N.Int.to_int (if N.Int.lt (nat limit) available then nat limit else available) in
        let offset = N.Int.to_int (N.Int.sub start first) in
        V.Array (Array.init n (fun i -> unwrap (entry ring (physical ring (offset + i)))))
      end
    | _ -> invalid ()
    in continuation (Ok result)
  with Invalid -> continuation (Error "history-ring: malformed storage")
