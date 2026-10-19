(* Specialized decoder. Leaf visitors are emitted in their parent and fuse the
   runtime's node charge with scalar validation. Fixed-width integer arrays
   borrow one checked contiguous byte range; only compiler SDK constructors
   allocate or write managed values. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types
open Type
module G = InstrList
open G

module Make (B : Plugin_codegen.Backend) = struct
  open B
  module Common = Generator.Make(B)
  open Common

  let box_word env p bits =
    if bits = 64 then BoxedWord64.box env p
    else TaggedSmallWord.msb_adjust p ^^ TaggedSmallWord.tag env p

  let checked env c code =
    let set, get = new_local env "icwire_decoded" in
    code ^^ set ^^ check env c (Tuple.compile_unit env) ^^ get

  let rec decode env typ =
    let typ = Type.normalize typ in
    Func.share_code1 Func.Always env (Generator.name_for "fast_decode" typ)
      ("context", I64Type) [I64Type] (fun env c ->
        let unit = Tuple.compile_unit env in
        let child t = read env c t in
        let body = match typ with
          | Prim _ -> leaf env c typ
          | Opt payload -> checked env c (cc env c "read_bool") ^^ E.if1 I64Type
              (Opt.inject env payload (child payload)) (Opt.null_lit env)
          | Tup ts -> G.concat_map child ts ^^ Tuple.from_stack env (List.length ts)
          | Array t ->
            (match Type.normalize t with
            | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
              let signed, bits = word_kind p in
              let set_count, count = new_local env "icwire_word_count" in
              let set_bytes, bytes = new_local env "icwire_word_bytes" in
              let extension = if signed then SX else ZX in
              let size = match bits with
                | 8 -> Some (Pack8, extension)
                | 16 -> Some (Pack16, extension)
                | 32 -> Some (Pack32, extension)
                | 64 -> None | _ -> assert false in
              c ^^ num bits ^^ invoke env "read_words" ^^ set_count ^^
              check env c unit ^^ c ^^ num 0 ^^ invoke env "scalar_part" ^^ set_bytes ^^
              Arr.tabulate env count (fun index ->
                bytes ^^ index ^^ compile_mul_const (Int64.of_int (bits / 8)) ^^
                G.i (Binary (Wasm_exts.Values.I64 I64Op.Add)) ^^
                G.i (Load {ty = I64Type; align = 0; offset = 0L; sz = size}) ^^
                box_word env p bits)
            | _ -> Arr.tabulate env (checked env c (cc env c "read_array")) (fun _ -> child t))
          | Obj (Object, fields, _) ->
            let set_more, more = new_local env "icwire_more_fields" in
            (* 0 marks end; a live field is its unsigned wire hash plus one.
               Caching it avoids reloading the runtime frame for comparisons. *)
            let step operation = cc env c operation ^^ set_more ^^ check env c unit in
            let has_more = more ^^ num 0 ^^ compile_comparison I64Op.Ne in
            let field_vars = List.map (fun f ->
              let set, get = new_local env ("icwire_field_" ^ f.lab) in f,set,get)
              (Schema.sort_fields fields) in
            cc env c "record_start" ^^ step "record_step" ^^
            G.concat_map (fun (f,set,get) ->
              let id = Int64.succ (Schema.field_id f.lab) in
              G.loop0 (G.with_current_depth (fun loop -> has_more ^^ E.if0
                (more ^^ compile_unboxed_const id ^^ compile_comparison I64Op.LtU ^^
                 E.if0 (step "skip_step" ^^ G.branch_to_ loop) G.nop) G.nop)) ^^
              (match Type.normalize f.typ with Opt _ -> Opt.null_lit env | _ -> unit) ^^ set ^^
              more ^^ compile_eq_const id ^^ E.if0
                (child f.typ ^^ set ^^
                 (match Type.normalize f.typ with Opt _ -> get ^^ Opt.is_some env ^^
                   E.if0 G.nop (fail env c 3) | _ -> G.nop) ^^
                 step "field_step")
                (match Type.normalize f.typ with Opt _ -> G.nop | _ -> fail env c 1 ^^ check env c unit)) field_vars ^^
            G.loop0 (G.with_current_depth (fun loop -> has_more ^^ E.if0
              (step "skip_step" ^^ G.branch_to_ loop) G.nop)) ^^
            Object.lit_raw env (List.map (fun (f,_,get) -> f.lab, (fun () -> get)) field_vars)
          | Variant fields ->
            let tag = checked env c (read_word env c false 32) in
            choose env tag (List.map (fun f -> Schema.field_id f.lab,
              Variant.inject env f.lab (child f.typ)) fields)
              (Some I64Type) (fail env c 2 ^^ unit)
          | Non -> fail env c 0 ^^ unit
          | _ -> invalid_arg "ICWire unsupported decoder type escaped validation"
        in
        match typ with
        | Prim _ -> body
        | _ -> cc env c "enter" ^^ E.if1 I64Type
            (checked env c body ^^ cc env c "leave") unit)

  and read env c typ =
    match Type.normalize typ with
    | Prim _ as typ -> leaf env c typ
    | _ -> checked env c (c ^^ decode env typ)

  and leaf env c = function
    | Prim Null -> cc env c "leaf_null" ^^ check env c (Tuple.compile_unit env) ^^ Opt.null_lit env
    | Prim Bool -> checked env c (cc env c "leaf_bool")
    | Prim (Text | Blob | Principal as p) ->
      c ^^ num (if p = Text then 1 else if p = Principal then 2 else 0) ^^ invoke env "leaf_bytes" ^^
      check env c (Tuple.compile_unit env) ^^ scalar env c ^^
      (if p = Text then Text.of_ptr_size env else if p = Principal then Principal.of_ptr_size env else Blob.of_ptr_size env)
    | Prim Char -> checked env c (cc env c "leaf_char") ^^
      TaggedSmallWord.msb_adjust Char ^^ TaggedSmallWord.tag env Char
    | Prim (Nat | Int as p) ->
      let set, get = new_local env "icwire_small_integer" in
      c ^^ num (if p = Int then 1 else 0) ^^ invoke env "leaf_bigint" ^^ set ^^
      check env c (Tuple.compile_unit env) ^^ get ^^ compile_eq_const Int64.min_int ^^ E.if1 I64Type
        (scalar env c ^^ BigNum.of_leb128 env (p = Int))
        (get ^^ (if p = Int then BigNum.from_signed_word64 env else BigNum.from_word64 env))
    | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
      let signed, bits = word_kind p in
      checked env c (c ^^ num (if signed then 1 else 0) ^^ num bits ^^ invoke env "leaf_word") ^^
      box_word env p bits
    | Prim (Float | Float32 as p) ->
      let set, get, _ = new_local_ env F64Type "icwire_decoded_float" in
      c ^^ num (if p = Float then 64 else 32) ^^ invoke env "leaf_float" ^^ set ^^
      check env c (Tuple.compile_unit env) ^^ get ^^
      (if p = Float then Float.box env else G.i (Convert (Wasm_exts.Values.F32 F32Op.DemoteF64)) ^^ box_float32 env)
    | _ -> invalid_arg "ICWire unsupported scalar decoder type escaped validation"

  let general env typ source =
    let set_context, c = new_local env "icwire_context" in
    let set_value, value = new_local env "icwire_value" in
    let set_result, get_result = new_local env "icwire_result" in
    source ^^ Blob.payload_ptr_unskewed env ^^ source ^^ Blob.len env ^^ invoke env "new" ^^ set_context ^^
      cc env c "read_header" ^^ c ^^ decode env typ ^^ set_value ^^ cc env c "finish" ^^
      result env c value ^^ set_result ^^ cc env c "done" ^^ get_result

  (* A root Blob has no recursive nodes or scalar validation beyond framing.
     Prove the complete successful shape before copying; every invalid shape
     retains the general decoder's precise error and validation precedence. *)
  let root_blob env source otherwise =
    let set_ptr, ptr = new_local env "icwire_root_bytes" in
    let set_len, len = new_local env "icwire_root_length" in
    let load32 offset = ptr ^^ G.i (Load {ty = I64Type; align = 0; offset; sz = Some (Pack32, ZX)}) in
    source ^^ Blob.payload_ptr_unskewed env ^^ set_ptr ^^
    source ^^ Blob.len env ^^ set_len ^^
    len ^^ num 8 ^^ compile_comparison I64Op.GeU ^^
    len ^^ num Schema.max_bytes ^^ compile_comparison I64Op.LeU ^^
    G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^ E.if1 I64Type
      (load32 0L ^^ compile_eq_const 0x31574349L ^^
       load32 4L ^^ len ^^ compile_add_const (-8L) ^^ compile_comparison I64Op.Eq ^^
       G.i (Binary (Wasm_exts.Values.I64 I64Op.And)))
      (num 0) ^^ E.if1 I64Type
      (Variant.inject env "ok" (ptr ^^ compile_add_const 8L ^^ len ^^ compile_add_const (-8L) ^^ Blob.of_ptr_size env))
      otherwise

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.type_arguments with [typ] -> typ | _ -> assert false in
    let set_source, source = new_local env "icwire_source" in
    let fallback = general env typ source in
    let body = match Type.normalize typ with Prim Blob -> root_blob env source fallback | _ -> fallback in
    Plugin_codegen.{representation = Managed; code = G.concat arguments ^^ set_source ^^ body}
end
