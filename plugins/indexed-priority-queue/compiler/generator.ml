module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module C = Mo_values.Compute_plugin
open Wasm_exts.Ast
open Wasm_exts.Types
open Schema
let ( ^^ ) = G.( ^^ )

(* All containers use conservative physical storage types. Specializing K/V
   does not change their representation or eliminate managed write barriers. *)
module Make (B : P.Backend) = struct
  open B
  type ordering = Callback | Scalar of T.prim
  let qt = Schema.queue T.Any T.Any
  let et = Schema.entry T.Any T.Any
  let ht = Schema.handle T.Any T.Any
  let at = T.Array (T.Mut (T.Opt et))
  let num n = compile_unboxed_const (Int64.of_int n)
  let add = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let shr n = num n ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.ShrU))
  let eq = compile_comparison I64Op.Eq
  let lt = compile_comparison I64Op.LtU
  let gt = compile_comparison I64Op.GtU
  let le = compile_comparison I64Op.LeU
  let ifv = E.if1 I64Type
  let null env = Opt.null_lit env
  let present env x = x ^^ Opt.is_some env
  let bind env name code f = let set, get = new_local env ("ipq_" ^ name) in code ^^ set ^^ f get
  let field env typ obj label = obj ^^ Object.load env typ label
  let store env typ obj label typ' value = Object.set env typ label typ' obj value
  let slots env q = field env qt q "slots"
  let size env q = field env qt q "size" ^^ BigNum.to_word64 env
  let set_size env q n = store env qt q "size" T.nat (n ^^ BigNum.from_word64 env)
  let index env h = field env ht h "index" ^^ BigNum.to_word64 env
  let set_index env h i = store env ht h "index" T.nat (i ^^ BigNum.from_word64 env)
  let handle env e = field env et e "handle"
  let priority env e = field env et e "priority"
  let payload env e = field env et e "value"
  let item env arr i = arr ^^ i ^^ Arr.get env
  let set_item env arr i value = Arr.set env at (T.Opt et) arr i value
  let detach env h = store env ht h "owner" (T.Opt qt) (null env)
  let helper env name arity results body =
    Func.share_code Func.Always env ("ipq_" ^ name)
      (List.init arity (fun i -> "a" ^ string_of_int i, I64Type))
      (List.init results (fun _ -> I64Type)) body
  let invoke args code = G.concat args ^^ code
  let order_name = function Callback -> "callback" | Scalar prim -> "scalar_" ^ T.string_of_typ (T.Prim prim)
  let compare env ordering comparator a b = match ordering with
    | Scalar prim -> a ^^ b ^^ Compare.scalar env prim
    | Callback ->
      bind env "comparison_tag"
        (Call.local env (Schema.compare T.Any) comparator [a; b] ^^ Variant.get_variant_tag env)
        (fun tag ->
          tag ^^ compile_eq_const (Variant.hash_variant_label env "less") ^^ ifv (num (-1))
            (tag ^^ compile_eq_const (Variant.hash_variant_label env "equal") ^^ ifv (num 0) (num 1)))
  let less env ordering comparator a b = compare env ordering comparator a b ^^ num 0 ^^ compile_comparison I64Op.LtS
  let loop_up env name first limit body =
    let set, get = new_local env ("ipq_" ^ name) in
    first ^^ set ^^ G.loop0 (G.with_current_depth (fun loop ->
      get ^^ limit ^^ lt ^^ E.if0 (body get ^^ get ^^ num 1 ^^ add ^^ set ^^ G.branch_to_ loop) G.nop))
  let resize env q capacity =
    invoke [q; capacity] (helper env "resize" 2 0 (fun env args ->
      let q = List.nth args 0 and capacity = List.nth args 1 in
      bind env "old_slots" (slots env q) (fun old ->
      bind env "resize_size" (size env q) (fun n ->
        store env qt q "slots" at
          (Arr.tabulate_mut env capacity (fun i -> i ^^ n ^^ lt ^^ ifv (item env old i) (null env)))))))
  let shrink env q =
    bind env "shrink_size" (size env q) (fun n ->
    bind env "shrink_capacity" (slots env q ^^ Arr.len env) (fun capacity ->
      n ^^ num 0 ^^ eq ^^ E.if0
        (resize env q (num 0))
        (capacity ^^ num 8 ^^ gt ^^ E.if0
          (n ^^ capacity ^^ shr 2 ^^ le ^^ E.if0 (resize env q (capacity ^^ shr 1)) G.nop) G.nop)))
  let swap_entries env arr i j a b =
    set_item env arr i b ^^ set_item env arr j a ^^
    set_index env (handle env a) j ^^ set_index env (handle env b) i
  (* User callbacks may read handles, so their path keeps every swap complete.
     Proven scalar comparators have no callbacks: move one ancestor/child per
     step and write the moving entry only at its final position. *)
  let move_step env ordering arr pos next moving other = match ordering with
    | Callback -> swap_entries env arr pos next moving other
    | Scalar _ -> set_item env arr pos other ^^ set_index env (handle env other) pos
  let finish_move env ordering arr start pos moving = match ordering with
    | Callback -> G.nop
    | Scalar _ -> pos ^^ start ^^ eq ^^ E.if0 G.nop
        (set_item env arr pos moving ^^ set_index env (handle env moving) pos)
  let sift_up env ordering q comparator start =
    invoke [q; comparator; start]
      (helper env ("sift_up_" ^ order_name ordering) 3 0 (fun env args ->
        let q = List.nth args 0 and comparator = List.nth args 1 in
        let set, pos = new_local env "ipq_sift_up_index" in
        bind env "sift_up_slots" (slots env q) (fun arr ->
        bind env "sift_up_entry" (item env arr (List.nth args 2)) (fun moving ->
        bind env "sift_up_priority" (priority env moving) (fun moving_priority ->
          List.nth args 2 ^^ set ^^
          G.loop0 (G.with_current_depth (fun loop ->
            pos ^^ num 0 ^^ gt ^^ E.if0
              (bind env "parent" (pos ^^ num 1 ^^ sub ^^ shr 1) (fun parent ->
               bind env "parent_entry" (item env arr parent) (fun parent_entry ->
                less env ordering comparator moving_priority (priority env parent_entry) ^^
                E.if0 (move_step env ordering arr pos parent moving parent_entry ^^ parent ^^ set ^^ G.branch_to_ loop) G.nop))) G.nop)) ^^
          finish_move env ordering arr (List.nth args 2) pos moving)))))
  let sift_down env ordering q comparator start =
    invoke [q; comparator; start]
      (helper env ("sift_down_" ^ order_name ordering) 3 0 (fun env args ->
        let q = List.nth args 0 and comparator = List.nth args 1 in
        let set_pos, pos = new_local env "ipq_sift_down_index" in
        let set_child, child = new_local env "ipq_sift_down_child" in
        let set_entry, child_entry = new_local env "ipq_sift_down_child_entry" in
        bind env "sift_down_size" (size env q) (fun n ->
          List.nth args 2 ^^ n ^^ shr 1 ^^ lt ^^ E.if0
        (bind env "sift_down_slots" (slots env q) (fun arr ->
        bind env "sift_down_entry" (item env arr (List.nth args 2)) (fun moving ->
        bind env "sift_down_priority" (priority env moving) (fun moving_priority ->
          List.nth args 2 ^^ set_pos ^^
          G.loop0 (G.with_current_depth (fun loop ->
            pos ^^ pos ^^ add ^^ num 1 ^^ add ^^ set_child ^^
            child ^^ n ^^ lt ^^ E.if0
              (item env arr child ^^ set_entry ^^
               child ^^ num 1 ^^ add ^^ n ^^ lt ^^ E.if0
                (bind env "right_entry" (item env arr (child ^^ num 1 ^^ add)) (fun right ->
                 less env ordering comparator (priority env right) (priority env child_entry) ^^
                 E.if0 (child ^^ num 1 ^^ add ^^ set_child ^^ right ^^ set_entry) G.nop)) G.nop ^^
               less env ordering comparator (priority env child_entry) moving_priority ^^
               E.if0 (move_step env ordering arr pos child moving child_entry ^^ child ^^ set_pos ^^ G.branch_to_ loop) G.nop) G.nop)) ^^
          finish_move env ordering arr (List.nth args 2) pos moving)))) G.nop)))
  (* Pop's replacement normally travels close to the bottom. For proven
     scalar comparisons, select the downward path first, then undo the suffix
     whose keys are >= the replacement. Ascending on equality is essential:
     it restores exactly the layout of the ordinary strict-less downward sift.
     The first comparison preserves the O(1) stop for equal/small replacements. *)
  let sift_pop_bottom env ordering q comparator start =
    invoke [q; comparator; start]
      (helper env ("sift_pop_bottom_" ^ order_name ordering) 3 0 (fun env args ->
        let q = List.nth args 0 and comparator = List.nth args 1 and start = List.nth args 2 in
        let set_pos, pos = new_local env "ipq_bottom_index" in
        let set_child, child = new_local env "ipq_bottom_child" in
        let set_entry, child_entry = new_local env "ipq_bottom_child_entry" in
        bind env "bottom_slots" (slots env q) (fun arr ->
        bind env "bottom_size" (size env q) (fun n ->
        bind env "bottom_entry" (item env arr start) (fun moving ->
        bind env "bottom_priority" (priority env moving) (fun moving_priority ->
          let choose_child () =
            pos ^^ pos ^^ add ^^ num 1 ^^ add ^^ set_child ^^
            child ^^ n ^^ lt ^^ E.if0
              (item env arr child ^^ set_entry ^^
               child ^^ num 1 ^^ add ^^ n ^^ lt ^^ E.if0
                 (bind env "bottom_right" (item env arr (child ^^ num 1 ^^ add)) (fun right ->
                    less env ordering comparator (priority env right) (priority env child_entry) ^^
                    E.if0 (child ^^ num 1 ^^ add ^^ set_child ^^ right ^^ set_entry) G.nop)) G.nop) G.nop
          in
          start ^^ set_pos ^^ choose_child () ^^
          child ^^ n ^^ lt ^^ E.if0
            (less env ordering comparator (priority env child_entry) moving_priority ^^ E.if0
              (G.loop0 (G.with_current_depth (fun descend ->
                 set_item env arr pos child_entry ^^ set_index env (handle env child_entry) pos ^^
                 child ^^ set_pos ^^ choose_child () ^^
                 child ^^ n ^^ lt ^^ E.if0 (G.branch_to_ descend) G.nop)) ^^
               G.loop0 (G.with_current_depth (fun ascend ->
                 pos ^^ start ^^ gt ^^ E.if0
                   (bind env "bottom_parent" (pos ^^ num 1 ^^ sub ^^ shr 1) (fun parent ->
                    bind env "bottom_parent_entry" (item env arr parent) (fun parent_entry ->
                      less env ordering comparator (priority env parent_entry) moving_priority ^^
                      E.if0 G.nop
                        (set_item env arr pos parent_entry ^^ set_index env (handle env parent_entry) pos ^^
                         parent ^^ set_pos ^^ G.branch_to_ ascend)))) G.nop)) ^^
               set_item env arr pos moving ^^ set_index env (handle env moving) pos) G.nop) G.nop))))))
  let repair env ordering q comparator pos =
    pos ^^ num 0 ^^ gt ^^ E.if0
      (bind env "repair_slots" (slots env q) (fun arr ->
       bind env "repair_parent" (pos ^^ num 1 ^^ sub ^^ shr 1) (fun parent ->
       bind env "repair_entry" (item env arr pos) (fun moving ->
       bind env "repair_parent_entry" (item env arr parent) (fun parent_entry ->
         less env ordering comparator (priority env moving) (priority env parent_entry) ^^
         E.if0 (swap_entries env arr pos parent moving parent_entry ^^ sift_up env ordering q comparator parent)
           (sift_down env ordering q comparator pos))))))
      (sift_down env ordering q comparator pos)
  let remove_at env ordering ~pop q comparator pos =
    let bottom_up = match ordering with Scalar _ -> pop | Callback -> false in
    invoke [q; comparator; pos]
      (helper env ((if bottom_up then "pop_at_" else "remove_at_") ^ order_name ordering) 3 1 (fun env args ->
        let q = List.nth args 0 and comparator = List.nth args 1 and pos = List.nth args 2 in
        bind env "remove_slots" (slots env q) (fun arr ->
        bind env "remove_old" (item env arr pos) (fun old ->
        bind env "remove_last" (size env q ^^ num 1 ^^ sub) (fun last ->
          detach env (handle env old) ^^
          pos ^^ last ^^ lt ^^ E.if0
            (bind env "replacement" (item env arr last) (fun replacement ->
              set_item env arr pos replacement ^^ set_index env (handle env replacement) pos)) G.nop ^^
          set_item env arr last (null env) ^^ set_size env q last ^^
          pos ^^ last ^^ lt ^^ E.if0
            (if bottom_up then sift_pop_bottom env ordering q comparator pos
             else repair env ordering q comparator pos) G.nop ^^
          shrink env q ^^ old)))))
  let make_entry env key value h = Object.lit env et [
    "priority", T.Any, (fun () -> key);
    "value", T.Any, (fun () -> value);
    "handle", ht, (fun () -> h);
  ]
  let pair env entry = priority env entry ^^ payload env entry ^^ Tuple.from_stack env 2
  let compile_body operation ordering env specialization args =
    let self = List.hd args in
    let comparator = match args with _ :: comparator :: _ -> comparator | _ -> num 0 in
    let with_handle absent body =
      bind env "handle_owner" (field env ht self "owner") (fun q ->
        present env q ^^ ifv
          (bind env "handle_index" (index env self) (fun pos ->
            pos ^^ size env q ^^ lt ^^ E.else_trap_with env "indexed-priority-queue: malformed handle" ^^
            bind env "handle_entry" (item env (slots env q) pos) (fun old -> body q pos old))) absent)
    in
    match operation with
    | Peek -> size env self ^^ num 0 ^^ eq ^^ ifv (null env) (pair env (item env (slots env self) (num 0)))
    | Peek_priority ->
      let kt = List.hd specialization.C.type_arguments in
      size env self ^^ num 0 ^^ eq ^^ ifv (null env)
        (Opt.inject env kt (priority env (item env (slots env self) (num 0))))
    | Get -> with_handle (null env) (fun _q _pos old -> pair env old)
    | Clear ->
      bind env "clear_slots" (slots env self) (fun arr ->
      bind env "clear_size" (size env self) (fun n ->
        loop_up env "clear_index" (num 0) n (fun i -> detach env (handle env (item env arr i))) ^^
        store env qt self "slots" at (Arr.tabulate_mut env (num 0) (fun _ -> null env)) ^^
        set_size env self (num 0) ^^ Tuple.compile_unit env))
    | Push ->
      let key = List.nth args 2 and value = List.nth args 3 in
      bind env "push_size" (size env self) (fun n ->
      bind env "push_capacity" (slots env self ^^ Arr.len env) (fun capacity ->
        n ^^ capacity ^^ eq ^^ E.if0
          (resize env self (capacity ^^ num 0 ^^ eq ^^ ifv (num 8) (capacity ^^ capacity ^^ add))) G.nop ^^
        bind env "new_handle" (Object.lit env ht [
          "owner", T.Opt qt, (fun () -> self);
          "index", T.nat, (fun () -> n ^^ BigNum.from_word64 env);
        ]) (fun h ->
          set_item env (slots env self) n (make_entry env key value h) ^^
          set_size env self (n ^^ num 1 ^^ add) ^^
          sift_up env ordering self comparator n ^^ h)))
    | Pop ->
      size env self ^^ num 0 ^^ eq ^^ ifv (null env)
        (bind env "popped_entry" (remove_at env ordering ~pop:true self comparator (num 0)) (pair env))
    | Remove -> with_handle (null env) (fun q pos _old ->
        bind env "removed_entry" (remove_at env ordering ~pop:false q comparator pos) (pair env))
    | Reschedule | Replace ->
      let key = List.nth args 2 in
      with_handle (if operation = Reschedule then num 0 else null env) (fun q pos old ->
        let value = if operation = Replace then List.nth args 3 else payload env old in
        set_item env (slots env q) pos (make_entry env key value self) ^^
        repair env ordering q comparator pos ^^
        if operation = Reschedule then num 1 else pair env old)
  let compile operation env specialization arguments =
    let code = match operation with
      | Push | Pop | Remove | Reschedule | Replace ->
        Compare.dispatch env ~comparator_index:1 arguments [I64Type]
          (fun child_env primitive arguments ->
            let ordering = match primitive with None -> Callback | Some prim -> Scalar prim in
            compile_body operation ordering child_env specialization arguments)
      | Peek | Peek_priority | Get | Clear -> compile_body operation Callback env specialization arguments
    in P.{code; representation = Managed}
end
