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
  let scalar env c = c ^^ num 0 ^^ invoke env "scalar_part" ^^
    c ^^ num 1 ^^ invoke env "scalar_part"
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

  (* Heap tags and wire hashes are distinct. Large variants use a balanced
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
            let set_record, record = new_local env "icwire_record_position" in
            cc env c "write_start" ^^ set_record ^^
            G.concat_map (fun f ->
              let set_position, position = new_local env "icwire_field_position" in
              let field_value = value ^^ Object.load_idx_raw env f.lab in
              let body = c ^^ compile_unboxed_const (Schema.field_id f.lab) ^^ invoke env "write_field" ^^ set_position ^^
                child f.typ field_value ^^ c ^^ position ^^ invoke env "write_end" in
              match Type.normalize f.typ with
              | Opt _ -> field_value ^^ Opt.is_some env ^^ E.if0 body G.nop
              | _ -> body) (Schema.sort_fields fields) ^^
            c ^^ record ^^ invoke env "write_end"
          | Variant fields ->
            choose env (value ^^ Variant.get_variant_tag env)
              (List.map (fun f -> Variant.hash_variant_label env f.lab,
                write_word env c (compile_unboxed_const (Schema.field_id f.lab)) 32 ^^
                child f.typ (value ^^ Variant.project env)) fields)
              None (fail env c 2)
          | Non -> fail env c 0
          | _ -> invalid_arg "ICWire unsupported encoder type escaped validation"
        in
        cc env c "enter" ^^ E.if0 (body ^^ cc env c "leave") G.nop)

  let rec decode env typ =
    let typ = Type.normalize typ in
    Func.share_code1 Func.Always env (name_for "decode" typ)
      ("context", I64Type) [I64Type] (fun env c ->
        let unit = Tuple.compile_unit env in
        let checked code = let set, get = new_local env "icwire_decoded" in
          code ^^ set ^^ check env c unit ^^ get in
        let child t = checked (c ^^ decode env t) in
        let body = match typ with
          | Prim Null -> Opt.null_lit env
          | Prim Bool -> cc env c "read_bool"
          | Prim (Text | Blob | Principal as p) ->
            c ^^ num (if p = Text then 1 else if p = Principal then 2 else 0) ^^ invoke env "read_bytes" ^^
            check env c unit ^^ scalar env c ^^
            (if p = Text then Text.of_ptr_size env else if p = Principal then Principal.of_ptr_size env else Blob.of_ptr_size env)
          | Prim Char -> cc env c "read_char" ^^ TaggedSmallWord.msb_adjust Char ^^ TaggedSmallWord.tag env Char
          | Prim (Nat | Int as p) -> c ^^ num (if p = Int then 1 else 0) ^^ invoke env "read_bigint" ^^
            check env c unit ^^ c ^^ num 2 ^^ invoke env "scalar_part" ^^ E.if1 I64Type
              (c ^^ num 3 ^^ invoke env "scalar_part" ^^
               (if p = Int then BigNum.from_signed_word64 env else BigNum.from_word64 env))
              (scalar env c ^^ BigNum.of_leb128 env (p = Int))
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let signed, bits = word_kind p in
            read_word env c signed bits ^^
            (if bits = 64 then BoxedWord64.box env p else TaggedSmallWord.msb_adjust p ^^ TaggedSmallWord.tag env p)
          | Prim (Float | Float32 as p) -> c ^^ num (if p = Float then 64 else 32) ^^ invoke env "read_float" ^^
            (if p = Float then Float.box env else G.i (Convert (Wasm_exts.Values.F32 F32Op.DemoteF64)) ^^ box_float32 env)
          | Opt payload -> cc env c "read_bool" ^^ E.if1 I64Type
              (Opt.inject env payload (child payload)) (Opt.null_lit env)
          | Tup ts -> G.concat_map child ts ^^ Tuple.from_stack env (List.length ts)
          | Array t -> Arr.tabulate env (cc env c "read_array") (fun _ -> child t)
          | Obj (Object, fields, _) ->
            let set_more, more = new_local env "icwire_more_fields" in
            let next = cc env c "record_next" ^^ set_more ^^ check env c unit in
            let field_vars = List.map (fun f -> let set, get = new_local env ("icwire_field_" ^ f.lab) in f,set,get) (Schema.sort_fields fields) in
            cc env c "record_start" ^^ next ^^
            G.concat_map (fun (f,set,get) ->
              let id = Schema.field_id f.lab in
              G.loop0 (G.with_current_depth (fun loop -> more ^^ E.if0
                (cc env c "field_tag" ^^ compile_unboxed_const id ^^ compile_comparison I64Op.LtU ^^
                 E.if0 (cc env c "field_skip" ^^ next ^^ G.branch_to_ loop) G.nop) G.nop)) ^^
              (match Type.normalize f.typ with Opt _ -> Opt.null_lit env | _ -> unit) ^^ set ^^
              more ^^ cc env c "field_tag" ^^ compile_eq_const id ^^
              G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^ E.if0
                (child f.typ ^^ set ^^
                 (match Type.normalize f.typ with Opt _ -> get ^^ Opt.is_some env ^^
                   E.if0 G.nop (fail env c 3) | _ -> G.nop) ^^
                 cc env c "field_end" ^^ next)
                (match Type.normalize f.typ with Opt _ -> G.nop | _ -> fail env c 1 ^^ check env c unit)) field_vars ^^
            G.loop0 (G.with_current_depth (fun loop -> more ^^ E.if0
              (cc env c "field_skip" ^^ next ^^ G.branch_to_ loop) G.nop)) ^^
            Object.lit_raw env (List.map (fun (f,_,get) -> f.lab, (fun () -> get)) field_vars)
          | Variant fields ->
            let tag = checked (read_word env c false 32) in
            choose env tag (List.map (fun f -> Schema.field_id f.lab,
              Variant.inject env f.lab (child f.typ)) fields)
              (Some I64Type) (fail env c 2 ^^ unit)
          | Non -> fail env c 0 ^^ unit
          | _ -> invalid_arg "ICWire unsupported decoder type escaped validation"
        in cc env c "enter" ^^ E.if1 I64Type
          (checked body ^^ cc env c "leave") unit)

  let result env c payload =
    cc env c "ok" ^^ E.if1 I64Type (Variant.inject env "ok" payload)
      (Variant.inject env "err" (Object.lit_raw env [
        "kind", (fun () -> c ^^ num 0 ^^ invoke env "error_part" ^^
          c ^^ num 1 ^^ invoke env "error_part" ^^ Text.of_ptr_size env);
        "offset", (fun () -> c ^^ num 2 ^^ invoke env "error_part" ^^ BoxedWord64.box env Nat64);
      ]))

  let compile_encode env specialization =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with [typ] -> typ | _ -> assert false in
    let set_value, value = new_local env "icwire_value" in
    let set_context, c = new_local env "icwire_context" in
    let set_result, get_result = new_local env "icwire_result" in
    set_value ^^ num 0 ^^ num 0 ^^ invoke env "new" ^^ set_context ^^ cc env c "write_header" ^^
    value ^^ c ^^ encode env typ ^^
    result env c (c ^^ num 0 ^^ invoke env "output_part" ^^ c ^^ num 1 ^^ invoke env "output_part" ^^ Blob.of_ptr_size env) ^^
    set_result ^^ cc env c "done" ^^ get_result

  let compile_decode env specialization =
    let typ = match specialization.Mo_values.Compute_plugin.type_arguments with [typ] -> typ | _ -> assert false in
    let set_source, source = new_local env "icwire_source" in
    let set_context, c = new_local env "icwire_context" in
    let set_value, value = new_local env "icwire_value" in
    let set_result, get_result = new_local env "icwire_result" in
    set_source ^^ source ^^ Blob.payload_ptr_unskewed env ^^ source ^^ Blob.len env ^^ invoke env "new" ^^ set_context ^^
    cc env c "read_header" ^^ c ^^ decode env typ ^^ set_value ^^ cc env c "finish" ^^
    result env c value ^^ set_result ^^ cc env c "done" ^^ get_result
end

module Encoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module Visitor = Make(B)
    let compile env s arguments = Plugin_codegen.{representation = Managed;
      code = G.concat arguments ^^ Visitor.compile_encode env s}
  end
end
module Decoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module Visitor = Make(B)
    let compile env s arguments = Plugin_codegen.{representation = Managed;
      code = G.concat arguments ^^ Visitor.compile_decode env s}
  end
end
