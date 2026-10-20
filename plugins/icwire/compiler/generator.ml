(* Schema-specialized visitors. Only compiler SDK helpers touch managed values;
   the runtime owns bounded byte cursors and canonical scalar validation. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types
open Type
module G = InstrList
open G

module TypeMap = Map.Make (Type.Ord)
let names = ref TypeMap.empty
let next_name = ref 0
let name_for operation typ =
  let n = match TypeMap.find_opt typ !names with
    | Some n -> n
    | None -> let n = !next_name in incr next_name;
      names := TypeMap.add typ n !names; n in
  "@icwire_" ^ operation ^ "_" ^ string_of_int n

module Make (B : Plugin_codegen.Backend) = struct
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let invoke env name = call env "icwire" ("icwire_" ^ name)
  let cc env c name = c ^^ invoke env name
  let fail env c code = c ^^ num code ^^ invoke env "fail"
  let check env c result = cc env c "ok" ^^ E.if0 G.nop (result ^^ G.i Return)
  let bytes env value convert action =
    let set, get = new_local env "icwire_bytes" in
    value ^^ convert ^^ set ^^
    action (get ^^ Blob.payload_ptr_unskewed env) (get ^^ Blob.len env)
  let word_kind = function
    | Nat8 -> false, 8 | Nat16 -> false, 16 | Nat32 -> false, 32 | Nat64 -> false, 64
    | Int8 -> true, 8 | Int16 -> true, 16 | Int32 -> true, 32 | Int64 -> true, 64
    | _ -> invalid_arg "ICWire word kind"
  let write_word env c value bits = c ^^ value ^^ num bits ^^ invoke env "write_word"
  let read_word env c signed bits = c ^^ num (if signed then 1 else 0) ^^ num bits ^^ invoke env "read_word"

  (* Heap tags and wire variant ordinals are distinct. Large variants use a balanced
     dispatch tree, without linear tag comparisons on each successful call. *)
  let choose env tag cases result otherwise =
    let set, get = new_local env "icwire_tag" in
    let cases = Array.of_list (List.sort (fun (a,_) (b,_) -> Int64.compare a b) cases) in
    let if_ = match result with None -> E.if0 | Some t -> E.if1 t in
    let rec tree first last =
      if first = last then otherwise
      else if last - first <= 3 then
        let id, body = cases.(first) in
        get ^^ compile_eq_const id ^^ if_ body (tree (first + 1) last)
      else
        let middle = first + (last - first) / 2 in
        let id, _ = cases.(middle) in
        get ^^ compile_unboxed_const id ^^ compile_comparison I64Op.LtU ^^
        if_ (tree first middle) (tree middle last)
    in tag ^^ set ^^ tree 0 (Array.length cases)

  let rec encode env typ =
    let typ = Type.normalize typ in
    Func.share_code Func.Always env (name_for "encode" typ)
      ["value", I64Type; "context", I64Type] [] (fun env args ->
        let value, c = match args with [v;c] -> v,c | _ -> assert false in
        let child typ value = value ^^ c ^^ encode env typ ^^ check env c G.nop in
        let body = match typ with
          | Prim Null -> G.nop
          | Prim Bool -> c ^^ value ^^ invoke env "write_bool"
          | Prim (Text | Blob | Principal as p) ->
            let kind = if p = Text then 1 else if p = Principal then 2 else 0 in
            c ^^ value ^^ (if p = Text then Text.size env else Blob.len env) ^^
            num kind ^^ invoke env "check_bytes" ^^ E.if0
              (bytes env value (if p = Text then Text.to_blob env else G.nop)
                (fun ptr len -> c ^^ ptr ^^ len ^^ num kind ^^ invoke env "write_bytes")) G.nop
          | Obj (Actor, _, _) ->
            c ^^ value ^^ Blob.len env ^^ num 2 ^^
            invoke env "check_bytes" ^^ E.if0
              (bytes env value G.nop (fun ptr len ->
                c ^^ ptr ^^ len ^^ num 2 ^^ invoke env "write_bytes")) G.nop
          | Func (Shared _, _, _, _, _) ->
            child Schema.actor_reference (value ^^ SharedFunc.principal env) ^^
            child Type.text (value ^^ SharedFunc.method_name env)
          | Prim Char -> c ^^ value ^^ TaggedSmallWord.lsb_adjust_codepoint env ^^ invoke env "write_char"
          | Prim (Nat | Int as p) ->
            value ^^ BitTagged.if_tagged_scalar env []
              (c ^^ value ^^ BigNum.to_word64 env ^^ num (if p = Int then 1 else 0) ^^ invoke env "write_small")
              (c ^^ value ^^ buffer_size env typ ^^ G.i Drop ^^ invoke env "check_bigint" ^^ E.if0
              (bytes env value (BigNum.to_leb128 env (p = Int)) (fun ptr len ->
                c ^^ ptr ^^ len ^^ num (if p = Int then 1 else 0) ^^ invoke env "write_bigint")) G.nop)
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let _, bits = word_kind p in
            write_word env c (value ^^ (if bits = 64 then BoxedWord64.unbox env p else TaggedSmallWord.lsb_adjust p)) bits
          | Prim (Float | Float32 as p) ->
            c ^^ value ^^ (if p = Float then Float.unbox env else unbox_float32 env ^^
              G.i (Convert (Wasm_exts.Values.F64 F64Op.PromoteF32))) ^^
            num (if p = Float then 64 else 32) ^^ invoke env "write_float"
          | Opt payload -> value ^^ Opt.is_some env ^^ E.if0
              (c ^^ num 1 ^^ invoke env "write_bool" ^^ child payload (value ^^ Opt.project env payload))
              (c ^^ num 0 ^^ invoke env "write_bool")
          | Tup ts -> G.concat_mapi (fun i t -> child t (value ^^ Tuple.load_n env (Int64.of_int i))) ts
          | Array t ->
            c ^^ value ^^ Arr.len env ^^ invoke env "write_array" ^^ check env c G.nop ^^
            Arr.for_each env value (value ^^ Arr.len env) (child t)
          | Obj (Object, fields, _) ->
            G.concat_map (fun f -> child f.Type.typ
              (value ^^ Object.load_idx_raw env f.lab)) (Schema.sort_fields fields)
          | Variant fields ->
            choose env (value ^^ Variant.get_variant_tag env)
              (List.mapi (fun ordinal f -> Variant.hash_variant_label env f.Type.lab,
                c ^^ num ordinal ^^ invoke env "write_length" ^^
                child f.typ (value ^^ Variant.project env)) (Schema.sort_fields fields))
              None (fail env c 2)
          | Non -> fail env c 0
          | _ -> invalid_arg "ICWire unsupported encoder type escaped validation"
        in
        cc env c "enter" ^^ E.if0 (body ^^ cc env c "leave") G.nop)

  let result env c payload =
    cc env c "ok" ^^ E.if1 I64Type (Variant.inject env "ok" payload)
      (Variant.inject env "err" (Object.lit_raw env [
        "kind", (fun () -> c ^^ num 0 ^^ invoke env "error_part" ^^
          c ^^ num 1 ^^ invoke env "error_part" ^^ Text.of_ptr_size env);
        "offset", (fun () -> c ^^ num 2 ^^ invoke env "error_part" ^^ BoxedWord64.box env Nat64);
      ]))

  let compile_encode ?limit env specialization =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with typ::_ -> typ | _ -> assert false in
    let set_value, value = new_local env "icwire_value" in
    let set_context, c = new_local env "icwire_context" in
    let set_result, get_result = new_local env "icwire_result" in
    set_value ^^ (match limit with
      | None -> num 0 ^^ num 0 ^^ invoke env "new"
      | Some limit -> limit ^^ invoke env "new_bounded") ^^ set_context ^^
    value ^^ c ^^ encode env typ ^^
    result env c (c ^^ num 0 ^^ invoke env "output_part" ^^ c ^^ num 1 ^^ invoke env "output_part" ^^ Blob.of_ptr_size env) ^^
    set_result ^^ cc env c "done" ^^ get_result

end
