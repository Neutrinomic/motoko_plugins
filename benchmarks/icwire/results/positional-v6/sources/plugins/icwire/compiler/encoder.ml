(* The common encoding path measures the source value, allocates its final Blob
   once, and writes through compiler-owned heap/stream helpers. No Rust cursor,
   intermediate byte vector, or per-scalar bridge is involved. Failed preflight
   delegates to the bounded diagnostic visitor to preserve exact error offsets.
   Finite floats are checked while writing, avoiding a second unbox/array scan;
   a failed write discards the unpublished Blob and runs that same visitor.
   Recursive schemas carry a depth counter during measurement only. *)
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
  let schema_depth typ =
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
    in depth typ

  (* Charge an entire mandatory skeleton once. Option payloads, variant arms
     and array elements charge their own skeleton only when inhabited. *)
  let rec required_nodes ?(seen = TM.empty) typ =
    let typ = normalize typ in
    if TM.mem typ seen then max_items + 1 else
    let seen = TM.add typ () seen in
    match typ with
    | Tup ts -> required_sum seen 1 ts
    | Obj (Object, fs, _) -> required_sum seen 1 (List.map (fun f -> f.typ) fs)
    | _ -> 1
  and required_sum seen initial ts = List.fold_left (fun n t ->
    min (max_items + 1) (n + required_nodes ~seen t)) initial ts

  let contains_float typ =
    let seen = ref TM.empty in
    let rec visit typ =
      let typ = normalize typ in
      if TM.mem typ !seen then false else begin
        seen := TM.add typ () !seen;
        match typ with
        | Prim (Float | Float32) -> true
        | Opt t | Array t -> visit t
        | Tup ts -> List.exists visit ts
        | Obj (Object, fs, _) | Variant fs -> List.exists (fun f -> visit f.typ) fs
        | _ -> false
      end
    in visit typ

  (* Fixed-width floats need no size traversal: their finite-value validation
     happens during writing, before any output Blob can escape. *)
  let rec fixed_width ?(seen = TM.empty) typ =
    let typ = normalize typ in
    if TM.mem typ seen then None else
    let seen = TM.add typ () seen in
    match typ with
    | Prim Null -> Some 0
    | Prim (Bool | Nat8 | Int8) -> Some 1
    | Prim (Nat16 | Int16) -> Some 2
    | Prim (Nat32 | Int32 | Char | Float32) -> Some 4
    | Prim (Nat64 | Int64 | Float) -> Some 8
    | Tup ts -> width_sum seen 0 ts
    | Obj (Object, fs, _) -> width_sum seen 0 (List.map (fun f -> f.typ) fs)
    | _ -> None
  and width_sum seen initial ts = List.fold_left (fun total t -> match total, fixed_width ~seen t with
    | Some n, Some m when n + m <= max_bytes -> Some (n + m)
    | _ -> None) (Some initial) ts

  let rec ordinal_width n = if n < 128 then 1 else 1 + ordinal_width (n lsr 7)

  (* Compact integers need neither an RTS loop nor a second size calculation.
     Choose their minimal LEB width, then fill fixed groups directly. Packing
     up to eight output bytes per store trades generated code for instructions;
     managed values still pass only through the SDK's scalar/word adapters. *)
  let write_compact env position signed word =
    let initialize_key, key = if signed then
      let set, get = new_local env "icwire_signed_width_key" in
      word ^^ compile_mul_const 2L ^^ word ^^
      G.i (Binary (Wasm_exts.Values.I64 I64Op.Xor)) ^^ set, get
      else G.nop, word in
    let emit width =
      let rec chunks start remaining =
        if remaining = 0 then G.nop else
        let count = if remaining >= 8 then 8 else if remaining >= 4 then 4 else if remaining >= 2 then 2 else 1 in
        let payload = G.concat_mapi (fun index _ ->
          let shift = 7 * (start + index) in
          word ^^ (if shift = 0 then G.nop else num shift ^^
            G.i (Binary (Wasm_exts.Values.I64 (if signed then I64Op.ShrS else I64Op.ShrU)))) ^^
          num 127 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^
          (if index = 0 then G.nop else num (8 * index) ^^
            G.i (Binary (Wasm_exts.Values.I64 I64Op.Shl)) ^^
            G.i (Binary (Wasm_exts.Values.I64 I64Op.Or)))) (List.init count Fun.id) in
        let continuation = List.fold_left (fun mask index ->
          if start + index = width - 1 then mask else
            Int64.logor mask (Int64.shift_left 0x80L (8 * index))) 0L (List.init count Fun.id) in
        position ^^ payload ^^
        (if continuation = 0L then G.nop else compile_unboxed_const continuation ^^
          G.i (Binary (Wasm_exts.Values.I64 I64Op.Or))) ^^
        (if count = 8 then G.nop else G.i (Convert (Wasm_exts.Values.I32 I32Op.WrapI64))) ^^
        G.i (Store {ty = (if count = 8 then I64Type else I32Type); align = 0;
          offset = Int64.of_int start; sz = (if count = 1 then Some Pack8 else if count = 2 then Some Pack16 else None)}) ^^
        chunks (start + count) (remaining - count)
      in chunks 0 width ^^ position ^^ compile_add_const (Int64.of_int width) ^^ G.setter_for position in
    let rec select first last =
      if first = last then emit first else
      let middle = first + (last - first) / 2 in
      key ^^ compile_unboxed_const (Int64.shift_left 1L (7 * middle)) ^^ compile_comparison I64Op.LtU ^^
      E.if0 (select first middle) (select (middle + 1) last) in
    initialize_key ^^ key ^^ num 128 ^^ compile_comparison I64Op.LtU ^^
    E.if0 (emit 1)
      (key ^^ num 16_384 ^^ compile_comparison I64Op.LtU ^^
       E.if0 (emit 2) (select 3 10))

  let rec measure ?(prepaid = false) ?(dynamic = false) env typ =
    let typ = normalize typ in
    let sharing = match typ with Prim _ | Non -> Func.Never | _ -> Func.Always in
    Func.share_code sharing env (Strm.name_for
      ((if prepaid then "icwire_measure_paid" else "icwire_measure") ^ (if dynamic then "_depth" else "")) [typ])
      (["value", I64Type; "position", I64Type; "remaining", I64Type] @
       if dynamic then ["depth", I64Type] else [])
      [I64Type; I64Type] (fun env args ->
        let value, position, remaining = match args with v::p::r::_ -> v,p,r | _ -> assert false in
        let depth = if dynamic then List.nth args 3 else num 0 in
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
        let check_depth width = if dynamic then
          reject (depth ^^ compile_add_const (Int64.of_int width) ^^ num 128 ^^ compile_comparison I64Op.GtU)
          else G.nop in
        let primitive typ value = match typ with
          | Prim Null -> G.nop
          | Prim (Bool | Nat8 | Int8) -> bytes 1
          | Prim (Nat16 | Int16) -> bytes 2
          | Prim (Nat32 | Int32 | Char) -> bytes 4
          | Prim (Nat64 | Int64) -> bytes 8
          | Prim (Float | Float32 as p) -> bytes (if p = Float then 8 else 4)
          | Prim (Text | Blob | Principal as p) ->
            let set_length, length = new_local env "icwire_length" in
            value ^^ (if p = Text then Text.size env else Blob.len env) ^^ set_length ^^
            reject (length ^^ num (if p = Principal then 29 else max_bytes) ^^ compile_comparison I64Op.GtU) ^^
            advance (length ^^ I32Leb.compile_leb128_size length ^^ add)
          | Prim (Nat | Int as p) ->
            let set_word, word = new_local env "icwire_integer_word" in
            let set_length, length = new_local env "icwire_integer_length" in
            value ^^ BitTagged.if_tagged_scalar env []
              (value ^^ BigNum.to_word64 env ^^ set_word ^^
               (* The leading significant bit of (x << 1) xor x is the sign
                  transition used by SLEB. Its unsigned LEB width therefore
                  equals x's signed width, including zero and minus one. *)
               (if p = Int then word ^^ compile_mul_const 2L ^^ word ^^
                  G.i (Binary (Wasm_exts.Values.I64 I64Op.Xor)) ^^ set_word else G.nop) ^^
               advance (I32Leb.compile_leb128_size word))
              (value ^^ BigNumLibtommath.fits_unsigned_bits env 28_672 ^^
               E.if0 G.nop failed ^^
               value ^^ buffer_size env typ ^^ G.i Drop ^^ set_length ^^
               (* The magnitude precheck already proves Nat's ULEB <= 4096.
                  Int may still need an additional sign bit at that boundary. *)
               (if p = Nat then G.nop else reject (length ^^ num 4096 ^^ compile_comparison I64Op.GtU)) ^^
               advance length)
          | _ -> assert false in
        let child ?(paid = true) ?(depth_checked = false) t v =
          let t = normalize t in
          match fixed_width t with
          | Some n ->
            (if depth_checked then G.nop else check_depth (1 + schema_depth t)) ^^
            (if paid then G.nop else charge (num (required_nodes t))) ^^ bytes n
          | None -> match t with
            | Prim _ ->
              let set_value, value = new_local env "icwire_scalar" in
              (if depth_checked then G.nop else check_depth 2) ^^ (if paid then G.nop else charge (num 1)) ^^
              v ^^ set_value ^^ primitive t value
            | _ -> v ^^ position ^^ remaining ^^
              (if dynamic then depth ^^ compile_add_const 1L else G.nop) ^^
              measure ~prepaid:paid ~dynamic env t ^^
              set_remaining ^^ set_position ^^
              reject (position ^^ num max_bytes ^^ compile_comparison I64Op.GtU) in
        let body = match typ with
          | Prim _ -> primitive typ value
          | Opt t -> bytes 1 ^^ value ^^ Opt.is_some env ^^ E.if0
              (child ~paid:false t (value ^^ Opt.project env t)) G.nop
          | Tup ts -> G.concat_mapi (fun i t -> child t (value ^^ Tuple.load_n env (Int64.of_int i))) ts
          | Obj (Object, fs, _) -> G.concat_map (fun f ->
              child f.typ (value ^^ Object.load_idx_raw env f.lab))
              (Schema.sort_fields fs)
          | Variant fs -> Diagnostic.choose env (value ^^ Variant.get_variant_tag env)
              (List.mapi (fun index f -> Variant.hash_variant_label env f.lab,
                bytes (ordinal_width index) ^^ child ~paid:false f.typ (value ^^ Variant.project env))
                (Schema.sort_fields fs)) None failed
          | Array t ->
            let set_length, length = new_local env "icwire_array_length" in
            let nodes = required_nodes t in
            value ^^ Arr.len env ^^ set_length ^^
            (* For one-node elements charge itself checks the count. Larger
               skeletons need this first bound before multiplying the count. *)
            (if nodes = 1 then G.nop else reject (length ^^ remaining ^^ compile_comparison I64Op.GtU)) ^^
            advance (I32Leb.compile_leb128_size length) ^^
            charge (length ^^ compile_mul_const (Int64.of_int nodes)) ^^
            (match fixed_width t with
              | Some width -> length ^^ E.if0 (check_depth (1 + schema_depth t)) G.nop ^^
                  advance (length ^^ compile_mul_const (Int64.of_int width))
              | None ->
                let primitive = match normalize t with Prim _ -> true | _ -> false in
                (if primitive then length ^^ E.if0 (check_depth 2) G.nop else G.nop) ^^
                (* Scalar lengths are individually bounded and count <= 1m,
                   so their sum fits i64. Check the byte cap once at the array
                   boundary. Composite children check their own boundaries. *)
                Arr.for_each env value length (fun v -> child ~paid:true ~depth_checked:primitive t v))
          | Non -> failed
          | _ -> invalid_arg "ICWire unsupported measure type"
        in
        check_depth 1 ^^ (if prepaid then G.nop else charge (num (required_nodes typ))) ^^
        body ^^ reject (position ^^ num max_bytes ^^ compile_comparison I64Op.GtU))) ^^
        position ^^ remaining)

  let rec write env typ =
    let typ = normalize typ in
    let sharing = match typ with Prim _ | Non -> Func.Never | _ -> Func.Always in
    Func.share_code sharing env (Strm.name_for "icwire_direct_write" [typ])
      ["value", I64Type; "position", I64Type] [I64Type] (fun env args ->
        let value, position = match args with [v;p] -> v,p | _ -> assert false in
        let set_position = G.setter_for position in
        let emit_body failed =
        let reject condition = condition ^^ E.if0 failed G.nop in
        let word bits v = match bits with
          | 8 -> Strm.write_byte env position v
          | 32 -> Strm.write_word_32 env position v
          | 16 | 64 -> Strm.reserve env position (Int64.of_int (bits / 8)) ^^ v ^^
            (if bits = 16 then G.i (Convert (Wasm_exts.Values.I32 I32Op.WrapI64)) else G.nop) ^^
            G.i (Store {ty = (if bits = 16 then I32Type else I64Type); align = 0; offset = 0L;
              sz = (if bits = 16 then Some Pack16 else None)})
          | _ -> assert false in
        let primitive typ value = match typ with
          | Prim Null -> G.nop
          | Prim Bool -> word 8 value
          | Prim (Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 as p) ->
            let _, bits = Diagnostic.word_kind p in
            word bits (value ^^ (if bits = 64 then BoxedWord64.unbox env p else TaggedSmallWord.lsb_adjust p))
          | Prim Char -> word 32 (value ^^ TaggedSmallWord.lsb_adjust_codepoint env)
          | Prim (Float | Float32 as p) ->
            let float_type = if p = Float then F64Type else F32Type in
            let set_float, float, _ = new_local_ env float_type "icwire_float" in
            let mask = if p = Float then 0x7ff0000000000000L else 0x7f800000L in
            value ^^ (if p = Float then Float.unbox env else unbox_float32 env) ^^ set_float ^^
            reject (float ^^ (if p = Float then
                G.i (Convert (Wasm_exts.Values.I64 I64Op.ReinterpretFloat))
              else G.i (Convert (Wasm_exts.Values.I32 I32Op.ReinterpretFloat)) ^^
                G.i (Convert (Wasm_exts.Values.I64 I64Op.ExtendUI32))) ^^
              compile_unboxed_const mask ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^
              compile_eq_const mask) ^^
            Strm.reserve env position (if p = Float then 8L else 4L) ^^ float ^^
            G.i (Store {ty = (if p = Float then F64Type else F32Type); align = 0; offset = 0L; sz = None})
          | Prim (Nat | Int as p) ->
            let set_word, word = new_local env "icwire_integer_word" in
            value ^^ BitTagged.if_tagged_scalar env []
              (value ^^ BigNum.to_word64 env ^^ set_word ^^ write_compact env position (p = Int) word)
              ((if p = Nat then Strm.write_bignum_leb else Strm.write_bignum_sleb) env position value)
          | Prim (Blob | Principal) -> Strm.write_blob env position value
          | Prim Text -> Strm.write_text env position value
          | _ -> assert false in
        let child t v = match normalize t with
          | Prim Null -> G.nop
          | Prim _ as t ->
            let set_value, value = new_local env "icwire_scalar" in
            v ^^ set_value ^^ primitive t value
          | _ -> v ^^ position ^^ write env t ^^ set_position ^^
              (if contains_float t then reject (position ^^ compile_eq_const 0L) else G.nop) in
        let body = match typ with
          | Prim _ -> primitive typ value
          | Opt t -> value ^^ Opt.is_some env ^^ E.if0
              (word 8 (num 1) ^^ child t (value ^^ Opt.project env t)) (word 8 (num 0))
          | Tup ts -> G.concat_mapi (fun i t -> child t (value ^^ Tuple.load_n env (Int64.of_int i))) ts
          | Obj (Object, fs, _) -> G.concat_map (fun f ->
              child f.typ (value ^^ Object.load_idx_raw env f.lab)) (Schema.sort_fields fs)
          | Variant fs -> Diagnostic.choose env (value ^^ Variant.get_variant_tag env)
              (List.mapi (fun index f -> Variant.hash_variant_label env f.lab,
                (if index < 128 then word 8 (num index) else Strm.write_word_leb env position (num index)) ^^
                child f.typ (value ^^ Variant.project env)) (Schema.sort_fields fs))
              None (G.i Unreachable)
          | Array t -> Strm.write_word_leb env position (value ^^ Arr.len env) ^^
              (if fixed_width t = Some 0 then G.nop else
                Arr.for_each env value (value ^^ Arr.len env) (child t))
          | Non -> G.i Unreachable
          | _ -> invalid_arg "ICWire unsupported direct write type"
        in body in
        (if contains_float typ then
          G.block0 (G.with_current_depth (fun exit ->
            (* Zero is a private failure sentinel, never a Blob payload address. *)
            emit_body (num 0 ^^ set_position ^^ G.branch_to_ exit)))
         else emit_body (G.i Unreachable)) ^^ position)

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with [t] -> t | _ -> assert false in
    let dynamic = schema_depth typ > 128 in
    let code =
      let set_value, value = new_local env "icwire_source_value" in
      let set_size, size = new_local env "icwire_measured_size" in
      let set_blob, blob = new_local env "icwire_final_blob" in
      let set_position, position = new_local env "icwire_final_position" in
      let finish =
        position ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ size ^^ add ^^ compile_comparison I64Op.Eq ^^
        E.else_trap_with env "ICWire measured output mismatch" ^^
        Variant.inject env "ok" blob in
      G.concat arguments ^^ set_value ^^
      value ^^ num 0 ^^ num max_items ^^ (if dynamic then num 0 else G.nop) ^^
      measure ~dynamic env typ ^^ G.i Drop ^^ set_size ^^
      size ^^ num max_bytes ^^ compile_comparison I64Op.GtU ^^ E.if1 I64Type
        (value ^^ Diagnostic.compile_encode env specialization)
        (alloc_blob env size ^^ set_blob ^^ blob ^^ Blob.payload_ptr_unskewed env ^^ set_position ^^
         value ^^ position ^^ write env typ ^^ set_position ^^
         (if contains_float typ then position ^^ compile_eq_const 0L ^^ E.if1 I64Type
            (value ^^ Diagnostic.compile_encode env specialization) finish
          else finish))
    in Plugin_codegen.{representation = Managed; code}
end
