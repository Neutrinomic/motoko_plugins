module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module C = Mo_values.Compute_plugin
open Wasm_exts.Ast
open Wasm_exts.Types
open Schema
let ( ^^ ) = G.( ^^ )

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
  let ifv yes no = E.if1 I64Type yes no
  let field env node index = node ^^ Tuple.load_n env (Int64.of_int index)
  let left env node = field env node 4
  let right env node = field env node 5
  let key env node = field env node 2
  let value env node = field env node 3
  let present env node = node ^^ Opt.is_some env
  let null env = Opt.null_lit env
  let bind env name expression body =
    let set, get = new_local env ("pmap_" ^ name) in
    expression ^^ set ^^ body get
  let invalid env = E.trap_with env "pure map: invalid tree metadata or depth"
  let check_depth env depth = depth ^^ num 128 ^^ lt ^^ E.else_trap_with env "pure map: invalid tree metadata or depth"
  let helper env name arity results body =
    Func.share_code Func.Always env ("pmap_" ^ name)
      (List.init arity (fun i -> "arg" ^ string_of_int i, I64Type))
      (List.init results (fun _ -> I64Type)) body
  let invoke args code = G.concat args ^^ code

  let height env tree =
    present env tree ^^ ifv
      (bind env "height" (field env tree 0 ^^ TaggedSmallWord.lsb_adjust T.Nat32)
        (fun h -> h ^^ num 1 ^^ lt ^^ E.if0 (invalid env) G.nop ^^
          h ^^ num 128 ^^ gt ^^ E.if0 (invalid env) G.nop ^^ h))
      (num 0)
  let count env tree =
    present env tree ^^ ifv
      (bind env "count" (field env tree 1 ^^ BigNum.to_word64 env)
        (fun n -> n ^^ num 0 ^^ compile_comparison I64Op.LeS ^^
          E.if0 (invalid env) G.nop ^^ n))
      (num 0)
  let node env l k v r =
    invoke [l; k; v; r] (helper env "node" 4 1 (fun env args ->
      let l = List.nth args 0 and k = List.nth args 1
      and v = List.nth args 2 and r = List.nth args 3 in
      bind env "left_height" (height env l) (fun hl ->
      bind env "right_height" (height env r) (fun hr ->
      bind env "next_height" (hl ^^ hr ^^ gt ^^ ifv hl hr ^^ num 1 ^^ add) (fun h ->
      bind env "next_count" (count env l ^^ count env r ^^ add ^^ num 1 ^^ add) (fun n ->
        h ^^ num 128 ^^ gt ^^ E.if0 (invalid env) G.nop ^^
        n ^^ num 0 ^^ compile_comparison I64Op.LeS ^^ E.if0 (invalid env) G.nop ^^
        h ^^ TaggedSmallWord.msb_adjust T.Nat32 ^^ TaggedSmallWord.tag env T.Nat32 ^^
        n ^^ BigNum.from_word64 env ^^ k ^^ v ^^ l ^^ r ^^ Tuple.from_stack env 6))))))
  (* Replacing a binding preserves the complete shape. Copy only the changed
     references and reuse metadata, without re-reading sibling subtrees. *)
  let copy env old k v l r =
    field env old 0 ^^ field env old 1 ^^ k ^^ v ^^ l ^^ r ^^
    Tuple.from_stack env 6
  let balance env l k v r =
    invoke [l; k; v; r] (helper env "balance" 4 1 (fun env args ->
      let l = List.nth args 0 and k = List.nth args 1
      and v = List.nth args 2 and r = List.nth args 3 in
      bind env "left_height" (height env l) (fun hl ->
      bind env "right_height" (height env r) (fun hr ->
      hl ^^ hr ^^ num 1 ^^ add ^^ gt ^^ ifv
        (bind env "ll" (left env l) (fun ll ->
         bind env "lr" (right env l) (fun lr ->
         height env ll ^^ height env lr ^^ compile_comparison I64Op.GeU ^^ ifv
           (node env ll (key env l) (value env l) (node env lr k v r))
           (bind env "middle" lr (fun m ->
             node env (node env ll (key env l) (value env l) (left env m))
               (key env m) (value env m) (node env (right env m) k v r))))))
        (hr ^^ hl ^^ num 1 ^^ add ^^ gt ^^ ifv
          (bind env "rl" (left env r) (fun rl ->
           bind env "rr" (right env r) (fun rr ->
           height env rr ^^ height env rl ^^ compile_comparison I64Op.GeU ^^ ifv
             (node env (node env l k v rl) (key env r) (value env r) rr)
             (bind env "middle" rl (fun m ->
               node env (node env l k v (left env m)) (key env m) (value env m)
                 (node env (right env m) (key env r) (value env r) rr))))))
          (node env l k v r))))))
  let rec join env l k v r d =
    invoke [l; k; v; r; d] (helper env "join" 5 1 (fun env args ->
      let l = List.nth args 0 and k = List.nth args 1
      and v = List.nth args 2 and r = List.nth args 3
      and d = List.nth args 4 in
      check_depth env d ^^
      bind env "left_height" (height env l) (fun hl ->
      bind env "right_height" (height env r) (fun hr ->
      hl ^^ hr ^^ num 1 ^^ add ^^ gt ^^ ifv
        (balance env (left env l) (key env l) (value env l)
          (join env (right env l) k v r (d ^^ num 1 ^^ add)))
        (hr ^^ hl ^^ num 1 ^^ add ^^ gt ^^ ifv
          (balance env (join env l k v (left env r) (d ^^ num 1 ^^ add))
            (key env r) (value env r) (right env r))
          (node env l k v r))))))
  let rec pop_min env tree d =
    invoke [tree; d] (helper env "pop_min" 2 2 (fun env args ->
      let tree = List.nth args 0 and d = List.nth args 1 in
      let set_next, next = new_local env "pmap_next" in
      let set_old, old = new_local env "pmap_old" in
      check_depth env d ^^
      present env tree ^^ E.else_trap_with env "pure map: invalid tree metadata or depth" ^^
      present env (left env tree) ^^ E.if0
        (pop_min env (left env tree) (d ^^ num 1 ^^ add) ^^ set_old ^^ set_next ^^
          balance env next (key env tree) (value env tree) (right env tree) ^^ set_next)
        (right env tree ^^ set_next ^^ tree ^^ set_old) ^^
      next ^^ old))
  let concat env l r =
    invoke [l; r] (helper env "concat" 2 1 (fun env args ->
      let l = List.nth args 0 and r = List.nth args 1 in
      present env l ^^ ifv
        (present env r ^^ ifv
          (let set_next, next = new_local env "pmap_next" in
           let set_old, old = new_local env "pmap_old" in
           pop_min env r (num 0) ^^ set_old ^^ set_next ^^
           join env l (key env old) (value env old) next (num 0))
          l)
        r))

  let ordering_name = function
    | Dynamic -> "callback"
    | Scalar prim -> "static_" ^ T.string_of_typ (T.Prim prim)
  let compare env ordering kt comparator a b = match ordering with
    | Scalar prim -> a ^^ b ^^ Compare.scalar env prim
    | Dynamic ->
      bind env "order_tag"
        (Call.local env (Schema.compare kt) comparator [a; b] ^^ Variant.get_variant_tag env)
        (fun tag ->
          tag ^^ compile_eq_const (Variant.hash_variant_label env "less") ^^ ifv (num (-1))
            (tag ^^ compile_eq_const (Variant.hash_variant_label env "equal") ^^ ifv (num 0) (num 1)))
  let search env ordering kt initial comparator needle =
    invoke [initial; comparator; needle]
      (helper env ("search_" ^ ordering_name ordering) 3 1 (fun env args ->
        let comparator = List.nth args 1 and needle = List.nth args 2 in
        let set_tree, tree = new_local env "pmap_search_tree" in
        let set_depth, depth = new_local env "pmap_search_depth" in
        List.nth args 0 ^^ set_tree ^^ num 0 ^^ set_depth ^^
        G.loop0 (G.with_current_depth (fun loop ->
          present env tree ^^ E.if0
            (bind env "comparison" (compare env ordering kt comparator needle (key env tree)) (fun order ->
              order ^^ num 0 ^^ eq ^^ E.if0 G.nop
                (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^
                  ifv (left env tree) (right env tree) ^^ set_tree ^^
                  depth ^^ num 1 ^^ add ^^ set_depth ^^
                  check_depth env depth ^^ G.branch_to_ loop)))
            G.nop)) ^^ tree))
  let optional_value env vt tree = present env tree ^^ ifv
    (Opt.inject env vt (value env tree)) (null env)
  let optional_entry env tree = present env tree ^^ ifv
    (key env tree ^^ value env tree ^^ Tuple.from_stack env 2) (null env)
  let option_class vt = T.(match promote vt with
    | Prim Null | Opt _ | Any | Con _ -> "nullable" | _ -> "plain")
  let rec update env operation ordering kt vt tree comparator needle payload d =
    let operation = match operation with Add -> Put | Remove -> Take | x -> x in
    let name = "update_" ^ Schema.name operation ^ "_" ^ ordering_name ordering ^ "_" ^ option_class vt in
    invoke [tree; comparator; needle; payload; d]
      (helper env name 5 3 (fun env args ->
        let tree = List.nth args 0 and comparator = List.nth args 1
        and needle = List.nth args 2 and payload = List.nth args 3
        and d = List.nth args 4 in
        let set_next, next = new_local env "pmap_next" in
        let set_old, old = new_local env "pmap_old" in
        let set_changed, changed = new_local env "pmap_changed" in
        let replace =
          let replacement = match operation with
            | Put ->
              present env tree ^^ E.if0
                (copy env tree needle payload (left env tree) (right env tree) ^^
                  set_next ^^ num 1 ^^ set_changed)
                (node env (null env) needle payload (null env) ^^
                  set_next ^^ num 2 ^^ set_changed)
            | Replace ->
              present env tree ^^ E.if0
                (copy env tree needle payload (left env tree) (right env tree) ^^
                  set_next ^^ num 1 ^^ set_changed)
                (tree ^^ set_next ^^ num 0 ^^ set_changed)
            | Take ->
              present env tree ^^ E.if0
                (concat env (left env tree) (right env tree) ^^ set_next ^^ num 2 ^^ set_changed)
                (tree ^^ set_next ^^ num 0 ^^ set_changed)
            | Alter ->
              bind env "replacement"
                (Call.local env (Schema.alteration vt) payload [optional_value env vt tree])
                (fun replacement ->
                  present env replacement ^^ E.if0
                    (present env tree ^^ E.if0
                      (copy env tree needle (replacement ^^ Opt.project env vt)
                        (left env tree) (right env tree) ^^
                        set_next ^^ num 1 ^^ set_changed)
                      (node env (null env) needle (replacement ^^ Opt.project env vt) (null env) ^^
                        set_next ^^ num 2 ^^ set_changed))
                    (present env tree ^^ E.if0
                      (concat env (left env tree) (right env tree) ^^ set_next ^^ num 2 ^^ set_changed)
                      (tree ^^ set_next ^^ num 0 ^^ set_changed)))
            | _ -> invalid_arg "pure map: invalid update operation"
          in tree ^^ set_old ^^ replacement
        in
        check_depth env d ^^
        present env tree ^^ E.if0
          (bind env "comparison" (compare env ordering kt comparator needle (key env tree)) (fun order ->
            order ^^ num 0 ^^ eq ^^ E.if0 replace
              (update env operation ordering kt vt
                (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^
                  ifv (left env tree) (right env tree)) comparator needle payload (d ^^ num 1 ^^ add) ^^
                set_changed ^^ set_old ^^ set_next ^^
                changed ^^ E.if0
                  (changed ^^ num 1 ^^ eq ^^ ifv
                    (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ ifv
                      (copy env tree (key env tree) (value env tree) next (right env tree))
                      (copy env tree (key env tree) (value env tree) (left env tree) next))
                    (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ ifv
                      (balance env next (key env tree) (value env tree) (right env tree))
                      (balance env (left env tree) (key env tree) (value env tree) next)) ^^ set_next)
                  (tree ^^ set_next))))
          replace ^^
        next ^^ old ^^ changed))

  let rec split env ordering kt tree comparator needle d =
    invoke [tree; comparator; needle; d]
      (helper env ("split_" ^ ordering_name ordering) 4 3 (fun env args ->
        let tree = List.nth args 0 and comparator = List.nth args 1
        and needle = List.nth args 2 and d = List.nth args 3 in
        let set_l, l = new_local env "pmap_split_left" in
        let set_old, old = new_local env "pmap_split_old" in
        let set_r, r = new_local env "pmap_split_right" in
        check_depth env d ^^
        present env tree ^^ E.if0
          (bind env "comparison" (compare env ordering kt comparator needle (key env tree)) (fun order ->
            order ^^ num 0 ^^ eq ^^ E.if0
              (left env tree ^^ set_l ^^ tree ^^ set_old ^^ right env tree ^^ set_r)
              (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ E.if0
                (split env ordering kt (left env tree) comparator needle (d ^^ num 1 ^^ add) ^^
                  set_r ^^ set_old ^^ set_l ^^
                  join env r (key env tree) (value env tree) (right env tree) (num 0) ^^ set_r)
                (split env ordering kt (right env tree) comparator needle (d ^^ num 1 ^^ add) ^^
                  set_r ^^ set_old ^^ set_l ^^
                  join env (left env tree) (key env tree) (value env tree) l (num 0) ^^ set_l))))
          (null env ^^ set_l ^^ null env ^^ set_old ^^ null env ^^ set_r) ^^
        l ^^ old ^^ r))
  let rec rank env ordering kt tree comparator needle index d =
    invoke [tree; comparator; needle; index; d]
      (helper env ("rank_" ^ ordering_name ordering) 5 2 (fun env args ->
        let tree = List.nth args 0 and comparator = List.nth args 1
        and needle = List.nth args 2 and index = List.nth args 3
        and d = List.nth args 4 in
        let set_index, result = new_local env "pmap_rank_result" in
        let set_found, found = new_local env "pmap_rank_found" in
        check_depth env d ^^
        index ^^ num 0 ^^ compile_comparison I64Op.LtS ^^
        E.if0 (invalid env) G.nop ^^
        present env tree ^^ E.if0
          (bind env "comparison" (compare env ordering kt comparator needle (key env tree)) (fun order ->
            order ^^ num 0 ^^ eq ^^ E.if0
              (index ^^ count env (left env tree) ^^ add ^^ set_index ^^ num 1 ^^ set_found)
              (order ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ E.if0
                (rank env ordering kt (left env tree) comparator needle index (d ^^ num 1 ^^ add) ^^
                  set_found ^^ set_index)
                (rank env ordering kt (right env tree) comparator needle
                  (index ^^ count env (left env tree) ^^ add ^^ num 1 ^^ add) (d ^^ num 1 ^^ add) ^^
                  set_found ^^ set_index))))
          (index ^^ set_index ^^ num 0 ^^ set_found) ^^
        result ^^ num 0 ^^ compile_comparison I64Op.LtS ^^
        E.if0 (invalid env) G.nop ^^ result ^^ found))
  let rec select env tree index d =
    invoke [tree; index; d] (helper env "select" 3 1 (fun env args ->
      let tree = List.nth args 0 and index = List.nth args 1 and d = List.nth args 2 in
      check_depth env d ^^
      present env tree ^^ ifv
        (bind env "left_count" (count env (left env tree)) (fun count ->
          index ^^ count ^^ eq ^^ ifv tree
            (index ^^ count ^^ lt ^^ ifv
              (select env (left env tree) index (d ^^ num 1 ^^ add))
              (select env (right env tree) (index ^^ count ^^ sub ^^ num 1 ^^ sub) (d ^^ num 1 ^^ add)))))
        (null env)))
  let rec from_sorted env entries start length =
    invoke [entries; start; length] (helper env "from_sorted" 3 1 (fun env args ->
      let entries = List.nth args 0 and start = List.nth args 1 and length = List.nth args 2 in
      length ^^ num 0 ^^ eq ^^ ifv (null env)
        (bind env "half" (length ^^ half) (fun half ->
         bind env "middle" (start ^^ half ^^ add) (fun middle ->
         bind env "entry" (entries ^^ middle ^^ Arr.get env) (fun entry ->
           node env (from_sorted env entries start half)
             (field env entry 0) (field env entry 1)
             (from_sorted env entries (middle ^^ num 1 ^^ add)
               (length ^^ half ^^ sub ^^ num 1 ^^ sub))))))))

  let compile_body operation source_ordering ordering env specialization arguments =
    let kt, vt = match specialization.C.type_arguments with
      | [k; v] -> k, v | _ -> invalid_arg "pure map specialization" in
    let argument i = List.nth arguments i in
    let tree = match arguments with x :: _ -> x | [] -> null env in
    let comparator = if source_ordering = Callback then (match operation with
      | Join | Concat | Select | From_sorted -> null env | _ -> argument 1) else null env in
    let needle = if source_ordering = Callback then 2 else 1 in
    let code = match operation with
    | Get | Get_entry | Contains ->
      bind env "found" (search env ordering kt tree comparator (argument needle)) (fun found ->
        match operation with
        | Get -> optional_value env vt found
        | Contains -> present env found
        | _ -> optional_entry env found)
    | Add | Put | Replace | Remove | Take | Alter ->
      let payload = match operation with Remove | Take -> null env | _ -> argument (needle + 1) in
      let set_old, old = new_local env "pmap_old" in
      let set_next, next = new_local env "pmap_next" in
      update env operation ordering kt vt tree comparator (argument needle) payload (num 0) ^^
      G.i Drop ^^ set_old ^^ set_next ^^
      (match operation with
      | Add | Remove -> next
      | Replace -> next ^^ optional_value env vt old
      | _ -> next ^^ optional_entry env old)
    | Join -> join env (argument 0) (argument 1) (argument 2) (argument 3) (num 0)
    | Concat -> concat env (argument 0) (argument 1)
    | Split ->
      let set_r, r = new_local env "pmap_split_right" in
      let set_old, old = new_local env "pmap_split_old" in
      let set_l, l = new_local env "pmap_split_left" in
      split env ordering kt tree comparator (argument needle) (num 0) ^^
      set_r ^^ set_old ^^ set_l ^^ l ^^ optional_entry env old ^^ r
    | Rank ->
      let set_found, found = new_local env "pmap_rank_found" in
      rank env ordering kt tree comparator (argument needle) (num 0) (num 0) ^^
      set_found ^^ BigNum.from_word64 env ^^ found
    | Select ->
      argument 1 ^^ (count env tree ^^ BigNum.from_word64 env) ^^ Compare.scalar env T.Nat ^^
      num 0 ^^ compile_comparison I64Op.LtS ^^ ifv
        (bind env "found" (select env tree (argument 1 ^^ BigNum.to_word64 env) (num 0))
          (optional_entry env)) (null env)
    | From_sorted -> from_sorted env tree (num 0) (tree ^^ Arr.len env)
    in code

  let compile operation source_ordering env specialization arguments =
    let comparison = match source_ordering, specialization.C.type_arguments with
      | Callback, _ -> Dynamic
      | Static, key :: _ -> (match T.promote key with
          | T.Prim prim -> Scalar prim
          | _ -> invalid_arg "unsupported static key type")
      | Static, [] -> invalid_arg "missing key type"
    in
    let representation = match operation with
      | Put | Replace | Take | Alter | Rank -> P.Tuple 2
      | Split -> P.Tuple 3
      | _ -> P.Managed
    in
    let result_types = match representation with
      | P.Tuple count -> List.init count (fun _ -> I64Type)
      | _ -> [I64Type]
    in
    let code = match source_ordering, operation with
      | Callback, (Join | Concat | Select | From_sorted)
      | Static, _ -> compile_body operation source_ordering comparison env specialization arguments
      | Callback, _ ->
        Compare.dispatch env ~comparator_index:1 arguments result_types
          (fun child_env primitive arguments ->
            let comparison = match primitive with None -> Dynamic | Some prim -> Scalar prim in
            compile_body operation source_ordering comparison child_env specialization arguments)
    in P.{code; representation}
end
