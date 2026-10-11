module V = Mo_values.Value
module N = Mo_values.Numerics
module C = Mo_values.Compute_plugin
open Schema

exception Invalid of string
let invalid () = raise (Invalid "pure set: invalid tree metadata or depth")
let bound = N.Int.of_int64 Int64.max_int
let depth n = if n >= 128 then invalid ()
let fields = function
  | V.Opt (V.Tup [V.Nat32 h; V.Int n; k; l; r]) ->
    N.Nat32.to_int h, n, k, l, r
  | _ -> invalid ()
let height = function V.Null -> 0 | t ->
  let h, _, _, _, _ = fields t in
  if h = 0 || h > 128 then invalid (); h
let size = function V.Null -> N.Int.zero | t ->
  let _, n, _, _, _ = fields t in
  if N.Int.le n N.Int.zero || N.Int.gt n bound then invalid (); n
let entry = function V.Null -> V.Null | t ->
  let _, _, k, _, _ = fields t in V.Opt k
let make l k r =
  let h = 1 + max (height l) (height r) in
  let n = N.Int.add N.Int.one (N.Int.add (size l) (size r)) in
  if h > 128 || N.Int.gt n bound then invalid ();
  V.Opt (V.Tup [V.Nat32 (N.Nat32.of_int h); V.Int n; k; l; r])
let balance l k r =
  let hl = height l and hr = height r in
  if hl > hr + 1 then begin
    let _, _, lk, ll, lr = fields l in
    if height ll >= height lr then make ll lk (make lr k r)
    else let _, _, mk, ml, mr = fields lr in
      make (make ll lk ml) mk (make mr k r)
  end else if hr > hl + 1 then begin
    let _, _, rk, rl, rr = fields r in
    if height rr >= height rl then make (make l k rl) rk rr
    else let _, _, mk, ml, mr = fields rl in
      make (make l k ml) mk (make mr rk rr)
  end else make l k r
let rec join d l k r =
  depth d;
  let hl = height l and hr = height r in
  if hl > hr + 1 then
    let _, _, lk, ll, lr = fields l in
    balance ll lk (join (d + 1) lr k r)
  else if hr > hl + 1 then
    let _, _, rk, rl, rr = fields r in
    balance (join (d + 1) l k rl) rk rr
  else make l k r
let rec pop_min d t =
  depth d;
  let _, _, k, l, r = fields t in
  match l with
  | V.Null -> r, t
  | _ -> let next, old = pop_min (d + 1) l in balance next k r, old
let concat l r = match l, r with
  | V.Null, _ -> r | _, V.Null -> l
  | _ -> let next, old = pop_min 0 r in
    let _, _, k, _, _ = fields old in join 0 l k next

let scalar typ a b =
  match Mo_types.Type.promote typ, a, b with
  | Mo_types.Type.Prim Mo_types.Type.Principal, V.Blob a, V.Blob b ->
    String.compare a b
  | _, _, _ -> V.compare a b

let evaluate operation ordering context ts _types args k =
  let protect f = try f () with Invalid message -> k (Error message) in
  protect (fun () ->
    match ts with
    | [kt] ->
      let tree, comparator, arguments = match operation, ordering, args with
        | (Join | Concat | Select | From_sorted), _, values ->
          V.Null, V.Null, values
        | _, Callback, tree :: cmp :: values -> tree, cmp, values
        | _, Static, tree :: values -> tree, V.Null, values
        | _ -> invalid ()
      in
      let compare a b cont = match ordering with
        | Static -> cont (scalar kt a b)
        | Callback -> context.C.call (Schema.compare kt) comparator [a; b]
          (function
            | Error message -> k (Error message)
            | Ok value -> protect (fun () -> match value with
              | V.Variant ("less", _) -> cont (-1)
              | V.Variant ("equal", _) -> cont 0
              | V.Variant ("greater", _) -> cont 1
              | _ -> invalid ()))
      in
      let rec search d t key cont =
        depth d;
        match t with
        | V.Null -> cont V.Null
        | _ -> let _, _, stored, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then cont t
            else search (d + 1) (if order < 0 then l else r) key cont)
      in
      let rec update d t key cont =
        depth d;
        let replace old = match operation, old with
          | (Add | Insert), V.Null -> cont (make V.Null key V.Null) true
          | (Add | Insert), _ -> cont old false
          | (Remove | Delete), V.Null -> cont old false
          | (Remove | Delete), _ ->
            let _, _, _, l, r = fields old in cont (concat l r) true
          | _ -> invalid ()
        in
        match t with
        | V.Null -> replace t
        | _ -> let _, _, stored, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then replace t
            else update (d + 1) (if order < 0 then l else r) key
              (fun child changed -> cont
                (if not changed then t
                 else if order < 0 then balance child stored r
                 else balance l stored child) changed))
      in
      let rec split d t key cont =
        depth d;
        match t with
        | V.Null -> cont V.Null V.Null V.Null
        | _ -> let _, _, stored, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then cont l t r
            else if order < 0 then split (d + 1) l key
              (fun a found b -> cont a found (join 0 b stored r))
            else split (d + 1) r key
              (fun a found b -> cont (join 0 l stored a) found b))
      in
      let rec rank d t key index =
        depth d;
        if N.Int.gt index bound then invalid ();
        match t with
        | V.Null -> k (Ok (V.Tup [V.Int index; V.Bool false]))
        | _ -> let _, _, stored, l, r = fields t in
          compare key stored (fun order ->
            if order = 0 then begin
              let result = N.Int.add index (size l) in
              if N.Int.gt result bound then invalid ();
              k (Ok (V.Tup [V.Int result; V.Bool true]))
            end else if order < 0 then rank (d + 1) l key index
            else rank (d + 1) r key
              (N.Int.add index (N.Int.add N.Int.one (size l))))
      in
      let rec select d t index =
        depth d;
        match t with
        | V.Null -> V.Null
        | _ -> let _, _, _, l, r = fields t in
          let n = size l in
          if N.Int.eq n index then entry t
          else if N.Int.lt index n then select (d + 1) l index
          else select (d + 1) r (N.Int.sub (N.Int.sub index n) N.Int.one)
      in
      (match operation, arguments with
      | (Get | Contains), [key] -> search 0 tree key (fun found ->
        k (Ok (match operation with
          | Get -> entry found | _ -> V.Bool (found <> V.Null))))
      | (Add | Insert | Remove | Delete), [key] ->
        update 0 tree key (fun next changed -> k (Ok (match operation with
          | Add | Remove -> next | _ -> V.Tup [next; V.Bool changed])))
      | Join, [l; key; r] -> k (Ok (join 0 l key r))
      | Concat, [l; r] -> k (Ok (concat l r))
      | Split, [key] -> split 0 tree key
        (fun l old r -> k (Ok (V.Tup [l; entry old; r])))
      | Rank, [key] -> rank 0 tree key N.Int.zero
      | Select, [t; V.Int index] ->
        k (Ok (if N.Int.ge index (size t) then V.Null else select 0 t index))
      | From_sorted, [V.Array entries] ->
        let rec build start count =
          if count = 0 then V.Null else
          let middle = start + count / 2 in
          make (build start (count / 2)) entries.(middle)
            (build (middle + 1) (count - count / 2 - 1))
        in k (Ok (build 0 (Array.length entries)))
      | _ -> invalid ())
    | _ -> invalid ())
