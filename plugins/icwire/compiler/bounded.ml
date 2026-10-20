(* One-pass encoding into a caller-bounded unpublished Blob. Capacity and
   resource admission are fused with writing. Fixed-width skeletons reserve
   their complete span once; failed writes use the diagnostic visitor so that
   eager aggregate admission cannot change the first reported error. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types
open Type
module G = InstrList
open G

module MakeMode (B : Plugin_codegen.Backend)
  (Mode : sig val trap : bool end) = struct
  open B
  module Exact = Encoder.Make(B)
  module Diagnostic = Generator.Make(B)
  let num = Exact.num
  let add = Exact.add
  let sub = Exact.sub
  let max_bytes = Exact.max_bytes
  let max_items = Exact.max_items

  let rec write ?(prepaid = false) ?(dynamic = false) env typ =
    let typ = normalize typ in
    let sharing = match typ with Prim _ | Non -> Func.Never | _ -> Func.Always in
    Func.share_code sharing env (Strm.name_for
      ((if prepaid then "icwire_bounded_paid" else "icwire_bounded") ^
       (if dynamic then "_depth" else "")) [typ])
      (["value", I64Type; "position", I64Type; "end", I64Type; "remaining", I64Type] @
       if dynamic then ["depth", I64Type] else [])
      [I64Type; I64Type] (fun env args ->
        let value, position, end_, remaining = match args with v::p::e::r::_ -> v,p,e,r | _ -> assert false in
        let depth = if dynamic then List.nth args 4 else num 0 in
        let set_position = G.setter_for position in
        let set_remaining = G.setter_for remaining in
        G.block0 (G.with_current_depth (fun exit ->
          let failed = num 0 ^^ set_position ^^ num 0 ^^ set_remaining ^^ G.branch_to_ exit in
          let reject condition = condition ^^ E.if0 failed G.nop in
          let reserve count = reject (count ^^ end_ ^^ position ^^ sub ^^ compile_comparison I64Op.GtU) in
          let charge count =
            reject (count ^^ remaining ^^ compile_comparison I64Op.GtU) ^^
            remaining ^^ count ^^ sub ^^ set_remaining in
          let check_depth width = if dynamic then
            reject (depth ^^ compile_add_const (Int64.of_int width) ^^ num 128 ^^ compile_comparison I64Op.GtU)
            else G.nop in
          let exact t v = v ^^ position ^^ Exact.write env t ^^ set_position ^^
            (if Exact.contains_float t then reject (position ^^ compile_eq_const 0L) else G.nop) in
          let primitive typ value = match typ with
            | Prim (Nat | Int as p) ->
              let set_word, word = new_local env "icwire_bounded_word" in
              let set_length, length = new_local env "icwire_bounded_integer_length" in
              value ^^ BitTagged.if_tagged_scalar env []
                (value ^^ BigNum.to_word64 env ^^ set_word ^^
                 Exact.write_compact ~before_emit:(fun width -> reserve (num width)) env position (p = Int) word)
                (value ^^ BigNumLibtommath.fits_unsigned_bits env 28_672 ^^ E.if0 G.nop failed ^^
                 value ^^ BigNum.leb128_size env (p = Int) ^^ set_length ^^
                 reject (length ^^ num 4096 ^^ compile_comparison I64Op.GtU) ^^ reserve length ^^
                 exact typ value)
            | Prim (Text | Blob | Principal as p) ->
              let set_length, length = new_local env "icwire_bounded_byte_length" in
              value ^^ (if p = Text then Text.size env else Blob.len env) ^^ set_length ^^
              reject (length ^^ num (if p = Principal then 29 else max_bytes) ^^ compile_comparison I64Op.GtU) ^^
              reserve (length ^^ I32Leb.compile_leb128_size length ^^ add) ^^ exact typ value
            | Prim _ ->
              let width = match Exact.fixed_width typ with Some width -> width | None -> assert false in
              reserve (num width) ^^ exact typ value
            | _ -> assert false in
          let child ?(paid = true) ?(depth_checked = false) t v =
            let t = normalize t in
            match t with
            | Prim _ ->
              let set_value, value = new_local env "icwire_bounded_scalar" in
              (if depth_checked then G.nop else check_depth 2) ^^
              (if paid then G.nop else charge (num 1)) ^^
              v ^^ set_value ^^ primitive t value
            | _ ->
              v ^^ position ^^ end_ ^^ remaining ^^
              (if dynamic then depth ^^ compile_add_const 1L else G.nop) ^^
              write ~prepaid:paid ~dynamic env t ^^ set_remaining ^^ set_position ^^
              reject (position ^^ compile_eq_const 0L) in
          let body = match Exact.fixed_width typ with
            | Some width -> check_depth (Exact.schema_depth typ) ^^ reserve (num width) ^^ exact typ value
            | None -> match typ with
              | Prim _ -> primitive typ value
              | Obj (Actor, _, _) -> primitive (Prim Principal) value
              | Func (Shared _, _, _, _, _) ->
                child Schema.actor_reference
                  (value ^^ SharedFunc.principal env) ^^
                child Type.text (value ^^ SharedFunc.method_name env)
              | Opt t -> reserve (num 1) ^^ value ^^ Opt.is_some env ^^ E.if0
                  (Strm.write_byte env position (num 1) ^^ child ~paid:false t (value ^^ Opt.project env t))
                  (Strm.write_byte env position (num 0))
              | Tup ts -> G.concat_mapi (fun index t ->
                  child t (value ^^ Tuple.load_n env (Int64.of_int index))) ts
              | Obj (Object, fields, _) -> G.concat_map (fun f ->
                  child f.typ (value ^^ Object.load env typ f.lab)) (Schema.sort_fields fields)
              | Variant fields -> Diagnostic.choose env (value ^^ Variant.get_variant_tag env)
                  (List.mapi (fun ordinal f -> Variant.hash_variant_label env f.Type.lab,
                    reserve (num (Exact.ordinal_width ordinal)) ^^
                    (if ordinal < 128 then Strm.write_byte env position (num ordinal)
                     else Strm.write_word_leb env position (num ordinal)) ^^
                    child ~paid:false f.typ (value ^^ Variant.project env)) (Schema.sort_fields fields))
                  None failed
              | Array t ->
                let set_length, length = new_local env "icwire_bounded_array_length" in
                let nodes = Exact.required_nodes t in
                value ^^ Arr.len env ^^ set_length ^^
                (if nodes = 1 then G.nop else reject (length ^^ remaining ^^ compile_comparison I64Op.GtU)) ^^
                charge (length ^^ compile_mul_const (Int64.of_int nodes)) ^^
                (match Exact.fixed_width t with
                  | Some width ->
                    length ^^ E.if0 (check_depth (1 + Exact.schema_depth t)) G.nop ^^
                    reserve (I32Leb.compile_leb128_size length ^^ length ^^
                      compile_mul_const (Int64.of_int width) ^^ add) ^^ exact typ value
                  | None ->
                    reserve (I32Leb.compile_leb128_size length) ^^ Strm.write_word_leb env position length ^^
                    let primitive = match normalize t with Prim _ -> true | _ -> false in
                    (if primitive then length ^^ E.if0 (check_depth 2) G.nop else G.nop) ^^
                    Arr.for_each env value length (fun v -> child ~depth_checked:primitive t v))
              | Non -> failed
              | _ -> invalid_arg "ICWire unsupported bounded encoder type" in
          check_depth 1 ^^ (if prepaid then G.nop else charge (num (Exact.required_nodes typ))) ^^ body)) ^^
        position ^^ remaining)

  (* Exact admission is constant-time for these roots. Retaining exact
     allocation avoids reserving a large application cap for a tiny scalar or
     copying a large Blob where no source traversal would have been saved. *)
  let cheap_measure typ = match normalize typ with
    | Prim _ -> true
    | Array t -> Option.is_some (Exact.fixed_width t)
    | t -> Option.is_some (Exact.fixed_width t)

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with [t; _] -> t | _ -> assert false in
    let get_value, get_bound = match arguments with [v;b] -> v,b | _ -> assert false in
    let dynamic = Exact.schema_depth typ > 128 in
    let set_value, value = new_local env "icwire_bounded_value" in
    let set_bound, bound = new_local env "icwire_bounded_source_limit" in
    let set_limit, limit = new_local env "icwire_bounded_limit" in
    let set_blob, blob = new_local env "icwire_bounded_blob" in
    let set_start, start = new_local env "icwire_bounded_start" in
    let set_position, position = new_local env "icwire_bounded_position" in
    let diagnose = value ^^ Diagnostic.compile_encode ~limit ~trap:Mode.trap env specialization in
    let body = if cheap_measure typ then
      let set_size, size = new_local env "icwire_bounded_exact_size" in
      let finish =
        position ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ size ^^ add ^^ compile_comparison I64Op.Eq ^^
        E.else_trap_with env "ICWire bounded output mismatch" ^^
        (if Mode.trap then blob else Variant.inject env "ok" blob) in
      value ^^ num 0 ^^ num max_items ^^ (if dynamic then num 0 else G.nop) ^^
      Exact.measure ~dynamic env typ ^^ G.i Drop ^^ set_size ^^
      size ^^ limit ^^ compile_comparison I64Op.GtU ^^ E.if1 I64Type diagnose
        (alloc_blob env size ^^ set_blob ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ set_position ^^
         value ^^ position ^^ Exact.write env typ ^^ set_position ^^
         (if Exact.contains_float typ then position ^^ compile_eq_const 0L ^^ E.if1 I64Type diagnose
            finish else finish))
      else
        Blob.alloc_unpublished env limit ^^ set_blob ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ set_start ^^
        value ^^ start ^^ start ^^ limit ^^ add ^^ num max_items ^^
        (if dynamic then num 0 else G.nop) ^^ write ~dynamic env typ ^^ G.i Drop ^^ set_position ^^
        position ^^ compile_eq_const 0L ^^ E.if1 I64Type
          (blob ^^ num 0 ^^ Blob.finish env ^^ G.i Drop ^^ diagnose)
          ((if Mode.trap then Fun.id else Variant.inject env "ok")
            (blob ^^ position ^^ start ^^ sub ^^ Blob.finish env)) in
    let code = get_value ^^ set_value ^^ get_bound ^^ set_bound ^^
      bound ^^ BitTagged.if_tagged_scalar env [I64Type]
        (bound ^^ BigNum.to_word64 env)
        (bound ^^ BigNumLibtommath.fits_unsigned_bits env 25 ^^ E.if1 I64Type
          (bound ^^ BigNum.to_word64 env) (num (max_bytes + 1))) ^^ set_limit ^^
      limit ^^ num max_bytes ^^ compile_comparison I64Op.GtU ^^ E.if1 I64Type diagnose body in
    Plugin_codegen.{representation = Managed; code}
end

module Make (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let trap = false end)
module MakeOrTrap (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let trap = true end)
