module V = Mo_values.Value
module N = Mo_values.Numerics
module C = Mo_values.Compute_plugin
open Schema

exception Invalid of string
let invalid () = raise (Invalid "pure map: invalid tree metadata or depth")
let bound = N.Int.of_int64 Int64.max_int
let depth n = if n >= 128 then invalid ()
let fields = function
  | V.Opt (V.Tup [V.Nat32 h; V.Int n; k; v; l; r]) ->
    let h = N.Nat32.to_int h in
    h, n, k, v, l, r
  | _ -> invalid ()
let height = function V.Null -> 0 | t ->
  let h, _, _, _, _, _ = fields t in
  if h = 0 || h > 128 then invalid (); h
let size = function V.Null -> N.Int.zero | t ->
  let _, n, _, _, _, _ = fields t in
  if N.Int.le n N.Int.zero || N.Int.gt n bound then invalid (); n
let entry = function V.Null -> V.Null | t -> let _, _, k, v, _, _ = fields t in V.Opt (V.Tup [k; v])
let value = function V.Null -> V.Null | t -> let _, _, _, v, _, _ = fields t in V.Opt v
let make l k v r =
  let h = 1 + max (height l) (height r) in
  let n = N.Int.add N.Int.one (N.Int.add (size l) (size r)) in
  if h > 128 || N.Int.gt n bound then invalid ();
  V.Opt (V.Tup [V.Nat32 (N.Nat32.of_int h); V.Int n; k; v; l; r])
let copy old k v l r = match old with
  | V.Opt (V.Tup [h; n; _; _; _; _]) -> V.Opt (V.Tup [h; n; k; v; l; r])
  | _ -> invalid ()
let balance l k v r =
  let hl = height l and hr = height r in
  if hl > hr + 1 then begin
    let _, _, lk, lv, ll, lr = fields l in
    if height ll >= height lr then make ll lk lv (make lr k v r)
    else let _, _, mk, mv, ml, mr = fields lr in
      make (make ll lk lv ml) mk mv (make mr k v r)
  end else if hr > hl + 1 then begin
    let _, _, rk, rv, rl, rr = fields r in
    if height rr >= height rl then make (make l k v rl) rk rv rr
    else let _, _, mk, mv, ml, mr = fields rl in
      make (make l k v ml) mk mv (make mr rk rv rr)
  end else make l k v r
let rec join d l k v r =
  depth d;
  let hl = height l and hr = height r in
  if hl > hr + 1 then
    let _, _, lk, lv, ll, lr = fields l in
    balance ll lk lv (join (d + 1) lr k v r)
  else if hr > hl + 1 then
    let _, _, rk, rv, rl, rr = fields r in
    balance (join (d + 1) l k v rl) rk rv rr
  else make l k v r
let rec pop_min d t =
  depth d;
  let _, _, k, v, l, r = fields t in
  match l with
  | V.Null -> r, t
  | _ -> let next, old = pop_min (d + 1) l in balance next k v r, old
let concat l r = match l, r with
  | V.Null, _ -> r | _, V.Null -> l
  | _ -> let next, old = pop_min 0 r in
    let _, _, k, v, _, _ = fields old in join 0 l k v next

let scalar typ a b =
  let compare = match Mo_types.Type.promote typ, a, b with
    | Mo_types.Type.Prim Mo_types.Type.Principal, V.Blob a, V.Blob b -> String.compare a b
    | _, _, _ -> V.compare a b
  in compare

let evaluate operation ordering context ts _types args k =
  let protect f = try f () with Invalid message -> k (Error message) in
  protect (fun () ->
    match ts with
    | [kt; vt] ->
      let tree, comparator, arguments = match operation, ordering, args with
        | (Join | Concat | Select | From_sorted), _, values -> V.Null, V.Null, values
        | _, Callback, tree :: cmp :: values -> tree, cmp, values
        | _, Static, tree :: values -> tree, V.Null, values
        | _ -> invalid ()
      in
      let call typ callback args cont = context.C.call typ callback args (function
        | Error message -> k (Error message)
        | Ok value -> protect (fun () -> cont value)) in
      let compare a b cont = match ordering with
        | Static -> cont (scalar kt a b)
        | Callback -> call (Schema.compare kt) comparator [a; b] (function
          | V.Variant ("less", _) -> cont (-1)
          | V.Variant ("equal", _) -> cont 0
          | V.Variant ("greater", _) -> cont 1
          | _ -> invalid ())
      in
      let rec search d t key cont =
        depth d;
        match t with
        | V.Null -> cont V.Null
        | _ -> let _, _, stored, _, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then cont t
            else search (d + 1) (if order < 0 then l else r) key cont)
      in
      let rec update d t key payload cont =
        depth d;
        let finish old replacement = match replacement with
          | V.Null -> (match old with
            | V.Null -> cont old old 0
            | _ -> let _, _, _, _, l, r = fields old in cont (concat l r) old 2)
          | V.Opt v -> let l, r = match old with
            | V.Null -> V.Null, V.Null
            | _ -> let _, _, _, _, l, r = fields old in l, r in
            (match old with
            | V.Null -> cont (make l key v r) old 2
            | _ -> cont (copy old key v l r) old 1)
          | _ -> invalid ()
        in
        let replace old = match operation with
          | Remove | Take -> finish old V.Null
          | Add | Put -> finish old (V.Opt payload)
          | Replace -> (match old with
            | V.Null -> cont old old 0
            | _ -> finish old (V.Opt payload))
          | Alter -> call (alteration vt) payload [value old] (finish old)
          | _ -> invalid ()
        in
        match t with
        | V.Null -> replace t
        | _ -> let _, _, stored, v, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then replace t
            else update (d + 1) (if order < 0 then l else r) key payload
              (fun child old changed ->
                cont (if changed = 0 then t else
                  if changed = 1 then
                    if order < 0 then copy t stored v child r else copy t stored v l child
                  else if order < 0 then balance child stored v r
                  else balance l stored v child) old changed))
      in
      let rec split d t key cont =
        depth d;
        match t with
        | V.Null -> cont V.Null V.Null V.Null
        | _ -> let _, _, stored, v, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then cont l t r
            else if order < 0 then
              split (d + 1) l key (fun a found b -> cont a found (join 0 b stored v r))
            else split (d + 1) r key (fun a found b -> cont (join 0 l stored v a) found b))
      in
      let rec rank d t key index =
        depth d;
        if N.Int.gt index bound then invalid ();
        match t with
        | V.Null -> k (Ok (V.Tup [V.Int index; V.Bool false]))
        | _ -> let _, _, stored, _, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then begin
              let result = N.Int.add index (size l) in
              if N.Int.gt result bound then invalid ();
              k (Ok (V.Tup [V.Int result; V.Bool true]))
            end
            else if order < 0 then rank (d + 1) l key index
            else rank (d + 1) r key (N.Int.add index (N.Int.add N.Int.one (size l))))
      in
      let rec select d t index =
        depth d;
        match t with
        | V.Null -> V.Null
        | _ -> let _, _, _, _, l, r = fields t in
          let n = size l in
          if N.Int.eq n index then entry t
          else if N.Int.lt index n then select (d + 1) l index
          else select (d + 1) r (N.Int.sub (N.Int.sub index n) N.Int.one)
      in
      let finish_update next old _changed =
        k (Ok (match operation with
          | Add | Remove -> next
          | Replace -> V.Tup [next; value old]
          | _ -> V.Tup [next; entry old])) in
      (match operation, arguments with
      | (Get | Get_entry | Contains), [key] -> search 0 tree key (fun found ->
        k (Ok (match operation with
          | Get -> value found | Contains -> V.Bool (found <> V.Null) | _ -> entry found)))
      | (Add | Put | Replace | Alter), [key; payload] -> update 0 tree key payload finish_update
      | (Remove | Take), [key] -> update 0 tree key V.Null finish_update
      | Join, [l; key; v; r] -> k (Ok (join 0 l key v r))
      | Concat, [l; r] -> k (Ok (concat l r))
      | Split, [key] -> split 0 tree key (fun l old r -> k (Ok (V.Tup [l; entry old; r])))
      | Rank, [key] -> rank 0 tree key N.Int.zero
      | Select, [t; V.Int index] ->
        k (Ok (if N.Int.ge index (size t) then V.Null else select 0 t index))
      | From_sorted, [V.Array entries] ->
        let rec build start count =
          if count = 0 then V.Null else
          let middle = start + count / 2 in
          let key, value = match entries.(middle) with V.Tup [k; v] -> k, v | _ -> invalid () in
          make (build start (count / 2)) key value
            (build (middle + 1) (count - count / 2 - 1))
        in k (Ok (build 0 (Array.length entries)))
      | _ -> invalid ())
    | _ -> invalid ())
