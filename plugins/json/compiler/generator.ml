(* Typed heap visitors; JSON syntax, numeric conversion and buffering live in
   runtime.wasm. Heap layouts and all allocation barriers belong to the SDK. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types
open Type
module G = InstrList
open G

(* Type metadata is erased by the visitor. A compiler-local identity registry
   also handles recursive objects with type components, which the host's
   serialization-oriented type-name formatter does not currently support. *)
module TypeMap = Map.Make (Type.Ord)
let type_names = ref TypeMap.empty
let next_type_name = ref 0
let name_for operation typ =
  let index = match TypeMap.find_opt typ !type_names with
    | Some index -> index
    | None -> let index = !next_type_name in incr next_type_name;
      type_names := TypeMap.add typ index !type_names; index in
  "@json_" ^ operation ^ "_" ^ string_of_int index

module Make (B : Plugin_codegen.Backend) = struct
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let invoke env name = call env "json" ("json_" ^ name)
  let ccall env c name = c ^^ invoke env name
  let fail env c code = c ^^ num code ^^ invoke env "fail"
  let constant_bytes env text action =
    let set, get = new_local env "json_constant" in
    Text.lit env text ^^ Text.to_blob env ^^ set ^^
    action (get ^^ Blob.payload_ptr_unskewed env) (get ^^ Blob.len env)
  let write_byte env c ch = c ^^ num (Char.code ch) ^^ invoke env "write_byte"
  let write_literal env c text = constant_bytes env text (fun ptr len -> c ^^ ptr ^^ len ^^ invoke env "write_raw")
  let write_key env c label =
    constant_bytes env label (fun ptr len -> c ^^ ptr ^^ len ^^ invoke env "write_string") ^^
    write_byte env c ':'
  let key_eq env c label = constant_bytes env label (fun ptr len -> c ^^ ptr ^^ len ^^ invoke env "key_eq")
  let path_field env c label = constant_bytes env label (fun ptr len -> c ^^ ptr ^^ len ^^ invoke env "path_field")
  let scalar env c = c ^^ num 0 ^^ invoke env "scalar_part" ^^ c ^^ num 1 ^^ invoke env "scalar_part"
  let sized_bytes env value convert action =
    let set, get = new_local env "json_bytes" in
    value ^^ convert ^^ set ^^ action (get ^^ Blob.payload_ptr_unskewed env) (get ^^ Blob.len env)
  let word_kind = function
    | Type.Nat8 -> false, 8 | Nat16 -> false, 16 | Nat32 -> false, 32 | Nat64 -> false, 64
    | Int8 -> true, 8 | Int16 -> true, 16 | Int32 -> true, 32 | Int64 -> true, 64
    | _ -> invalid_arg "JSON word_kind"

  let rec encode env typ =
    let typ = Type.normalize typ in
    Func.share_code Func.Always env (name_for "encode" typ)
      ["value", I64Type; "context", I64Type] [] (fun env args ->
        let value, c = match args with [v;c] -> v,c | _ -> assert false in
        let child typ value = value ^^ c ^^ encode env typ in
        let fields fs =
          write_byte env c '{' ^^
          G.concat_mapi (fun i f ->
            (if i = 0 then G.nop else write_byte env c ',') ^^
            write_key env c f.Type.lab ^^
            path_field env c f.lab ^^
            child f.typ (value ^^ Object.load_idx_raw env f.lab) ^^
            ccall env c "path_pop") fs ^^
          write_byte env c '}'
        in
        let body = match typ with
          | Type.Prim Null -> write_literal env c "null"
          | Prim Bool -> value ^^ E.if0
            (write_literal env c "true") (write_literal env c "false")
          | Prim Text ->
            c ^^ value ^^ Text.size env ^^ invoke env "check_string" ^^ E.if0
              (sized_bytes env value (Text.to_blob env) (fun ptr len -> c ^^ ptr ^^ len ^^ invoke env "write_string")) G.nop
          | Prim (Blob | Principal as p) -> sized_bytes env value G.nop (fun ptr len ->
            c ^^ ptr ^^ len ^^ num (if p = Principal then 1 else 0) ^^ invoke env "write_binary")
          | Prim Char -> c ^^ value ^^ TaggedSmallWord.lsb_adjust_codepoint env ^^ invoke env "write_char"
          | Prim (Nat | Int as p) ->
            c ^^ value ^^ buffer_size env typ ^^ G.i Drop ^^ invoke env "check_bigint" ^^ E.if0
              (sized_bytes env value (BigNum.to_leb128 env (p = Int)) (fun ptr len ->
                c ^^ ptr ^^ len ^^ num (if p = Int then 1 else 0) ^^ invoke env "write_bigint")) G.nop
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let signed, bits = word_kind p in
            c ^^ value ^^ (if bits = 64 then BoxedWord64.unbox env p else TaggedSmallWord.lsb_adjust p) ^^
            num (if signed then 1 else 0) ^^ num (if bits = 64 then 1 else 0) ^^ invoke env "write_word"
          | Prim Float -> c ^^ value ^^ Float.unbox env ^^ invoke env "write_float"
          | Prim Float32 -> c ^^ value ^^ unbox_float32 env ^^
            G.i (Convert (Wasm_exts.Values.F64 F64Op.PromoteF32)) ^^ invoke env "write_float"
          | Opt payload ->
            value ^^ Opt.is_some env ^^ E.if0
              ((if Schema.tagged_option payload then write_literal env c "{\"some\":" else G.nop) ^^
               child payload (value ^^ Opt.project env payload) ^^
               (if Schema.tagged_option payload then write_byte env c '}' else G.nop))
              (write_literal env c "null")
          | Tup ts -> write_byte env c '[' ^^
            G.concat_mapi (fun i typ ->
              (if i = 0 then G.nop else write_byte env c ',') ^^
              c ^^ num i ^^ invoke env "path_index" ^^
              child typ (value ^^ Tuple.load_n env (Int64.of_int i)) ^^
              ccall env c "path_pop") ts ^^
            write_byte env c ']'
          | Array typ ->
            let set_i, get_i = new_local env "json_index" in
            c ^^ value ^^ Arr.len env ^^ invoke env "collection" ^^ E.if0 G.nop (G.i Return) ^^
            num 0 ^^ set_i ^^ write_byte env c '[' ^^
            Arr.for_each env value (value ^^ Arr.len env) (fun element ->
              ccall env c "ok" ^^ E.if0 G.nop (G.i Return) ^^
              get_i ^^ compile_eq_const 0L ^^ E.if0 G.nop (write_byte env c ',') ^^
              c ^^ get_i ^^ invoke env "path_index" ^^
              child typ element ^^ ccall env c "path_pop" ^^
              get_i ^^ compile_add_const 1L ^^ set_i) ^^
            write_byte env c ']'
          | Obj (Object, fs, _) -> fields fs
          | Non -> fail env c 0
          | Variant fs ->
            List.fold_right (fun f rest ->
              value ^^ Variant.test_is env f.Type.lab ^^ E.if0
                (write_byte env c '{' ^^ write_key env c f.lab ^^
                 path_field env c f.lab ^^ child f.typ (value ^^ Variant.project env) ^^
                 ccall env c "path_pop" ^^ write_byte env c '}') rest) fs
              (fail env c 2)
          | _ -> invalid_arg "JSON unsupported encoder type escaped validation"
        in
        ccall env c "enter" ^^ E.if0
          (body ^^ ccall env c "leave") G.nop)

  let rec decode env typ =
    let typ = Type.normalize typ in
    Func.share_code1 Func.Always env (name_for "decode" typ)
      ("context", I64Type) [I64Type] (fun env c ->
        let child typ = c ^^ decode env typ in
        let count_array n = ccall env c "array_start" ^^ num n ^^ compile_comparison I64Op.Ne ^^
          E.if0 (fail env c 4) G.nop in
        let expect ch = c ^^ num (Char.code ch) ^^ invoke env "expect" in
        let only_field label payload =
          ccall env c "object_start" ^^
          ccall env c "object_next" ^^ E.if1 I64Type
            (ccall env c "path_key" ^^
             key_eq env c label ^^ E.if1 I64Type payload (fail env c 2 ^^ Tuple.compile_unit env) ^^
             ccall env c "path_pop")
            (fail env c 3 ^^ Tuple.compile_unit env)
        in
        let end_single value =
          let set, get = new_local env "json_single_value" in
          value ^^ set ^^ ccall env c "object_next" ^^
          E.if0 (ccall env c "path_key" ^^ fail env c 3 ^^ ccall env c "path_pop") G.nop ^^ get in
        let body = match typ with
          | Type.Prim Null -> ccall env c "read_null" ^^ Opt.null_lit env
          | Prim Bool -> ccall env c "read_bool"
          | Prim Text -> ccall env c "read_string" ^^ scalar env c ^^ Text.of_ptr_size env
          | Prim (Blob | Principal as p) ->
            c ^^ num (if p = Principal then 1 else 0) ^^ invoke env "read_binary" ^^ scalar env c ^^
            (if p = Principal then Principal.of_ptr_size env else Blob.of_ptr_size env)
          | Prim Char -> ccall env c "read_char" ^^ TaggedSmallWord.msb_adjust Char ^^ TaggedSmallWord.tag env Char
          | Prim (Nat | Int as p) -> c ^^ num (if p = Int then 1 else 0) ^^ invoke env "read_bigint" ^^
            scalar env c ^^ BigNum.of_leb128 env (p = Int)
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let signed, bits = word_kind p in
            c ^^ num (if signed then 1 else 0) ^^ num bits ^^ invoke env "read_word" ^^
            (if bits = 64 then BoxedWord64.box env p else TaggedSmallWord.msb_adjust p ^^ TaggedSmallWord.tag env p)
          | Prim Float -> c ^^ num 64 ^^ invoke env "read_float" ^^ Float.box env
          | Prim Float32 -> c ^^ num 32 ^^ invoke env "read_float" ^^ G.i (Convert (Wasm_exts.Values.F32 F32Op.DemoteF64)) ^^ box_float32 env
          | Opt payload ->
            ccall env c "peek" ^^ num (Char.code 'n') ^^ compile_comparison I64Op.Eq ^^
            E.if1 I64Type (ccall env c "read_null" ^^ Opt.null_lit env)
              (Opt.inject env payload (if Schema.tagged_option payload then
                end_single (only_field "some" (child payload)) else child payload))
          | Tup ts -> count_array (List.length ts) ^^
            G.concat_mapi (fun i typ ->
              (if i = 0 then G.nop else expect ',') ^^
              c ^^ num i ^^ invoke env "path_index" ^^
              child typ ^^ ccall env c "path_pop") ts ^^
            Tuple.from_stack env (List.length ts) ^^ expect ']'
          | Array typ ->
            Arr.tabulate env (ccall env c "array_start") (fun index ->
              let set_element, get_element = new_local env "json_decoded_element" in
              index ^^ compile_eq_const 0L ^^ E.if0 G.nop (expect ',') ^^
              c ^^ index ^^ invoke env "path_index" ^^
              child typ ^^ set_element ^^
              ccall env c "ok" ^^ E.if0 G.nop
                (Tuple.compile_unit env ^^ G.i Return) ^^
              ccall env c "path_pop" ^^ get_element) ^^ expect ']'
          | Non -> fail env c 0 ^^ Tuple.compile_unit env
          | Obj (Object, fs, _) ->
            let fields = List.map (fun f ->
              let set_value, get_value = new_local env ("json_field_" ^ f.Type.lab) in
              let set_seen, get_seen = new_local env ("json_seen_" ^ f.lab) in
              f, set_value, get_value, set_seen, get_seen) fs in
            G.concat_map (fun (f,set,_,_,_) ->
              (match Type.normalize f.Type.typ with Opt _ -> Opt.null_lit env | _ -> Tuple.compile_unit env) ^^ set) fields ^^
            ccall env c "object_start" ^^
            G.loop0 (G.with_current_depth (fun loop ->
              ccall env c "object_next" ^^ E.if0
                (ccall env c "path_key" ^^
                 List.fold_right (fun (f,set,_,set_seen,_) rest ->
                   key_eq env c f.Type.lab ^^ E.if0
                     (child f.typ ^^ set ^^ num 1 ^^ set_seen) rest) fields (ccall env c "skip") ^^
                 ccall env c "path_pop" ^^ G.branch_to_ loop) G.nop)) ^^
            G.concat_map (fun (f,_,_,_,seen) -> match Type.normalize f.Type.typ with
              | Opt _ -> G.nop
              | _ -> seen ^^ E.if0 G.nop (path_field env c f.lab ^^ fail env c 1 ^^ ccall env c "path_pop")) fields ^^
            Object.lit_raw env (List.map (fun (f,_,get,_,_) -> f.Type.lab, (fun () -> get)) fields)
          | Variant fs ->
            end_single (ccall env c "object_start" ^^ ccall env c "object_next" ^^
              E.if1 I64Type
                (ccall env c "path_key" ^^
                 List.fold_right (fun f rest -> key_eq env c f.Type.lab ^^ E.if1 I64Type
                  (Variant.inject env f.lab (child f.typ)) rest) fs
                  (fail env c 2 ^^ Tuple.compile_unit env) ^^
                 ccall env c "path_pop")
                (fail env c 3 ^^ Tuple.compile_unit env))
          | _ -> invalid_arg "JSON unsupported decoder type escaped validation"
        in
        ccall env c "enter" ^^ E.if1 I64Type
          (body ^^ ccall env c "leave") (Tuple.compile_unit env))

  let result env c payload =
    let text_part index () = c ^^ num index ^^ invoke env "error_part" ^^
      c ^^ num (index + 1) ^^ invoke env "error_part" ^^ Text.of_ptr_size env in
    ccall env c "ok" ^^ E.if1 I64Type
      (Variant.inject env "ok" payload)
      (Variant.inject env "err" (Object.lit_raw env [
        "kind", text_part 0; "message", text_part 2; "path", text_part 4;
        "offset", (fun () -> c ^^ num 6 ^^ invoke env "error_part" ^^ BoxedWord64.box env Type.Nat64);
      ]))

  let compile_encode env specialization =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with [typ] -> typ | _ -> assert false in
    let set_value, value = new_local env "json_value" in
    let set_context, c = new_local env "json_context" in
    let set_result, get_result = new_local env "json_result" in
    set_value ^^ num 0 ^^ num 0 ^^ invoke env "new" ^^ set_context ^^
    value ^^ c ^^ encode env typ ^^
    result env c (c ^^ num 0 ^^ invoke env "output_part" ^^ c ^^ num 1 ^^ invoke env "output_part" ^^ Text.of_ptr_size env) ^^
    set_result ^^ ccall env c "done" ^^ get_result

  let compile_decode env specialization =
    let typ = match specialization.Mo_values.Compute_plugin.type_arguments with [typ] -> typ | _ -> assert false in
    let set_source, source = new_local env "json_source_text" in
    let set_input, input = new_local env "json_input" in
    let set_context, c = new_local env "json_context" in
    let set_value, value = new_local env "json_decoded_value" in
    let set_result, get_result = new_local env "json_result" in
    set_source ^^ source ^^ Text.size env ^^ num Schema.max_bytes ^^ compile_comparison I64Op.GtU ^^
    E.if1 I64Type
      (Variant.inject env "err" (Object.lit_raw env [
        "kind", (fun () -> Text.lit env "limit");
        "message", (fun () -> Text.lit env "JSON byte limit exceeded");
        "path", (fun () -> Text.lit env "");
        "offset", (fun () -> num 0 ^^ BoxedWord64.box env Type.Nat64);
      ]))
      (source ^^ Text.to_blob env ^^ set_input ^^
       input ^^ Blob.payload_ptr_unskewed env ^^ input ^^ Blob.len env ^^ invoke env "new" ^^ set_context ^^
       c ^^ decode env typ ^^ set_value ^^ ccall env c "finish" ^^
       result env c value ^^ set_result ^^ ccall env c "done" ^^ get_result)
end

module Encoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module Visitor = Make(B)
    let compile = Visitor.compile_encode
  end
end
module Decoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module Visitor = Make(B)
    let compile = Visitor.compile_decode
  end
end
