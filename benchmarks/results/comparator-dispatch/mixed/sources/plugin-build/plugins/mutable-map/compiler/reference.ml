module V = Mo_values.Value
module N = Mo_values.Numerics
module C = Mo_values.Compute_plugin
open Schema
exception Invalid
let invalid () = raise Invalid
let depth n = if n >= 64 then invalid ()
let fields = function V.Obj fields -> fields | _ -> invalid ()
let field obj label = try V.Env.find label (fields obj) with Not_found -> invalid ()
let read obj label = match field obj label with V.Mut v -> !v | v -> v
let write obj label value = match field obj label with V.Mut slot -> slot := value | _ -> invalid ()
let unwrap = function V.Opt value -> value | _ -> invalid ()
let array obj label = match read obj label with V.Array a -> a | _ -> invalid ()
let get a i = if i < 0 || i >= Array.length a then invalid (); match a.(i) with V.Mut v -> !v | _ -> invalid ()
let set a i v = if i < 0 || i >= Array.length a then invalid (); match a.(i) with V.Mut slot -> slot := v | _ -> invalid ()
let count obj = match read obj "count" with
  | V.Nat32 n -> let n = N.Nat32.to_int n in if n > 31 then invalid (); n | _ -> invalid ()
let set_count obj n = if n < 0 || n > 31 then invalid (); write obj "count" (V.Nat32 (N.Nat32.of_int n))
let leaf obj = Array.length (array obj "children") = 0
let item obj i = get (array obj "entries") i
let child obj i = unwrap (get (array obj "children") i)
let set_item obj i v = set (array obj "entries") i v
let set_child obj i v = set (array obj "children") i v
let key entry = match unwrap entry with V.Tup [k; _] -> k | _ -> invalid ()
let value entry = match entry with V.Null -> V.Null | _ -> match unwrap entry with V.Tup [_; v] -> V.Opt v | _ -> invalid ()
let object_ items = V.Obj (List.fold_left (fun env (label, value) -> V.Env.add label value env) V.Env.empty items)
let node is_leaf = object_ [
  "count", V.Mut (ref (V.Nat32 (N.Nat32.of_int 0)));
  "entries", V.Array (Array.init 31 (fun _ -> V.Mut (ref V.Null)));
  "children", V.Array (Array.init (if is_leaf then 0 else 32) (fun _ -> V.Mut (ref V.Null)));
]
let shift_right a first finish = for i = finish downto first + 1 do set a i (get a (i - 1)) done
let shift_left a first finish = for i = first to finish - 1 do set a i (get a (i + 1)) done; set a finish V.Null
let split parent index =
  let left = child parent index in
  let right = node (leaf left) and median = item left 15 and n = count parent in
  for i = 0 to 14 do set_item right i (item left (i + 16)); set_item left (i + 16) V.Null done;
  set_item left 15 V.Null;
  if not (leaf left) then for i = 0 to 15 do set_child right i (get (array left "children") (i + 16)); set_child left (i + 16) V.Null done;
  shift_right (array parent "entries") index n;
  shift_right (array parent "children") (index + 1) (n + 1);
  set_item parent index median; set_child parent (index + 1) (V.Opt right);
  set_count left 15; set_count right 15; set_count parent (n + 1)
let merge parent index =
  let left = child parent index and right = child parent (index + 1) in
  let nl = count left and nr = count right and np = count parent in
  if nl + nr + 1 > 31 then invalid ();
  set_item left nl (item parent index);
  for i = 0 to nr - 1 do set_item left (nl + 1 + i) (item right i); set_item right i V.Null done;
  if not (leaf left) then for i = 0 to nr do
    set_child left (nl + 1 + i) (get (array right "children") i); set_child right i V.Null done;
  shift_left (array parent "entries") index (np - 1);
  shift_left (array parent "children") (index + 1) np;
  set_count left (nl + nr + 1); set_count right 0; set_count parent (np - 1); left
let borrow_left parent index =
  let target = child parent index and sibling = child parent (index - 1) in
  let n = count target and s = count sibling in
  shift_right (array target "entries") 0 n;
  set_item target 0 (item parent (index - 1));
  set_item parent (index - 1) (item sibling (s - 1)); set_item sibling (s - 1) V.Null;
  if not (leaf target) then begin
    shift_right (array target "children") 0 (n + 1);
    set_child target 0 (get (array sibling "children") s); set_child sibling s V.Null
  end;
  set_count target (n + 1); set_count sibling (s - 1)
let borrow_right parent index =
  let target = child parent index and sibling = child parent (index + 1) in
  let n = count target and s = count sibling in
  set_item target n (item parent index); set_item parent index (item sibling 0);
  shift_left (array sibling "entries") 0 (s - 1);
  if not (leaf target) then begin
    set_child target (n + 1) (get (array sibling "children") 0);
    shift_left (array sibling "children") 0 s
  end;
  set_count target (n + 1); set_count sibling (s - 1)
let collapse map = match read map "root" with
  | V.Null -> ()
  | V.Opt root when count root = 0 -> write map "root" (if leaf root then V.Null else get (array root "children") 0)
  | _ -> ()
let rec extreme d root right =
  depth d;
  if leaf root then item root (if right then count root - 1 else 0)
  else extreme (d + 1) (child root (if right then count root else 0)) right
let max_size = N.Int.of_string "18446744073709551615"
let change_size map delta = match read map "size" with
  | V.Int size ->
      if delta < 0 && N.Int.gt size max_size then invalid ();
      let next = N.Int.add size (N.Int.of_int delta) in
      if N.Int.lt next N.Int.zero then invalid ();
      write map "size" (V.Int next)
  | _ -> invalid ()
let scalar typ a b = match Mo_types.Type.promote typ, a, b with
  | Mo_types.Type.Prim Mo_types.Type.Principal, V.Blob a, V.Blob b -> String.compare a b
  | _ -> V.compare a b
let evaluate operation ordering context ts _types args continuation =
  let protect f = try f () with Invalid -> continuation (Error "mutable-map: malformed tree") in
  protect (fun () ->
    let kt = match ts with [kt; _] -> kt | _ -> invalid () in
    let map, comparator, needle, payload = match ordering, args with
      | Callback, map :: comparator :: needle :: rest -> map, comparator, needle, rest
      | Static, map :: needle :: rest -> map, V.Null, needle, rest
      | _ -> invalid () in
    let payload = match payload with [v] -> v | _ -> V.Null in
    let compare a b cont = match ordering with
      | Static -> cont (scalar kt a b)
      | Callback -> context.C.call (Schema.compare kt) comparator [a; b] (function
          | Error message -> continuation (Error message)
          | Ok order -> protect (fun () -> cont (match order with
              | V.Variant ("less", _) -> -1 | V.Variant ("equal", _) -> 0
              | V.Variant ("greater", _) -> 1 | _ -> invalid ()))) in
    let locate current needle cont =
      let rec loop lo hi = if lo >= hi then cont lo false else
        let mid = (lo + hi) / 2 in
        compare needle (key (item current mid)) (fun order ->
          if order = 0 then cont mid true else if order < 0 then loop lo mid else loop (mid + 1) hi)
      in loop 0 (count current) in
    let rec search d tree cont = depth d; match tree with
      | V.Null -> cont V.Null 0
      | V.Opt current -> locate current needle (fun index found ->
          if found then cont tree index else if leaf current then cont V.Null 0
          else search (d + 1) (get (array current "children") index) cont)
      | _ -> invalid () in
    let replacement = V.Opt (V.Tup [needle; payload]) in
    let rec insert d current cont = depth d;
      locate current needle (fun index found ->
        if found then let old = item current index in set_item current index replacement; cont old
        else if leaf current then begin
          let n = count current in shift_right (array current "entries") index n;
          set_item current index replacement; set_count current (n + 1); change_size map 1; cont V.Null
        end else if count (child current index) = 31 then begin
          split current index;
          compare needle (key (item current index)) (fun order ->
            if order = 0 then let old = item current index in set_item current index replacement; cont old
            else insert (d + 1) (child current (if order < 0 then index else index + 1)) cont)
        end else insert (d + 1) (child current index) cont) in
    let rec delete d current needle cont = depth d;
      locate current needle (fun index found ->
        if found then begin
          let old = item current index in
          if leaf current then begin
            let n = count current in shift_left (array current "entries") index (n - 1);
            set_count current (n - 1); cont old
          end else begin
            let left = child current index and right = child current (index + 1) in
            if count left > 15 then
              let replacement = extreme 0 left true in
              delete (d + 1) left (key replacement) (fun _ -> set_item current index replacement; cont old)
            else if count right > 15 then
              let replacement = extreme 0 right false in
              delete (d + 1) right (key replacement) (fun _ -> set_item current index replacement; cont old)
            else let next = merge current index in collapse map; delete (d + 1) next needle (fun _ -> cont old)
          end
        end else if leaf current then cont V.Null else begin
          let next = child current index in
          let next = if count next <> 15 then next
            else if index > 0 && count (child current (index - 1)) > 15 then (borrow_left current index; next)
            else if index < count current && count (child current (index + 1)) > 15 then (borrow_right current index; next)
            else let next = merge current (if index < count current then index else index - 1) in collapse map; next
          in delete (d + 1) next needle cont
        end) in
    let finish old = continuation (Ok (match operation with
      | Get_entry -> old | Get | Swap | Replace | Take -> value old
      | Contains | Delete -> V.Bool (old <> V.Null)
      | Insert -> V.Bool (old = V.Null) | Add | Remove -> V.Tup [])) in
    match operation with
    | Get | Get_entry | Contains | Replace -> search 0 (read map "root") (fun node index ->
        let old = match node with V.Null -> V.Null | _ -> item (unwrap node) index in
        if operation = Replace && node <> V.Null then set_item (unwrap node) index replacement;
        finish old)
    | Add | Insert | Swap ->
        let root = match read map "root" with V.Null -> let root = node true in write map "root" (V.Opt root); root | root -> unwrap root in
        let root = if count root = 31 then begin
          let next = node false in set_child next 0 (V.Opt root); split next 0; write map "root" (V.Opt next); next
        end else root in insert 0 root finish
    | Remove | Delete | Take -> (match read map "root" with
        | V.Null -> finish V.Null
        | root -> delete 0 (unwrap root) needle (fun old -> collapse map; if old <> V.Null then change_size map (-1); finish old)))
