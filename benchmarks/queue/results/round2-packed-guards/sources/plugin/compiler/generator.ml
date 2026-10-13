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
  let shift_left = G.i (Binary (Wasm_exts.Values.I64 I64Op.Shl))
  let shift_right = G.i (Binary (Wasm_exts.Values.I64 I64Op.ShrU))
  let or_ = G.i (Binary (Wasm_exts.Values.I64 I64Op.Or))
  let wrap = num 31 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And))
  let eq = compile_comparison I64Op.Eq
  let null env = Opt.null_lit env
  let present env x = x ^^ Opt.is_some env
  let bind env name value f =
    let set, get = new_local env ("queue_" ^ name) in value ^^ set ^^ f get
  let field env typ obj name = obj ^^ Object.load env typ name
  let store env typ obj name vt value = Object.set env typ name vt obj value
  (* One Nat32 stores count in bits 5..10 and start in bits 0..4. *)
  let metadata env chunk = field env ct chunk "meta" ^^ TaggedSmallWord.lsb_adjust T.Nat32
  let decode_count value = value ^^ num 5 ^^ shift_right
  let decode_start value = value ^^ wrap
  let set_metadata env chunk offset length =
    store env ct chunk "meta" T.nat32
      (length ^^ num 5 ^^ shift_left ^^ offset ^^ or_ ^^
       TaggedSmallWord.msb_adjust T.Nat32 ^^ TaggedSmallWord.tag env T.Nat32)
  let set_link env chunk name value = store env ct chunk name (T.Opt ct) value
  let set_end env queue name value = store env qt queue name (T.Opt ct) value
  let slots env chunk = field env ct chunk "values"
  let get env chunk index = slots env chunk ^^ index ^^ Arr.get env
  let set env chunk index value = Arr.set env slots_t (T.Opt T.Any) (slots env chunk) index value
  let invalid env = E.trap_with env "queue: malformed storage"
  (* Private layout invariants are established by the constructors and updates.
     The SDK still checks every array index and applies normal GC barriers;
     assertValid is the explicit full representation check. *)
  let make_chunk env = Object.lit env ct [
    "values", slots_t, (fun () -> Arr.tabulate_mut env (num 32) (fun _ -> null env));
    "meta", T.nat32, (fun () -> num 0 ^^ TaggedSmallWord.tag env T.Nat32);
    "previous", T.Opt ct, (fun () -> null env);
    "next", T.Opt ct, (fun () -> null env);
  ]
  let take_chunk env queue =
    bind env "spare" (field env qt queue "spare") (fun spare ->
      present env spare ^^ E.if1 I64Type
        (set_end env queue "spare" (null env) ^^ spare) (make_chunk env))
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
    bind env "metadata" (metadata env chunk) (fun meta ->
      decode_count meta ^^ set_n ^^ decode_start meta ^^ set_s) ^^
    n ^^ num 32 ^^ eq ^^ E.if0
      (bind env "fresh" (take_chunk env queue) (fun fresh ->
        set_link env fresh toward chunk ^^ set_link env chunk outward fresh ^^
        set_end env queue endpoint fresh ^^ fresh ^^ set_chunk ^^
        num 0 ^^ set_n ^^ num 0 ^^ set_s)) G.nop ^^
    bind env "index" ((if front then s ^^ num 1 ^^ sub else s ^^ n ^^ add) ^^ wrap) (fun index ->
      set env chunk index value ^^
      set_metadata env chunk (if front then index else s) (n ^^ num 1 ^^ add) ^^
      store env qt queue "size" T.nat
        (field env qt queue "size" ^^ num 1 ^^ BigNum.from_word64 env ^^ BigNum.compile_add env))
  let remove env front queue chunk n s index storage =
    let endpoint = if front then "front" else "back" in
    let toward = if front then "next" else "previous" in
    let outward = if front then "previous" else "next" in
    bind env "size" (field env qt queue "size" ^^ BigNum.to_word64 env) (fun size ->
      size ^^ num 0 ^^ eq ^^ E.if0 (invalid env) G.nop ^^
      Arr.set env slots_t (T.Opt T.Any) storage index (null env) ^^
      set_metadata env chunk (if front then s ^^ num 1 ^^ add ^^ wrap else s) (n ^^ num 1 ^^ sub) ^^
      store env qt queue "size" T.nat (size ^^ num 1 ^^ sub ^^ BigNum.from_word64 env) ^^
      n ^^ num 1 ^^ eq ^^ E.if0
        (bind env "adjacent" (field env ct chunk toward) (fun adjacent ->
          present env adjacent ^^ E.if0
            (set_end env queue endpoint adjacent ^^
             set_link env adjacent outward (null env) ^^
             set_link env chunk toward (null env) ^^
             set_metadata env chunk (num 0) (num 0) ^^
             set_end env queue "spare" chunk)
            (set_end env queue "spare" (null env)))) G.nop)
  let read_chunk env front queue chunk =
    bind env "metadata" (metadata env chunk) (fun meta ->
    bind env "count" (decode_count meta) (fun n ->
      n ^^ num 0 ^^ eq ^^ E.if1 I64Type (null env)
        (bind env "start" (decode_start meta) (fun s ->
         bind env "index" (if front then s else s ^^ n ^^ add ^^ num 1 ^^ sub ^^ wrap) (fun index ->
         bind env "slots" (slots env chunk) (fun storage ->
         bind env "result" (storage ^^ index ^^ Arr.get env) (fun result ->
           remove env front queue chunk n s index storage ^^ result)))))))
  let read env front queue =
    let endpoint = if front then "front" else "back" in
    bind env "chunk" (field env qt queue endpoint) (fun chunk ->
      present env chunk ^^ E.if1 I64Type
        (read_chunk env front queue chunk) (null env))
  let peek env front queue =
    let endpoint = if front then "front" else "back" in
    bind env "chunk" (field env qt queue endpoint) (fun chunk ->
      present env chunk ^^ E.if1 I64Type
        (bind env "metadata" (metadata env chunk) (fun meta ->
         bind env "count" (decode_count meta) (fun n ->
          n ^^ num 0 ^^ eq ^^ E.if1 I64Type (null env)
            (get env chunk (if front then decode_start meta
              else decode_start meta ^^ n ^^ add ^^ num 1 ^^ sub ^^ wrap)))))
        (null env))
  let to_array env mutable_ queue =
    let set_chunk, chunk = new_local env "queue_cursor_chunk" in
    let set_slots, slots = new_local env "queue_cursor_slots" in
    let set_left, left = new_local env "queue_cursor_left" in
    let set_index, index = new_local env "queue_cursor_index" in
    field env qt queue "front" ^^ set_chunk ^^
    num 0 ^^ set_left ^^
    (if mutable_ then Arr.tabulate_mut else Arr.tabulate) env
      (field env qt queue "size" ^^ BigNum.to_word64 env) (fun _ ->
        left ^^ num 0 ^^ eq ^^ E.if0
          (present env chunk ^^ E.else_trap_with env "queue: malformed storage" ^^
           field env ct chunk "values" ^^ set_slots ^^
           bind env "metadata" (metadata env chunk) (fun meta ->
             decode_start meta ^^ set_index ^^ decode_count meta ^^ set_left) ^^
           left ^^ num 0 ^^ eq ^^ E.if0 (invalid env) G.nop ^^
           field env ct chunk "next" ^^ set_chunk) G.nop ^^
        bind env "slot" (slots ^^ index ^^ Arr.get env) (fun slot ->
          present env slot ^^ E.else_trap_with env "queue: malformed storage" ^^
          bind env "item" (slot ^^ Opt.project env T.Any) (fun item ->
          index ^^ num 1 ^^ add ^^ wrap ^^ set_index ^^
          left ^^ num 1 ^^ sub ^^ set_left ^^ item)))
  let compile operation env specialization arguments =
    let kt = match specialization.C.type_arguments with [t] -> t | _ -> invalid_arg "queue: type arguments" in
    let code = match operation, arguments with
      | (Push_front | Push_back), [queue; value] ->
        queue ^^ Opt.inject env kt value ^^
        helper env (Schema.name operation) 2 0 (fun env args ->
          push env (operation = Push_front) (List.nth args 0) (List.nth args 1)) ^^
        Tuple.compile_unit env
      | (Pop_front | Pop_back), [queue] ->
        queue ^^ helper env (Schema.name operation) 1 1 (fun env args ->
          read env (operation = Pop_front) (List.hd args))
      | (Peek_front | Peek_back), [queue] ->
        bind env "queue" queue (fun queue -> peek env (operation = Peek_front) queue)
      | (To_array | To_var_array), [queue] ->
        queue ^^ helper env (Schema.name operation) 1 1 (fun env args ->
          to_array env (operation = To_var_array) (List.hd args))
      | _ -> invalid_arg "queue: arguments"
    in P.{code; representation = Managed}
end
