module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
open Wasm_exts.Ast
open Wasm_exts.Types
open Schema
let ( ^^ ) = G.( ^^ )

module Make (B : P.Backend) = struct
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let add = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let mul = G.i (Binary (Wasm_exts.Values.I64 I64Op.Mul))
  let div = G.i (Binary (Wasm_exts.Values.I64 I64Op.DivU))
  let rem = G.i (Binary (Wasm_exts.Values.I64 I64Op.RemU))
  let eq = compile_comparison I64Op.Eq
  let lt = compile_comparison I64Op.LtU
  let gt = compile_comparison I64Op.GtU
  let ifv = E.if1 I64Type
  let rt = Schema.ring T.Any
  let ct = Schema.chunk T.Any
  let dt = Schema.directory T.Any
  let null env = Opt.null_lit env
  let bind env name value body = let set, get = new_local env ("history_ring_" ^ name) in value ^^ set ^^ body get
  let field env ring name = ring ^^ Object.load env rt name
  let small env ring name = field env ring name ^^ BigNum.to_word64 env
  let store env ring name typ value = Object.set env rt name typ ring value
  let store_small env ring name value = store env ring name T.nat (value ^^ BigNum.from_word64 env)
  let chunks env ring = field env ring "chunks"
  let width env ring = small env ring "chunkSize"
  let count env ring = small env ring "size"
  let head env ring = small env ring "head"
  let nat env n = num n ^^ BigNum.from_word64 env
  (* All callers establish a >= b. Compact operands can subtract without
     allocating a temporary negative bigint; arbitrary Nat keeps the fallback. *)
  let nat_sub env a b = bind env "minuend" a (fun a -> bind env "subtrahend" b (fun b ->
    let large = a ^^ b ^^ BigNum.compile_neg env ^^ BigNum.compile_add env in
    a ^^ BitTagged.if_tagged_scalar env [I64Type]
      (b ^^ BitTagged.if_tagged_scalar env [I64Type]
        (a ^^ BigNum.to_word64 env ^^ b ^^ BigNum.to_word64 env ^^ sub ^^ BigNum.from_word64 env)
        large)
      large))
  let nat_lt env a b = a ^^ b ^^ Compare.scalar env T.Nat ^^ num 0 ^^ compile_comparison I64Op.LtS
  let nat_eq env a b = a ^^ b ^^ Compare.scalar env T.Nat ^^ num 0 ^^ eq
  let invalid env = E.trap_with env "history-ring: malformed storage"
  let chunk env directory i = bind env "chunk" (directory ^^ i ^^ Arr.get env) (fun c ->
    c ^^ Opt.is_some env ^^ E.else_trap_with env "history-ring: malformed storage" ^^ c)
  (* Physical generic slots are always written through ?Any. This preserves
     conservative GC barriers even when an instantiation stores ?Null. *)
  let set_slot env array i value = Arr.set env ct (T.Opt T.Any) array i value
  let set_chunk env directory i value = Arr.set env dt (T.Opt ct) directory i value
  let physical env ring offset = head env ring ^^ offset ^^ add ^^ chunks env ring ^^ Arr.len env ^^ width env ring ^^ mul ^^ rem
  let entry env ring position = bind env "position" position (fun p ->
    chunk env (chunks env ring) (p ^^ width env ring ^^ div) ^^ p ^^ width env ring ^^ rem ^^ Arr.get env)
  let write_entry env ring position value = bind env "position" position (fun p ->
    set_slot env (chunk env (chunks env ring) (p ^^ width env ring ^^ div)) (p ^^ width env ring ^^ rem) value)
  let loop_up env name first limit body =
    let set, get = new_local env ("history_ring_" ^ name) in
    first ^^ set ^^ G.loop0 (G.with_current_depth (fun loop ->
      get ^^ limit ^^ lt ^^ E.if0 (body get ^^ get ^^ num 1 ^^ add ^^ set ^^ G.branch_to_ loop) G.nop))
  let helper env name arity results body = Func.share_code Func.Always env ("history_ring_" ^ name)
    (List.init arity (fun i -> "a" ^ string_of_int i, I64Type))
    (List.init results (fun _ -> I64Type)) body
  let invoke xs fn = G.concat xs ^^ fn
  let reset env ring =
    store env ring "chunks" dt (Arr.tabulate_mut env (num 0) (fun _ -> null env)) ^^
    store_small env ring "head" (num 0) ^^ store_small env ring "size" (num 0)
  let grow env ring = invoke [ring] (helper env "grow" 1 0 (fun env args ->
    let ring = List.hd args in
    bind env "old" (chunks env ring) (fun old ->
    bind env "old_length" (old ^^ Arr.len env) (fun old_n ->
    bind env "width" (width env ring) (fun w ->
    bind env "proposed" (old_n ^^ num 0 ^^ eq ^^ ifv (num 1) (old_n ^^ num 2 ^^ mul)) (fun proposed ->
    bind env "new_length"
      (nat_lt env (field env ring "capacity") (proposed ^^ w ^^ mul ^^ BigNum.from_word64 env) ^^ ifv
        (field env ring "capacity" ^^ BigNum.to_word64 env ^^ w ^^ add ^^ num 1 ^^ sub ^^ w ^^ div)
        proposed) (fun new_n ->
    bind env "head" (head env ring) (fun h ->
    bind env "offset" (h ^^ w ^^ rem) (fun offset ->
      new_n ^^ old_n ^^ gt ^^ E.else_trap_with env "history-ring: malformed storage" ^^
      bind env "grown"
        (Arr.tabulate_mut env new_n (fun i ->
          i ^^ old_n ^^ lt ^^ ifv
            (old ^^ h ^^ w ^^ div ^^ i ^^ add ^^ old_n ^^ rem ^^ Arr.get env)
            (null env))) (fun grown ->
        offset ^^ num 0 ^^ eq ^^ E.if0 G.nop
          (bind env "first" (chunk env grown (num 0)) (fun first ->
           bind env "split" (Arr.tabulate_mut env w (fun i ->
             i ^^ offset ^^ lt ^^ ifv (first ^^ i ^^ Arr.get env) (null env))) (fun split ->
             loop_up env "clear_split" (num 0) offset (fun i -> set_slot env first i (null env)) ^^
             set_chunk env grown old_n split))) ^^
        store env ring "chunks" dt grown ^^ store_small env ring "head" offset))))))))))
  let remove env ring release = invoke [ring] (helper env (if release then "pop" else "evict") 1 1 (fun env args ->
    let ring = List.hd args in
    bind env "size" (count env ring) (fun n ->
      n ^^ num 0 ^^ eq ^^ ifv (null env)
        (bind env "directory" (chunks env ring) (fun directory ->
         bind env "width" (width env ring) (fun w ->
         bind env "head" (head env ring) (fun h ->
         bind env "chunk_index" (h ^^ w ^^ div) (fun ci ->
         bind env "head_chunk" (chunk env directory ci) (fun c ->
         bind env "slot" (h ^^ w ^^ rem) (fun slot ->
         bind env "old" (c ^^ slot ^^ Arr.get env) (fun old ->
         bind env "new_head" (h ^^ num 1 ^^ add ^^ directory ^^ Arr.len env ^^ w ^^ mul ^^ rem) (fun nh ->
           set_slot env c slot (null env) ^^
           store_small env ring "head" nh ^^ store_small env ring "size" (n ^^ num 1 ^^ sub) ^^
           (if release then
             n ^^ num 1 ^^ eq ^^ E.if0 (reset env ring)
               (nh ^^ w ^^ rem ^^ num 0 ^^ eq ^^ E.if0
                 (n ^^ num 1 ^^ sub ^^ directory ^^ Arr.len env ^^ num 1 ^^ sub ^^ w ^^ mul ^^ gt ^^
                  E.if0 G.nop (set_chunk env directory ci (null env))) G.nop)
            else G.nop) ^^ old))))))))))))
  let compile operation env _specialization arguments =
    let ring = List.hd arguments in
    let code = match operation, arguments with
    | Append, [_; value] ->
      bind env "sequence" (field env ring "next") (fun sequence ->
        nat_eq env (field env ring "capacity") (nat env 0) ^^ E.if0 G.nop
          (nat_eq env (field env ring "size") (field env ring "capacity") ^^ E.if0
             (remove env ring false ^^ G.i Drop) G.nop ^^
           count env ring ^^ chunks env ring ^^ Arr.len env ^^ width env ring ^^ mul ^^ eq ^^ E.if0
             (grow env ring) G.nop ^^
           bind env "directory" (chunks env ring) (fun directory ->
           bind env "width" (width env ring) (fun w ->
           bind env "size" (count env ring) (fun n ->
           bind env "position" (head env ring ^^ n ^^ add ^^ directory ^^ Arr.len env ^^ w ^^ mul ^^ rem) (fun p ->
           bind env "chunk_index" (p ^^ w ^^ div) (fun ci ->
           bind env "destination" (directory ^^ ci ^^ Arr.get env) (fun destination ->
           bind env "chunk" (destination ^^ Opt.is_some env ^^ ifv destination
             (bind env "allocated_chunk" (Arr.tabulate_mut env w (fun _ -> null env)) (fun c ->
               set_chunk env directory ci c ^^ c))) (fun c ->
             set_slot env c (p ^^ w ^^ rem) (Opt.inject env T.Any value) ^^
             store_small env ring "size" (n ^^ num 1 ^^ add))))))))) ^^
        store env ring "next" T.nat (sequence ^^ nat env 1 ^^ BigNum.compile_add env) ^^ sequence)
    | Get, [_; sequence] ->
      bind env "first" (nat_sub env (field env ring "next") (field env ring "size")) (fun first ->
        nat_lt env sequence first ^^ ifv (null env)
          (nat_lt env sequence (field env ring "next") ^^ ifv
            (entry env ring (physical env ring (nat_sub env sequence first ^^ BigNum.to_word64 env)))
            (null env)))
    | Pop_front, [_] -> remove env ring true
    | Drop, [_; amount] ->
      bind env "size" (count env ring) (fun n ->
        nat_lt env amount (field env ring "size") ^^ ifv
          (bind env "drop_count" (amount ^^ BigNum.to_word64 env) (fun amount ->
           bind env "directory" (chunks env ring) (fun directory ->
           bind env "width" (width env ring) (fun w ->
           bind env "span" (directory ^^ Arr.len env ^^ w ^^ mul) (fun span ->
           bind env "cursor" (head env ring) (fun cursor ->
             loop_up env "drop" (num 0) amount (fun i ->
               bind env "chunk_index" (cursor ^^ w ^^ div) (fun ci ->
                 set_slot env (chunk env directory ci) (cursor ^^ w ^^ rem) (null env) ^^
                 cursor ^^ num 1 ^^ add ^^ span ^^ rem ^^ G.setter_for cursor ^^
                 (* A wrapped tail can share this chunk. Release only when the
                    remaining range fits entirely in the other chunks. *)
                 cursor ^^ w ^^ rem ^^ num 0 ^^ eq ^^ E.if0
                   (n ^^ i ^^ sub ^^ num 1 ^^ sub ^^ span ^^ w ^^ sub ^^ gt ^^
                    E.if0 G.nop (set_chunk env directory ci (null env))) G.nop)) ^^
             store_small env ring "head" cursor ^^
             store_small env ring "size" (n ^^ amount ^^ sub) ^^
             amount ^^ BigNum.from_word64 env))))))
          (reset env ring ^^ n ^^ BigNum.from_word64 env))
    | Page, [_; sequence; limit] ->
      bind env "finish" (field env ring "next") (fun finish ->
      bind env "first" (nat_sub env finish (field env ring "size")) (fun first ->
      bind env "start" (nat_lt env sequence first ^^ ifv first sequence) (fun start ->
        nat_lt env start finish ^^ ifv
          (bind env "available" (nat_sub env finish start) (fun available ->
           bind env "length" (nat_lt env limit available ^^ ifv limit available ^^ BigNum.to_word64 env) (fun length ->
           bind env "offset" (nat_sub env start first ^^ BigNum.to_word64 env) (fun offset ->
           bind env "directory" (chunks env ring) (fun directory ->
           bind env "width" (width env ring) (fun w ->
           bind env "span" (directory ^^ Arr.len env ^^ w ^^ mul) (fun span ->
           bind env "start_position" (head env ring ^^ offset ^^ add) (fun start_position ->
             Arr.tabulate env length (fun i ->
               bind env "position" (start_position ^^ i ^^ add ^^ span ^^ rem) (fun position ->
                 chunk env directory (position ^^ w ^^ div) ^^
                 position ^^ w ^^ rem ^^ Arr.get env ^^ Opt.project env T.Any))))))))))
          (Arr.tabulate env (num 0) (fun _ -> invalid env)))))
    | _ -> invalid_arg "history-ring: invalid operation arguments"
    in P.{code; representation = Managed}
end
