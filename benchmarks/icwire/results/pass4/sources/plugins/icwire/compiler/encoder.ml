(* The common encoding path measures the source value, allocates its final Blob
   once, and writes through compiler-owned heap/stream helpers. No Rust cursor,
   intermediate byte vector, or per-scalar bridge is involved. Failed preflight
   delegates to the bounded diagnostic visitor to preserve exact error offsets.
   Recursive or exceptionally deep schemas use that visitor directly. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types
open Type
module G = InstrList
open G
module TM = Map.Make (Type.Ord)

module Make (B : Plugin_codegen.Backend) = struct
  open B
  module Diagnostic = Generator.Make(B)
  let num n = compile_unboxed_const (Int64.of_int n)
  let add = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let max_bytes = 16_777_216
  let max_items = 1_000_000
  let bad = max_bytes + 1

  (* A finite schema gives an upper bound on typed value depth, independently
     of array lengths and which optional/variant branches are inhabited. *)
  let bounded_schema typ =
    let memo = ref TM.empty in
    let rec depth typ =
      let typ = normalize typ in
      match TM.find_opt typ !memo with
      | Some n -> n
      | None ->
        memo := TM.add typ 129 !memo;
        let children = match typ with
          | Opt t | Array t -> [t]
          | Tup ts -> ts
          | Obj (Object, fs, _) | Variant fs -> List.map (fun f -> f.typ) fs
          | _ -> [] in
        let n = 1 + List.fold_left (fun n t -> max n (depth t)) 0 children in
        memo := TM.add typ n !memo; n
    in depth typ <= 128

  (* Charge an entire mandatory skeleton once, even when some descendants have
     variable branches. Optional record fields, option payloads, variant arms
     and array elements charge their own skeleton only when inhabited. *)
  let rec required_nodes typ = match normalize typ with
    | Tup ts -> required_sum 1 ts
    | Obj (Object, fs, _) -> List.fold_left (fun total f ->
        match normalize f.typ with
        | Opt _ -> total
        | _ -> min (max_items + 1) (total + 1 + required_nodes f.typ)) 1 fs
    | _ -> 1
  and required_sum initial ts = List.fold_left (fun n t ->
    min (max_items + 1) (n + required_nodes t)) initial ts

  (* Width-only measurement may skip values only when their inhabitants cannot
     fail validation: finite floats still need inspection. *)
  let rec fixed_width typ = match normalize typ with
    | Prim Null -> Some 0
    | Prim (Bool | Nat8 | Int8) -> Some 1
    | Prim (Nat16 | Int16) -> Some 2
    | Prim (Nat32 | Int32 | Char) -> Some 4
    | Prim (Nat64 | Int64) -> Some 8
    | Tup ts -> width_sum 0 ts
    | Obj (Object, fs, _) when not (List.exists (fun f -> match normalize f.typ with Opt _ -> true | _ -> false) fs) ->
      width_sum (4 + 8 * List.length fs) (List.map (fun f -> f.typ) fs)
    | _ -> None
  and width_sum initial ts = List.fold_left (fun total t -> match total, fixed_width t with
    | Some n, Some m when n + m <= max_bytes -> Some (n + m)
    | _ -> None) (Some initial) ts

  let rec measure ?(prepaid = false) env typ =
    let typ = normalize typ in
    let sharing = match typ with Prim _ | Non -> Func.Never | _ -> Func.Always in
    Func.share_code sharing env (Strm.name_for (if prepaid then "icwire_measure_paid" else "icwire_measure") [typ])
      ["value", I64Type; "position", I64Type; "remaining", I64Type]
      [I64Type; I64Type] (fun env args ->
        let value, position, remaining = match args with [v;p;r] -> v,p,r | _ -> assert false in
        let set_position = G.setter_for position in
        let set_remaining = G.setter_for remaining in
        G.block0 (G.with_current_depth (fun exit ->
        let failed = num bad ^^ set_position ^^ num 0 ^^ set_remaining ^^ G.branch_to_ exit in
        let reject condition = condition ^^ E.if0 failed G.nop in
        let charge count =
          reject (count ^^ remaining ^^ compile_comparison I64Op.GtU) ^^
          remaining ^^ count ^^ sub ^^ set_remaining in
        let advance n = position ^^ n ^^ add ^^ set_position in
        let bytes n = advance (num n) in
        let primitive typ value = match typ with
          | Prim Null -> G.nop
          | Prim (Bool | Nat8 | Int8) -> bytes 1
          | Prim (Nat16 | Int16) -> bytes 2
          | Prim (Nat32 | Int32 | Char) -> bytes 4
          | Prim (Nat64 | Int64) -> bytes 8
          | Prim (Float | Float32 as p) ->
            let mask = if p = Float then 0x7ff0000000000000L else 0x7f800000L in
            reject (value ^^ (if p = Float then Float.unbox env ^^
                G.i (Convert (Wasm_exts.Values.I64 I64Op.ReinterpretFloat))
              else unbox_float32 env ^^ G.i (Convert (Wasm_exts.Values.I32 I32Op.ReinterpretFloat)) ^^
                G.i (Convert (Wasm_exts.Values.I64 I64Op.ExtendUI32))) ^^
              compile_unboxed_const mask ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^
              compile_eq_const mask) ^^ bytes (if p = Float then 8 else 4)
          | Prim (Text | Blob | Principal as p) ->
            let set_length, length = new_local env "icwire_length" in
            value ^^ (if p = Text then Text.size env else Blob.len env) ^^ set_length ^^
            reject (length ^^ num (if p = Principal then 29 else max_bytes - 4) ^^ compile_comparison I64Op.GtU) ^^
            advance (length ^^ compile_add_const 4L)
          | Prim (Nat | Int) ->
            let set_length, length = new_local env "icwire_integer_length" in
            value ^^ BitTagged.if_tagged_scalar env [I64Type] (num 1)
              (value ^^ BigNumLibtommath.fits_unsigned_bits env 28_672) ^^
            E.if0 G.nop failed ^^
            value ^^ buffer_size env typ ^^ G.i Drop ^^ set_length ^^
            reject (length ^^ num 4096 ^^ compile_comparison I64Op.GtU) ^^ advance length
          | _ -> assert false in
        let child ?(paid = true) t v =
          let t = normalize t in
          match fixed_width t with
          | Some n ->
            (if paid then G.nop else charge (num (required_nodes t))) ^^ bytes n
          | None -> match t with
            | Prim _ ->
              let set_value, value = new_local env "icwire_scalar" in
              (if paid then G.nop else charge (num 1)) ^^
              v ^^ set_value ^^ primitive t value
            | _ -> v ^^ position ^^ remaining ^^ measure ~prepaid:paid env t ^^
              set_remaining ^^ set_position ^^
              reject (position ^^ num max_bytes ^^ compile_comparison I64Op.GtU) in
        let body = match typ with
          | Prim _ -> primitive typ value
          | Opt t -> bytes 1 ^^ value ^^ Opt.is_some env ^^ E.if0
              (child ~paid:false t (value ^^ Opt.project env t)) G.nop
          | Tup ts -> G.concat_mapi (fun i t -> child t (value ^^ Tuple.load_n env (Int64.of_int i))) ts
          | Obj (Object, fs, _) -> bytes 4 ^^ G.concat_map (fun f ->
              let v = value ^^ Object.load_idx_raw env f.lab in
              let field = bytes 8 ^^ child f.typ v in
              match normalize f.typ with
              | Opt _ -> v ^^ Opt.is_some env ^^ E.if0
                  (charge (num (1 + required_nodes f.typ)) ^^ field) G.nop
              | _ -> field)
              (Schema.sort_fields fs)
          | Variant fs -> bytes 4 ^^ Diagnostic.choose env (value ^^ Variant.get_variant_tag env)
              (List.map (fun f -> Variant.hash_variant_label env f.lab,
                child ~paid:false f.typ (value ^^ Variant.project env)) fs) None failed
          | Array t ->
            let set_length, length = new_local env "icwire_array_length" in
            value ^^ Arr.len env ^^ set_length ^^
            reject (length ^^ remaining ^^ compile_comparison I64Op.GtU) ^^ bytes 4 ^^
            charge (length ^^ compile_mul_const (Int64.of_int (required_nodes t))) ^^
            (match fixed_width t with
              | Some width -> advance (length ^^ compile_mul_const (Int64.of_int width))
              | None -> Arr.for_each env value length (fun v -> child ~paid:true t v ^^
                  reject (position ^^ num max_bytes ^^ compile_comparison I64Op.GtU)))
          | Non -> failed
          | _ -> invalid_arg "ICWire unsupported measure type"
        in
        (if prepaid then G.nop else charge (num (required_nodes typ))) ^^
        body ^^ reject (position ^^ num max_bytes ^^ compile_comparison I64Op.GtU))) ^^
        position ^^ remaining)

  let rec write env typ =
    let typ = normalize typ in
    let sharing = match typ with Prim _ | Non -> Func.Never | _ -> Func.Always in
    Func.share_code sharing env (Strm.name_for "icwire_direct_write" [typ])
      ["value", I64Type; "position", I64Type] [I64Type] (fun env args ->
        let value, position = match args with [v;p] -> v,p | _ -> assert false in
        let set_position = G.setter_for position in
        let child t v = v ^^ position ^^ write env t ^^ set_position in
        let word bits v = match bits with
          | 8 -> Strm.write_byte env position v
          | 32 -> Strm.write_word_32 env position v
          | 16 | 64 -> Strm.reserve env position (Int64.of_int (bits / 8)) ^^ v ^^
            (if bits = 16 then G.i (Convert (Wasm_exts.Values.I32 I32Op.WrapI64)) else G.nop) ^^
            G.i (Store {ty = (if bits = 16 then I32Type else I64Type); align = 0; offset = 0L;
              sz = (if bits = 16 then Some Pack16 else None)})
          | _ -> assert false in
        let framed body =
          let set_start, start = new_local env "icwire_frame_start" in
          position ^^ set_start ^^ position ^^ compile_add_const 4L ^^ set_position ^^
          body ^^ start ^^ position ^^ start ^^ sub ^^ compile_add_const (-4L) ^^
          G.i (Convert (Wasm_exts.Values.I32 I32Op.WrapI64)) ^^
          G.i (Store {ty = I32Type; align = 0; offset = 0L; sz = None}) in
        let body = match typ with
          | Prim Null -> G.nop
          | Prim Bool -> word 8 value
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let _, bits = Diagnostic.word_kind p in
            word bits (value ^^ (if bits = 64 then BoxedWord64.unbox env p else TaggedSmallWord.lsb_adjust p))
          | Prim Char -> word 32 (value ^^ TaggedSmallWord.lsb_adjust_codepoint env)
          | Prim (Float | Float32 as p) ->
            Strm.reserve env position (if p = Float then 8L else 4L) ^^ value ^^
            (if p = Float then Float.unbox env else unbox_float32 env) ^^
            G.i (Store {ty = (if p = Float then F64Type else F32Type); align = 0; offset = 0L; sz = None})
          | Prim (Nat | Int as p) ->
            (if p = Nat then Strm.write_bignum_leb else Strm.write_bignum_sleb) env position value
          | Prim (Blob | Principal) ->
            let set_length, length = new_local env "icwire_length" in
            value ^^ Blob.len env ^^ set_length ^^ word 32 length ^^
            position ^^ value ^^ Blob.payload_ptr_unskewed env ^^ length ^^ G.i MemoryCopy ^^
            position ^^ length ^^ add ^^ set_position
          | Prim Text ->
            (* The SDK text writer flattens ropes directly into the target. Its
               LEB length occupies the final bytes of our reserved u32 prefix;
               overwrite that prefix after the text copy has completed. *)
            let set_length, length = new_local env "icwire_text_length" in
            let set_start, start = new_local env "icwire_text_start" in
            value ^^ Text.size env ^^ set_length ^^ position ^^ set_start ^^
            position ^^ compile_add_const 4L ^^ I32Leb.compile_leb128_size length ^^ sub ^^ set_position ^^
            Strm.write_text env position value ^^
            start ^^ length ^^ G.i (Convert (Wasm_exts.Values.I32 I32Op.WrapI64)) ^^
            G.i (Store {ty = I32Type; align = 0; offset = 0L; sz = None})
          | Opt t -> value ^^ Opt.is_some env ^^ E.if0
              (word 8 (num 1) ^^ child t (value ^^ Opt.project env t)) (word 8 (num 0))
          | Tup ts -> G.concat_mapi (fun i t -> child t (value ^^ Tuple.load_n env (Int64.of_int i))) ts
          | Obj (Object, fs, _) -> framed (G.concat_map (fun f ->
              let v = value ^^ Object.load_idx_raw env f.lab in
              let field = word 32 (compile_unboxed_const (Schema.field_id f.lab)) ^^ framed (child f.typ v) in
              match normalize f.typ with Opt _ -> v ^^ Opt.is_some env ^^ E.if0 field G.nop | _ -> field)
              (Schema.sort_fields fs))
          | Variant fs -> Diagnostic.choose env (value ^^ Variant.get_variant_tag env)
              (List.map (fun f -> Variant.hash_variant_label env f.lab,
                word 32 (compile_unboxed_const (Schema.field_id f.lab)) ^^ child f.typ (value ^^ Variant.project env)) fs)
              None (G.i Unreachable)
          | Array t -> word 32 (value ^^ Arr.len env) ^^
              (if fixed_width t = Some 0 then G.nop else
                Arr.for_each env value (value ^^ Arr.len env) (child t))
          | Non -> G.i Unreachable
          | _ -> invalid_arg "ICWire unsupported direct write type"
        in body ^^ position)

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with [t] -> t | _ -> assert false in
    let code = if not (bounded_schema typ) then
      G.concat arguments ^^ Diagnostic.compile_encode env specialization
    else
      let set_value, value = new_local env "icwire_source_value" in
      let set_size, size = new_local env "icwire_measured_size" in
      let set_blob, blob = new_local env "icwire_final_blob" in
      let set_position, position = new_local env "icwire_final_position" in
      G.concat arguments ^^ set_value ^^
      value ^^ num 4 ^^ num max_items ^^ measure env typ ^^ G.i Drop ^^ set_size ^^
      size ^^ num max_bytes ^^ compile_comparison I64Op.GtU ^^ E.if1 I64Type
        (value ^^ Diagnostic.compile_encode env specialization)
        (alloc_blob env size ^^ set_blob ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ set_position ^^
         Strm.write_word_32 env position (compile_unboxed_const 0x31574349L) ^^
         value ^^ position ^^ write env typ ^^ set_position ^^
         position ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ size ^^ add ^^ compile_comparison I64Op.Eq ^^
         E.else_trap_with env "ICWire measured output mismatch" ^^
         Variant.inject env "ok" blob)
    in Plugin_codegen.{representation = Managed; code}
end
