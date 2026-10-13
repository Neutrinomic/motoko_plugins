module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module C = Mo_values.Compute_plugin
open Wasm_exts.Ast
open Wasm_exts.Types
open Schema
let ( ^^ ) = G.( ^^ )

(* Payloads and links always use conservative managed storage views. Helpers
   are shared across T, including ?Null, closures, and mutable payloads. *)
module Make (B : P.Backend) = struct
  open B
  let ct = Schema.chunk T.Any
  let qt = Schema.queue T.Any
  let slots_t = T.Array (T.Mut (T.Opt T.Any))
  let num n = compile_unboxed_const (Int64.of_int n)
  let add = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let wrap = num 31 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And))
  let eq = compile_comparison I64Op.Eq
  let gt = compile_comparison I64Op.GtU
  let null env = Opt.null_lit env
  let present env x = x ^^ Opt.is_some env
  let bind env name value f =
    let set, get = new_local env ("queue_" ^ name) in value ^^ set ^^ f get
  let field env typ obj name = obj ^^ Object.load env typ name
  let store env typ obj name vt value = Object.set env typ name vt obj value
  let count env chunk = field env ct chunk "count" ^^ TaggedSmallWord.lsb_adjust T.Nat32
  let start env chunk = field env ct chunk "start" ^^ TaggedSmallWord.lsb_adjust T.Nat32
  let set_index env chunk name value = store env ct chunk name T.nat32
    (value ^^ TaggedSmallWord.msb_adjust T.Nat32 ^^ TaggedSmallWord.tag env T.Nat32)
  let set_link env chunk name value = store env ct chunk name (T.Opt ct) value
  let set_end env queue name value = store env qt queue name (T.Opt ct) value
  let slots env chunk = field env ct chunk "values"
  let get env chunk index = slots env chunk ^^ index ^^ Arr.get env
  let set env chunk index value = Arr.set env slots_t (T.Opt T.Any) (slots env chunk) index value
  let invalid env = E.trap_with env "queue: malformed storage"
  let check env chunk n s =
    n ^^ num 32 ^^ gt ^^ E.if0 (invalid env) G.nop ^^
    s ^^ num 31 ^^ gt ^^ E.if0 (invalid env) G.nop ^^
    slots env chunk ^^ Arr.len env ^^ num 32 ^^ eq ^^ E.else_trap_with env "queue: malformed storage"
  let make_chunk env = Object.lit env ct [
    "values", slots_t, (fun () -> Arr.tabulate_mut env (num 32) (fun _ -> null env));
    "start", T.nat32, (fun () -> num 0 ^^ TaggedSmallWord.tag env T.Nat32);
    "count", T.nat32, (fun () -> num 0 ^^ TaggedSmallWord.tag env T.Nat32);
    "previous", T.Opt ct, (fun () -> null env);
    "next", T.Opt ct, (fun () -> null env);
  ]
  let helper env name arity results body =
    Func.share_code Func.Always env ("queue_" ^ name)
      (List.init arity (fun i -> "arg" ^ string_of_int i, I64Type))
      (List.init results (fun _ -> I64Type)) body
  let push env front queue value =
    let endpoint = if front then "front" else "back" in
    let toward = if front then "next" else "previous" in
    let outward = if front then "previous" else "next" in
    let set_chunk, chunk = new_local env "queue_endpoint" in
    field env qt queue endpoint ^^ set_chunk ^^
    present env chunk ^^ E.if0 G.nop
      (make_chunk env ^^ set_chunk ^^ set_end env queue "front" chunk ^^ set_end env queue "back" chunk) ^^
    let set_n, n = new_local env "queue_count" in
    let set_s, s = new_local env "queue_start" in
    count env chunk ^^ set_n ^^ start env chunk ^^ set_s ^^
    check env chunk n s ^^
    n ^^ num 32 ^^ eq ^^ E.if0
      (bind env "fresh" (make_chunk env) (fun fresh ->
        set_link env fresh toward chunk ^^ set_link env chunk outward fresh ^^
        set_end env queue endpoint fresh ^^ fresh ^^ set_chunk ^^
        num 0 ^^ set_n ^^ num 0 ^^ set_s)) G.nop ^^
    bind env "index" ((if front then s ^^ num 1 ^^ sub else s ^^ n ^^ add) ^^ wrap) (fun index ->
      set env chunk index value ^^
      (if front then set_index env chunk "start" index else G.nop) ^^
      set_index env chunk "count" (n ^^ num 1 ^^ add) ^^
      store env qt queue "size" T.nat
        (field env qt queue "size" ^^ num 1 ^^ BigNum.from_word64 env ^^ BigNum.compile_add env))
  let remove env front queue chunk n s index =
    let endpoint = if front then "front" else "back" in
    let toward = if front then "next" else "previous" in
    let outward = if front then "previous" else "next" in
    bind env "size" (field env qt queue "size" ^^ BigNum.to_word64 env) (fun size ->
      size ^^ num 0 ^^ eq ^^ E.if0 (invalid env) G.nop ^^
      set env chunk index (null env) ^^
      (if front then set_index env chunk "start" (s ^^ num 1 ^^ add ^^ wrap) else G.nop) ^^
      set_index env chunk "count" (n ^^ num 1 ^^ sub) ^^
      store env qt queue "size" T.nat (size ^^ num 1 ^^ sub ^^ BigNum.from_word64 env) ^^
      n ^^ num 1 ^^ eq ^^ E.if0
        (bind env "adjacent" (field env ct chunk toward) (fun adjacent ->
          present env adjacent ^^ E.if0
            (set_end env queue endpoint adjacent ^^
             set_link env adjacent outward (null env) ^^
             set_link env chunk toward (null env)) G.nop)) G.nop)
  let read_chunk env front pop queue chunk =
    bind env "count" (count env chunk) (fun n ->
    bind env "start" (start env chunk) (fun s ->
      check env chunk n s ^^
      n ^^ num 0 ^^ eq ^^ E.if1 I64Type (null env)
        (bind env "index" ((if front then s else s ^^ n ^^ add ^^ num 1 ^^ sub) ^^ wrap) (fun index ->
         bind env "result" (get env chunk index) (fun result ->
           present env result ^^ E.else_trap_with env "queue: malformed storage" ^^
           (if pop then remove env front queue chunk n s index else G.nop) ^^ result)))))
  let read env front pop queue =
    let endpoint = if front then "front" else "back" in
    bind env "chunk" (field env qt queue endpoint) (fun chunk ->
      present env chunk ^^ E.if1 I64Type
        (read_chunk env front pop queue chunk) (null env))
  let compile operation env specialization arguments =
    let kt = match specialization.C.type_arguments with [t] -> t | _ -> invalid_arg "queue: type arguments" in
    let code = match operation, arguments with
      | (Push_front | Push_back), [queue; value] ->
        queue ^^ Opt.inject env kt value ^^
        helper env (Schema.name operation) 2 0 (fun env args ->
          push env (operation = Push_front) (List.nth args 0) (List.nth args 1)) ^^
        Tuple.compile_unit env
      | (Pop_front | Pop_back | Peek_front | Peek_back), [queue] ->
        queue ^^ helper env (Schema.name operation) 1 1 (fun env args ->
          read env (operation = Pop_front || operation = Peek_front)
            (operation = Pop_front || operation = Pop_back) (List.hd args))
      | _ -> invalid_arg "queue: arguments"
    in P.{code; representation = Managed}
end
