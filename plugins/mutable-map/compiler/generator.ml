module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module C = Mo_values.Compute_plugin
open Wasm_exts.Ast
open Wasm_exts.Types
open Schema
let ( ^^ ) = G.( ^^ )

(* Degree-16 B-tree: at most 31 entries, at least 15 outside the root.
   Structural steps finish before invoking a comparator. All retained state is
   managed; the SDK supplies forwarding, bounds checks and mutation barriers. *)
module Make (B : P.Backend) = struct
  type comparison = Dynamic | Scalar of T.prim
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let add = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let half = num 1 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.ShrU))
  let eq = compile_comparison I64Op.Eq
  let lt = compile_comparison I64Op.LtU
  let gt = compile_comparison I64Op.GtU
  let ifv = E.if1 I64Type
  let null env = Opt.null_lit env
  let present env x = x ^^ Opt.is_some env
  let bind env name x f = let set, get = new_local env ("mmap_" ^ name) in x ^^ set ^^ f get
  (* K/V do not affect node or entry layout. Shared helpers only specialize
     scalar comparison; result-option injection happens at each call site. *)
  let helper env name arity results f =
    Func.share_code Func.Always env ("mmap_" ^ name)
      (List.init arity (fun i -> "a" ^ string_of_int i, I64Type))
      (List.init results (fun _ -> I64Type)) f
  let invoke xs f = G.concat xs ^^ f
  let invalid env = E.trap_with env "mutable-map: malformed tree"
  let depth_check env d = d ^^ num 64 ^^ lt ^^ E.else_trap_with env "mutable-map: malformed tree"
  let field env typ obj name = obj ^^ Object.load env typ name
  let store env typ obj name value_type value = Object.set env typ name value_type obj value
  let count env nt node = field env nt node "count" ^^ TaggedSmallWord.lsb_adjust T.Nat32
  let set_count env nt node value = store env nt node "count" T.nat32
    (value ^^ TaggedSmallWord.msb_adjust T.Nat32 ^^ TaggedSmallWord.tag env T.Nat32)
  let entries env nt node = field env nt node "entries"
  let children env nt node = field env nt node "children"
  let leaf env nt node = children env nt node ^^ Arr.len env ^^ num 0 ^^ eq
  let item env nt node index = entries env nt node ^^ index ^^ Arr.get env
  let child env nt node index = children env nt node ^^ index ^^ Arr.get env
  let set_item env nt et node index value =
    Arr.set env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt node) index value
  let set_child env nt node index value =
    Arr.set env (T.Array (T.Mut (T.Opt nt))) (T.Opt nt) (children env nt node) index value
  let key env entry = entry ^^ Tuple.load_n env 0L
  let value env entry = entry ^^ Tuple.load_n env 1L
  let nonnull env x = bind env "nonnull" x (fun x ->
    present env x ^^ E.else_trap_with env "mutable-map: malformed tree" ^^ x)
  let checked_count env nt node = bind env "count" (count env nt node) (fun n ->
    n ^^ num 31 ^^ gt ^^ E.if0 (invalid env) G.nop ^^ n)
  let node env nt et is_leaf =
    Object.lit env nt [
      "count", T.nat32, (fun () -> num 0 ^^ TaggedSmallWord.tag env T.Nat32);
      "entries", T.Array (T.Mut (T.Opt et)),
        (fun () -> Arr.tabulate_mut env (num 31) (fun _ -> null env));
      "children", T.Array (T.Mut (T.Opt nt)),
        (fun () -> Arr.tabulate_mut env (is_leaf ^^ ifv (num 0) (num 32)) (fun _ -> null env));
    ]
  let loop_up env name first limit body =
    let set, get = new_local env ("mmap_" ^ name) in
    first ^^ set ^^ G.loop0 (G.with_current_depth (fun loop ->
      get ^^ limit ^^ lt ^^ E.if0 (body get ^^ get ^^ num 1 ^^ add ^^ set ^^ G.branch_to_ loop) G.nop))
  let shift_right env arr_type _value_type arr first finish =
    bind env "shift_array" arr (fun arr ->
      finish ^^ first ^^ gt ^^ E.if0
        (Arr.move_within env arr_type arr first (first ^^ num 1 ^^ add)
          (finish ^^ first ^^ sub)) G.nop)
  let shift_left env arr_type value_type arr first finish =
    bind env "shift_array" arr (fun arr ->
      finish ^^ first ^^ gt ^^ E.if0
        (Arr.move_within env arr_type arr (first ^^ num 1 ^^ add) first
          (finish ^^ first ^^ sub)) G.nop ^^
      Arr.set env arr_type value_type arr finish (null env))
  let ordering_name = function
    | Dynamic -> "callback"
    | Scalar prim -> "static_" ^ T.string_of_typ (T.Prim prim)
  let compare env ordering kt comparator a b = match ordering with
    | Scalar ((T.Nat | T.Int) as prim) ->
      bind env "compare_a" a (fun a ->
      bind env "compare_b" b (fun b ->
        a ^^ b ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.Or)) ^^
        BitTagged.if_tagged_scalar env [I64Type]
          (* Compact Nat/Int share the same tag and signed representation.
             Boxed operands retain the existing arbitrary-precision path. *)
          (a ^^ b ^^ compile_comparison I64Op.LtS ^^
           ifv (num (-1)) (a ^^ b ^^ eq ^^ ifv (num 0) (num 1)))
          (a ^^ b ^^ Compare.scalar env prim)))
    | Scalar prim -> a ^^ b ^^ Compare.scalar env prim
    | Dynamic ->
      bind env "order_tag"
        (Call.local env (Schema.compare kt) comparator [a; b] ^^ Variant.get_variant_tag env)
        (fun tag ->
          tag ^^ compile_eq_const (Variant.hash_variant_label env "less") ^^ ifv (num (-1))
            (tag ^^ compile_eq_const (Variant.hash_variant_label env "equal") ^^ ifv (num 0) (num 1)))
  (* Return the insertion position and whether an equivalent key was found. *)
  let locate env ordering kt nt node comparator needle =
    invoke [node; comparator; needle]
      (helper env ("locate_" ^ ordering_name ordering) 3 2 (fun env args ->
        let node = List.nth args 0 and comparator = List.nth args 1 and needle = List.nth args 2 in
        let set_lo, lo = new_local env "mmap_lo" and set_hi, hi = new_local env "mmap_hi" in
        let set_found, found = new_local env "mmap_found" in
        let search load_at =
          G.loop0 (G.with_current_depth (fun loop ->
            lo ^^ hi ^^ lt ^^ E.if0
              (bind env "mid" (lo ^^ hi ^^ add ^^ half) (fun mid ->
               bind env "order" (compare env ordering kt comparator needle
                 (key env (nonnull env (load_at mid)))) (fun order ->
                 order ^^ num 0 ^^ eq ^^ E.if0
                   (mid ^^ set_lo ^^ num 1 ^^ set_found)
                   (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ E.if0
                      (mid ^^ set_hi) (mid ^^ num 1 ^^ add ^^ set_lo) ^^
                    G.branch_to_ loop)))) G.nop))
        in
        bind env "search_entries" (entries env nt node) (fun slots ->
          num 0 ^^ set_lo ^^ checked_count env nt node ^^ set_hi ^^
          num 0 ^^ set_found ^^
          (match ordering with
          | Scalar (T.Nat | T.Int) ->
            (* Binary-search midpoints remain below the initial count. Only
               native scalar comparison runs while the prefix is borrowed;
               BigNum boxing may allocate but introduces no GC safepoint. *)
            let _, fields = T.as_obj (T.normalize nt) in
            let array_type = T.lookup_val_field "entries" fields in
            hi ^^ num 0 ^^ gt ^^ E.if0
              (Arr.with_prefix env array_type slots hi search) G.nop
          | _ -> search (fun index -> slots ^^ index ^^ Arr.get env)) ^^
          lo ^^ found)))
  let split env nt et parent index =
    invoke [parent; index] (helper env "split" 2 0 (fun env args ->
      let parent = List.nth args 0 and index = List.nth args 1 in
      bind env "left" (nonnull env (child env nt parent index)) (fun left ->
      bind env "right" (node env nt et (leaf env nt left)) (fun right ->
      bind env "median" (nonnull env (item env nt left (num 15))) (fun median ->
      bind env "parent_count" (checked_count env nt parent) (fun n ->
        loop_up env "split_entries" (num 0) (num 15) (fun i ->
          set_item env nt et right i (item env nt left (i ^^ num 16 ^^ add)) ^^
          set_item env nt et left (i ^^ num 16 ^^ add) (null env)) ^^
        set_item env nt et left (num 15) (null env) ^^
        leaf env nt left ^^ E.if0 G.nop
          (loop_up env "split_children" (num 0) (num 16) (fun i ->
             set_child env nt right i (child env nt left (i ^^ num 16 ^^ add)) ^^
             set_child env nt left (i ^^ num 16 ^^ add) (null env))) ^^
        shift_right env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt parent) index n ^^
        shift_right env (T.Array (T.Mut (T.Opt nt))) (T.Opt nt) (children env nt parent)
          (index ^^ num 1 ^^ add) (n ^^ num 1 ^^ add) ^^
        set_item env nt et parent index median ^^
        set_child env nt parent (index ^^ num 1 ^^ add) right ^^
        set_count env nt left (num 15) ^^ set_count env nt right (num 15) ^^
        set_count env nt parent (n ^^ num 1 ^^ add)))))))
  let search env ordering kt nt root comparator needle =
    invoke [root; comparator; needle]
      (helper env ("search_" ^ ordering_name ordering) 3 2 (fun env args ->
        let set_node, node = new_local env "mmap_search_node" in
        let set_index, index = new_local env "mmap_search_index" in
        let set_found, found = new_local env "mmap_search_found" in
        let set_depth, depth = new_local env "mmap_search_depth" in
        let comparator = List.nth args 1 and needle = List.nth args 2 in
        List.nth args 0 ^^ set_node ^^ num 0 ^^ set_index ^^ num 0 ^^ set_depth ^^
        G.loop0 (G.with_current_depth (fun loop ->
          present env node ^^ E.if0
            (depth_check env depth ^^
             locate env ordering kt nt node comparator needle ^^ set_found ^^ set_index ^^
             found ^^ E.if0 G.nop
               (leaf env nt node ^^ ifv (null env) (child env nt node index) ^^ set_node ^^
                depth ^^ num 1 ^^ add ^^ set_depth ^^ G.branch_to_ loop)) G.nop)) ^^
        node ^^ index))
  let insert env ordering kt nt et mt map comparator needle payload =
    invoke [map; comparator; needle; payload]
      (helper env ("insert_" ^ ordering_name ordering) 4 1 (fun env args ->
        let map = List.nth args 0 and comparator = List.nth args 1
        and needle = List.nth args 2 and payload = List.nth args 3 in
        let set_node, current = new_local env "mmap_insert_node" in
        let set_index, index = new_local env "mmap_insert_index" in
        let set_found, found = new_local env "mmap_insert_found" in
        let set_old, old = new_local env "mmap_insert_old" in
        let set_depth, depth = new_local env "mmap_insert_depth" in
        field env mt map "root" ^^ set_node ^^ null env ^^ set_old ^^ num 0 ^^ set_depth ^^
        present env current ^^ E.if0 G.nop
          (node env nt et (num 1) ^^ set_node ^^ store env mt map "root" (T.Opt nt) current) ^^
        checked_count env nt current ^^ num 31 ^^ eq ^^ E.if0
          (bind env "new_root" (node env nt et (num 0)) (fun new_root ->
            set_child env nt new_root (num 0) current ^^ split env nt et new_root (num 0) ^^
            store env mt map "root" (T.Opt nt) new_root ^^ new_root ^^ set_node)) G.nop ^^
        G.loop0 (G.with_current_depth (fun loop ->
          depth_check env depth ^^
          locate env ordering kt nt current comparator needle ^^ set_found ^^ set_index ^^
          found ^^ E.if0
            (item env nt current index ^^ set_old ^^
             set_item env nt et current index (needle ^^ payload ^^ Tuple.from_stack env 2))
            (leaf env nt current ^^ E.if0
              (bind env "n" (checked_count env nt current) (fun n ->
                shift_right env (T.Array (T.Mut (T.Opt et))) (T.Opt et)
                  (entries env nt current) index n ^^
                set_item env nt et current index (needle ^^ payload ^^ Tuple.from_stack env 2) ^^
                set_count env nt current (n ^^ num 1 ^^ add) ^^
                store env mt map "size" T.nat
                  (field env mt map "size" ^^ num 1 ^^ BigNum.from_word64 env ^^ BigNum.compile_add env)))
              (bind env "next" (nonnull env (child env nt current index)) (fun next ->
                checked_count env nt next ^^ num 31 ^^ eq ^^ E.if0
                  (split env nt et current index ^^
                   bind env "order" (compare env ordering kt comparator needle
                     (key env (nonnull env (item env nt current index)))) (fun order ->
                     order ^^ num 0 ^^ eq ^^ E.if0
                       (num 1 ^^ set_found)
                       (order ^^ num 0 ^^ compile_comparison I64Op.GtS ^^ E.if0
                         (index ^^ num 1 ^^ add ^^ set_index) G.nop))) G.nop ^^
                found ^^ E.if0
                  (item env nt current index ^^ set_old ^^
                   set_item env nt et current index (needle ^^ payload ^^ Tuple.from_stack env 2))
                  (nonnull env (child env nt current index) ^^ set_node ^^
                   depth ^^ num 1 ^^ add ^^ set_depth ^^ G.branch_to_ loop)))))) ^^ old))
  (* Merge separator[index] and the right sibling into the left sibling. *)
  let merge env nt et parent index =
    invoke [parent; index] (helper env "merge" 2 1 (fun env args ->
      let parent = List.nth args 0 and index = List.nth args 1 in
      bind env "left" (nonnull env (child env nt parent index)) (fun left ->
      bind env "right" (nonnull env (child env nt parent (index ^^ num 1 ^^ add))) (fun right ->
      bind env "nl" (checked_count env nt left) (fun nl ->
      bind env "nr" (checked_count env nt right) (fun nr ->
      bind env "np" (checked_count env nt parent) (fun np ->
        nl ^^ nr ^^ add ^^ num 1 ^^ add ^^ num 31 ^^ gt ^^ E.if0 (invalid env) G.nop ^^
        set_item env nt et left nl (item env nt parent index) ^^
        loop_up env "merge_entries" (num 0) nr (fun i ->
          set_item env nt et left (nl ^^ num 1 ^^ add ^^ i ^^ add) (item env nt right i) ^^
          set_item env nt et right i (null env)) ^^
        leaf env nt left ^^ E.if0 G.nop
          (loop_up env "merge_children" (num 0) (nr ^^ num 1 ^^ add) (fun i ->
             set_child env nt left (nl ^^ num 1 ^^ add ^^ i ^^ add) (child env nt right i) ^^
             set_child env nt right i (null env))) ^^
        shift_left env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt parent)
          index (np ^^ num 1 ^^ sub) ^^
        shift_left env (T.Array (T.Mut (T.Opt nt))) (T.Opt nt) (children env nt parent)
          (index ^^ num 1 ^^ add) np ^^
        set_count env nt left (nl ^^ nr ^^ add ^^ num 1 ^^ add) ^^
        set_count env nt right (num 0) ^^ set_count env nt parent (np ^^ num 1 ^^ sub) ^^ left)))))))
  let borrow_left env nt et parent index =
    invoke [parent; index] (helper env "borrow_left" 2 0 (fun env args ->
      let parent = List.nth args 0 and index = List.nth args 1 in
      bind env "target" (nonnull env (child env nt parent index)) (fun target ->
      bind env "sibling" (nonnull env (child env nt parent (index ^^ num 1 ^^ sub))) (fun sibling ->
      bind env "n" (checked_count env nt target) (fun n ->
      bind env "s" (checked_count env nt sibling) (fun s ->
        shift_right env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt target) (num 0) n ^^
        set_item env nt et target (num 0) (item env nt parent (index ^^ num 1 ^^ sub)) ^^
        set_item env nt et parent (index ^^ num 1 ^^ sub) (item env nt sibling (s ^^ num 1 ^^ sub)) ^^
        set_item env nt et sibling (s ^^ num 1 ^^ sub) (null env) ^^
        leaf env nt target ^^ E.if0 G.nop
          (shift_right env (T.Array (T.Mut (T.Opt nt))) (T.Opt nt) (children env nt target)
             (num 0) (n ^^ num 1 ^^ add) ^^
           set_child env nt target (num 0) (child env nt sibling s) ^^
           set_child env nt sibling s (null env)) ^^
        set_count env nt target (n ^^ num 1 ^^ add) ^^ set_count env nt sibling (s ^^ num 1 ^^ sub)))))))
  let borrow_right env nt et parent index =
    invoke [parent; index] (helper env "borrow_right" 2 0 (fun env args ->
      let parent = List.nth args 0 and index = List.nth args 1 in
      bind env "target" (nonnull env (child env nt parent index)) (fun target ->
      bind env "sibling" (nonnull env (child env nt parent (index ^^ num 1 ^^ add))) (fun sibling ->
      bind env "n" (checked_count env nt target) (fun n ->
      bind env "s" (checked_count env nt sibling) (fun s ->
        set_item env nt et target n (item env nt parent index) ^^
        set_item env nt et parent index (item env nt sibling (num 0)) ^^
        shift_left env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt sibling)
          (num 0) (s ^^ num 1 ^^ sub) ^^
        leaf env nt target ^^ E.if0 G.nop
          (set_child env nt target (n ^^ num 1 ^^ add) (child env nt sibling (num 0)) ^^
           shift_left env (T.Array (T.Mut (T.Opt nt))) (T.Opt nt) (children env nt sibling) (num 0) s) ^^
        set_count env nt target (n ^^ num 1 ^^ add) ^^ set_count env nt sibling (s ^^ num 1 ^^ sub)))))))
  let collapse env nt mt map =
    bind env "root" (field env mt map "root") (fun root ->
      present env root ^^ E.if0
        (count env nt root ^^ num 0 ^^ eq ^^ E.if0
           (store env mt map "root" (T.Opt nt)
             (leaf env nt root ^^ ifv (null env) (nonnull env (child env nt root (num 0))))) G.nop) G.nop)
  let extreme env nt root right =
    invoke [root] (helper env (if right then "maximum" else "minimum") 1 1 (fun env args ->
      let set_node, current = new_local env "mmap_extreme_node" in
      let set_depth, depth = new_local env "mmap_extreme_depth" in
      List.hd args ^^ set_node ^^ num 0 ^^ set_depth ^^
      G.loop0 (G.with_current_depth (fun loop ->
        depth_check env depth ^^ leaf env nt current ^^ E.if0 G.nop
          (nonnull env (child env nt current (if right then checked_count env nt current else num 0)) ^^ set_node ^^
           depth ^^ num 1 ^^ add ^^ set_depth ^^ G.branch_to_ loop))) ^^
      nonnull env (item env nt current (if right then checked_count env nt current ^^ num 1 ^^ sub else num 0))))
  (* Public extrema preserve the ordinary Map traversal contract: nullable
     child links end the search, and the depth limit is 128 rather than the
     stricter internal mutation guard. Return the stored entry unchanged. *)
  let public_extreme env nt mt map reverse =
    invoke [map] (helper env (if reverse then "max_entry" else "min_entry")
      1 1 (fun env args ->
        let set_node, current = new_local env "mmap_extreme_entry_node" in
        let set_depth, depth = new_local env "mmap_extreme_entry_depth" in
        let set_result, result = new_local env "mmap_extreme_entry_result" in
        field env mt (List.hd args) "root" ^^ set_node ^^
        num 0 ^^ set_depth ^^ null env ^^ set_result ^^
        G.loop0 (G.with_current_depth (fun loop ->
          depth ^^ num 128 ^^ gt ^^ E.if0 (invalid env) G.nop ^^
          present env current ^^ E.if0
            (bind env "extreme_entry_count" (count env nt current) (fun n ->
              n ^^ num 0 ^^ eq ^^ E.if0 (invalid env) G.nop ^^
              leaf env nt current ^^ E.if0
                (nonnull env (item env nt current
                   (if reverse then n ^^ num 1 ^^ sub else num 0)) ^^
                 set_result)
                (child env nt current (if reverse then n else num 0) ^^
                 set_node ^^ depth ^^ num 1 ^^ add ^^ set_depth ^^
                 G.branch_to_ loop))) G.nop)) ^^ result))
  (* Before descending, grow a minimal child by borrowing or merging, so its
     subsequent removal cannot underflow. Collapse an empty root before any
     comparator can reenter a read of this map. *)
  let rec delete env ordering kt nt et mt map current comparator needle depth =
    invoke [map; current; comparator; needle; depth]
      (helper env ("delete_" ^ ordering_name ordering) 5 1 (fun env args ->
        let map = List.nth args 0 and current = List.nth args 1
        and comparator = List.nth args 2 and needle = List.nth args 3 and depth = List.nth args 4 in
        let set_index, index = new_local env "mmap_delete_index" in
        let set_found, found = new_local env "mmap_delete_found" in
        let set_next, next = new_local env "mmap_delete_next" in
        depth_check env depth ^^
        locate env ordering kt nt current comparator needle ^^ set_found ^^ set_index ^^
        found ^^ ifv
          (bind env "old" (nonnull env (item env nt current index)) (fun old ->
            leaf env nt current ^^ E.if0
              (bind env "n" (checked_count env nt current) (fun n ->
                shift_left env (T.Array (T.Mut (T.Opt et))) (T.Opt et) (entries env nt current)
                  index (n ^^ num 1 ^^ sub) ^^
                set_count env nt current (n ^^ num 1 ^^ sub)))
              (bind env "left" (nonnull env (child env nt current index)) (fun left ->
               bind env "right" (nonnull env (child env nt current (index ^^ num 1 ^^ add))) (fun right ->
                 checked_count env nt left ^^ num 15 ^^ gt ^^ E.if0
                   (bind env "replacement" (extreme env nt left true) (fun replacement ->
                     delete env ordering kt nt et mt map left comparator (key env replacement) (depth ^^ num 1 ^^ add) ^^
                     G.i Drop ^^ set_item env nt et current index replacement))
                   (checked_count env nt right ^^ num 15 ^^ gt ^^ E.if0
                     (bind env "replacement" (extreme env nt right false) (fun replacement ->
                       delete env ordering kt nt et mt map right comparator (key env replacement) (depth ^^ num 1 ^^ add) ^^
                       G.i Drop ^^ set_item env nt et current index replacement))
                     (merge env nt et current index ^^ set_next ^^ collapse env nt mt map ^^
                      delete env ordering kt nt et mt map next comparator needle (depth ^^ num 1 ^^ add) ^^ G.i Drop))))) ^^ old))
          (leaf env nt current ^^ ifv (null env)
            (nonnull env (child env nt current index) ^^ set_next ^^
             checked_count env nt next ^^ num 15 ^^ eq ^^ E.if0
               (index ^^ num 0 ^^ gt ^^ ifv
                  (checked_count env nt (nonnull env (child env nt current (index ^^ num 1 ^^ sub))) ^^ num 15 ^^ gt)
                  (num 0) ^^ E.if0
                    (borrow_left env nt et current index)
                    (index ^^ checked_count env nt current ^^ lt ^^ ifv
                       (checked_count env nt (nonnull env (child env nt current (index ^^ num 1 ^^ add))) ^^ num 15 ^^ gt)
                       (num 0) ^^ E.if0
                         (borrow_right env nt et current index)
                         (index ^^ checked_count env nt current ^^ lt ^^ ifv index (index ^^ num 1 ^^ sub) ^^ set_index ^^
                          merge env nt et current index ^^ set_next ^^ collapse env nt mt map))) G.nop ^^
             delete env ordering kt nt et mt map next comparator needle (depth ^^ num 1 ^^ add)))))
  let compile_body operation source_ordering ordering env specialization arguments =
    let kt, vt = match specialization.C.type_arguments with
      | [k; v] -> k, v | _ -> invalid_arg "mutable-map: type arguments" in
    let nt = Schema.node kt vt and et = Schema.entry kt vt and mt = Schema.map kt vt in
    let map, comparator, needle, payload = match operation, source_ordering, arguments with
      | (Min_entry | Max_entry), _, [map] -> map, num 0, num 0, []
      | _, Callback, map :: comparator :: needle :: rest -> map, comparator, needle, rest
      | _, Static, map :: needle :: rest -> map, num 0, needle, rest
      | _ -> invalid_arg "mutable-map: arguments" in
    let payload = match payload with [v] -> v | _ -> null env in
    let old_result old = match operation with
      | Get_entry | Min_entry | Max_entry -> old
      | Get | Swap | Replace | Take -> present env old ^^ ifv (Opt.inject env vt (value env old)) (null env)
      | Contains | Delete -> present env old
      | Insert -> present env old ^^ num 0 ^^ eq
      | Add | Remove -> Tuple.compile_unit env
    in
    let code = match operation with
      | Min_entry | Max_entry -> public_extreme env nt mt map (operation = Max_entry)
      | Get | Get_entry | Contains | Replace ->
        let set_node, current = new_local env "mmap_result_node" in
        let set_index, index = new_local env "mmap_result_index" in
        search env ordering kt nt (field env mt map "root") comparator needle ^^ set_index ^^ set_node ^^
        bind env "old" (present env current ^^ ifv (item env nt current index) (null env)) (fun old ->
          (if operation = Replace then present env current ^^ E.if0
             (set_item env nt et current index (needle ^^ payload ^^ Tuple.from_stack env 2)) G.nop else G.nop) ^^
          old_result old)
      | Add | Insert | Swap -> bind env "old" (insert env ordering kt nt et mt map comparator needle payload) old_result
      | Remove | Delete | Take ->
        bind env "root" (field env mt map "root") (fun root ->
        bind env "old" (present env root ^^ ifv
          (delete env ordering kt nt et mt map root comparator needle (num 0)) (null env)) (fun old ->
          collapse env nt mt map ^^
          present env old ^^ E.if0
            (* Every realizable tree has fewer than 2^64 entries. The checked
               bridge rejects oversized forged metadata and avoids boxed
               bignum addition with a negative operand on ordinary deletes. *)
            (bind env "size" (field env mt map "size" ^^ BigNum.to_word64 env) (fun size ->
              size ^^ num 0 ^^ eq ^^ E.if0 (invalid env) G.nop ^^
              store env mt map "size" T.nat
                (size ^^ num 1 ^^ sub ^^ BigNum.from_word64 env))) G.nop ^^
          old_result old))
    in code

  let compile operation source_ordering env specialization arguments =
    let comparison = match source_ordering, specialization.C.type_arguments with
      | Callback, _ -> Dynamic
      | Static, key :: _ -> (match T.promote key with
          | T.Prim prim -> Scalar prim
          | _ -> invalid_arg "unsupported static key type")
      | Static, [] -> invalid_arg "missing key type"
    in
    let representation = P.Managed in
    let code = if operation = Min_entry || operation = Max_entry then
      compile_body operation source_ordering comparison env specialization arguments
    else match source_ordering with
      | Callback ->
        Compare.dispatch env ~comparator_index:1 arguments [I64Type]
          (fun child_env primitive arguments ->
            let comparison = match primitive with None -> Dynamic | Some prim -> Scalar prim in
            compile_body operation source_ordering comparison child_env specialization arguments)
      | Static -> compile_body operation source_ordering comparison env specialization arguments
    in P.{code; representation}
end
