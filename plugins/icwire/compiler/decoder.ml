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

module MakeMode (B : Plugin_codegen.Backend)
  (Mode : sig val trap : bool val optional : bool end) = struct
  open B
  module Common = Generator.Make(B)
  open Common

  let success env typ value =
    if Mode.trap then value
    else if Mode.optional then Opt.inject env typ value
    else Variant.inject env "ok" value

  let decoded_result env typ c value =
    if Mode.trap then
      cc env c "ok" ^^
      E.if0 G.nop (cc env c "trap_error" ^^ G.i Unreachable) ^^ value
    else if Mode.optional then
      cc env c "ok" ^^ E.if1 I64Type
        (Opt.inject env typ value) (Opt.null_lit env)
    else result env c value

  let box_word env p bits =
    if bits = 64 then BoxedWord64.box env p
    else TaggedSmallWord.msb_adjust p ^^ TaggedSmallWord.tag env p

  let checked env c code =
    let set, get = new_local env "icwire_decoded" in
    code ^^ set ^^ check env c (Tuple.compile_unit env) ^^ get

  (* The compiler-owned bridge constructs a complete bigint from validated
     LEB bytes in one managed allocation. No temporary arithmetic values or
     plugin-owned assumptions about the managed bigint layout are needed. *)
  let rec decode env static_depth typ =
    let typ = Type.normalize typ in
    Func.share_code1 Func.Always env (Generator.name_for (if static_depth then "flat_decode" else "fast_decode") typ)
      ("context", I64Type) [I64Type] (fun env c ->
        let unit = Tuple.compile_unit env in
        let child t = read env c static_depth t in
        let body = match typ with
          | Prim _ | Obj (Actor, _, _) -> leaf env c typ
          | Func (Shared _, _, _, _, _) ->
            child Schema.actor_reference ^^ child Type.text ^^
            SharedFunc.of_parts env
          | Opt payload -> checked env c (cc env c "read_bool") ^^ E.if1 I64Type
              (Opt.inject env payload (child payload)) (Opt.null_lit env)
          | Tup ts -> G.concat_map child ts ^^ Tuple.from_stack env (List.length ts)
          | Array t ->
            (match Type.normalize t with
            | Prim Bool ->
              let set_count, count = new_local env "icwire_bool_count" in
              let set_bytes, bytes = new_local env "icwire_bool_bytes" in
              cc env c "read_bools" ^^ set_count ^^ check env c unit ^^
              cc env c "scalar_ptr" ^^ set_bytes ^^
              Arr.tabulate env count (fun index ->
                bytes ^^ index ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.Add)) ^^
                G.i (Load {ty = I64Type; align = 0; offset = 0L; sz = Some (Pack8, ZX)}))
            | Prim (Float | Float32 as p) ->
              let bits = if p = Float then 64 else 32 in
              let set_count, count = new_local env "icwire_float_count" in
              let set_bytes, bytes = new_local env "icwire_float_bytes" in
              c ^^ num bits ^^ invoke env "read_floats" ^^ set_count ^^ check env c unit ^^
              cc env c "scalar_ptr" ^^ set_bytes ^^
              Arr.tabulate env count (fun index ->
                bytes ^^ index ^^ compile_mul_const (Int64.of_int (bits / 8)) ^^
                G.i (Binary (Wasm_exts.Values.I64 I64Op.Add)) ^^
                G.i (Load {ty = (if p = Float then F64Type else F32Type); align = 0; offset = 0L; sz = None}) ^^
                (if p = Float then Float.box env else box_float32 env))
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
              check env c unit ^^ cc env c "scalar_ptr" ^^ set_bytes ^^
              Arr.tabulate env count (fun index ->
                bytes ^^ index ^^ compile_mul_const (Int64.of_int (bits / 8)) ^^
                G.i (Binary (Wasm_exts.Values.I64 I64Op.Add)) ^^
                G.i (Load {ty = I64Type; align = 0; offset = 0L; sz = size}) ^^
                box_word env p bits)
            | _ -> Arr.tabulate env (checked env c (cc env c "read_array")) (fun _ -> child t))
          | Obj (Object, fields, _) ->
            Object.lit_raw env (List.map (fun f ->
              f.lab, (fun () -> child f.typ)) (Schema.sort_fields fields))
          | Variant fields ->
            let tag = checked env c (cc env c "read_length") in
            choose env tag (List.mapi (fun index f -> Int64.of_int index,
              Variant.inject env f.lab (child f.typ)) (Schema.sort_fields fields))
              (Some I64Type) (fail env c 2 ^^ unit ^^ G.i Return)
          | Non -> fail env c 0 ^^ unit ^^ G.i Return
          | _ -> invalid_arg "ICWire unsupported decoder type escaped validation"
        in
        match typ with
        | Prim _ | Obj (Actor, _, _) -> body
        | _ -> cc env c (if static_depth then "node" else "enter") ^^ E.if1 I64Type
            (* Every child and tag has already checked its runtime read. Direct
               invalid-variant/None branches return above, so reaching this
               epilogue proves success without another runtime ok call. *)
            (body ^^ (if static_depth then G.nop else cc env c "leave")) unit)

  and read env c static_depth typ =
    match Type.normalize typ with
    | (Prim _ | Obj (Actor, _, _)) as typ -> leaf env c typ
    | _ -> checked env c (c ^^ decode env static_depth typ)

  and leaf env c = function
    | Obj (Actor, _, _) ->
      let set_ptr, ptr = new_local env "icwire_actor_bytes" in
      c ^^ num 2 ^^ invoke env "leaf_bytes" ^^ set_ptr ^^
      ptr ^^ num 0 ^^ compile_comparison I64Op.Ne ^^ E.if0 G.nop
        (Tuple.compile_unit env ^^ G.i Return) ^^
      ptr ^^ cc env c "scalar_len" ^^ Actor.of_ptr_size env
    | Prim Null -> cc env c "leaf_null" ^^ check env c (Tuple.compile_unit env) ^^ Opt.null_lit env
    | Prim Bool -> checked env c (cc env c "leaf_bool")
    | Prim (Text | Blob | Principal as p) ->
      let set_ptr, ptr = new_local env "icwire_scalar_bytes" in
      (if p = Text then cc env c "leaf_text" else c ^^ num (if p = Principal then 2 else 0) ^^ invoke env "leaf_bytes") ^^ set_ptr ^^
      ptr ^^ num 0 ^^ compile_comparison I64Op.Ne ^^ E.if0 G.nop (Tuple.compile_unit env ^^ G.i Return) ^^
      ptr ^^ cc env c "scalar_len" ^^
      (if p = Text then Text.of_ptr_size env else if p = Principal then Principal.of_ptr_size env else Blob.of_ptr_size env)
    | Prim Char -> checked env c (cc env c "leaf_char") ^^
      TaggedSmallWord.msb_adjust Char ^^ TaggedSmallWord.tag env Char
    | Prim (Nat | Int as p) ->
      let set, get = new_local env "icwire_small_integer" in
      c ^^ num (if p = Int then 1 else 0) ^^ invoke env "leaf_bigint" ^^ set ^^
      (* The runtime returns the bigint sentinel on every failed read, so a
         direct word already proves success. Check status only before borrowing
         the fallback bytes; ordinary nested integers need no extra call. *)
      get ^^ compile_eq_const Int64.min_int ^^ E.if1 I64Type
        (check env c (Tuple.compile_unit env) ^^
         cc env c "scalar_ptr" ^^ cc env c "scalar_len" ^^ BigNum.of_leb128 env (p = Int))
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
      c ^^ decode env (Schema.bounded_depth typ) typ ^^ set_value ^^ cc env c "finish" ^^
      decoded_result env typ c value ^^ set_result ^^ cc env c "done" ^^ get_result

  (* A root byte string has no recursive nodes. Prove its complete canonical
     ULEB prefix and exact total size before scalar validation and the SDK copy.
     Invalid shapes use the general decoder's exact validation order. *)
  let root_bytes env source p otherwise =
    let set_ptr, ptr = new_local env "icwire_root_bytes" in
    let set_len, len = new_local env "icwire_root_length" in
    let set_payload, payload = new_local env "icwire_root_payload_length" in
    let binary op = G.i (Binary (Wasm_exts.Values.I64 op)) in
    let expected width =
      let byte index = payload ^^ num (index * 7) ^^ binary I64Op.ShrU ^^
        num 127 ^^ binary I64Op.And ^^
        (if index + 1 < width then num 128 ^^ binary I64Op.Or else G.nop) ^^
        num (index * 8) ^^ binary I64Op.Shl in
      let rec join index = if index = 0 then byte 0
        else join (index - 1) ^^ byte index ^^ binary I64Op.Or in
      join (width - 1) in
    let rec candidate width =
      if width = 5 || (p = Principal && width > 1) then otherwise else
      let minimum = if width = 1 then 0 else 1 lsl (7 * (width - 1)) in
      let maximum = min (if p = Principal then 30 else Schema.max_bytes)
        ((1 lsl (7 * width)) - 1 + width) in
      let data = ptr ^^ num width ^^ binary I64Op.Add in
      let success = success env (Prim p) (data ^^ payload ^^
        (if p = Text then Text.of_ptr_size env else if p = Principal then Principal.of_ptr_size env else Blob.of_ptr_size env)) in
      len ^^ num (minimum + width) ^^ compile_comparison I64Op.GeU ^^
      len ^^ num maximum ^^ compile_comparison I64Op.LeU ^^ binary I64Op.And ^^ E.if1 I64Type
        (len ^^ num width ^^ binary I64Op.Sub ^^ set_payload ^^
         ptr ^^ G.i (Load {ty = I64Type; align = 0; offset = 0L;
           sz = Some ((if width = 1 then Pack8 else if width = 2 then Pack16 else Pack32), ZX)}) ^^
         (if width = 3 then num 0xffffff ^^ binary I64Op.And else G.nop) ^^
         expected width ^^ compile_comparison I64Op.Eq ^^ E.if1 I64Type
           (if p = Text then data ^^ payload ^^ invoke env "utf8_valid" ^^ E.if1 I64Type success otherwise else success)
           otherwise)
        (candidate (width + 1)) in
    source ^^ Blob.payload_ptr_unskewed env ^^ set_ptr ^^
    source ^^ Blob.len env ^^ set_len ^^ candidate 1

  let root_fixed env typ source width validate value otherwise =
    let set_ptr, ptr = new_local env "icwire_root_scalar_bytes" in
    source ^^ Blob.payload_ptr_unskewed env ^^ set_ptr ^^
    source ^^ Blob.len env ^^ num width ^^ compile_comparison I64Op.Eq ^^ E.if1 I64Type
      (validate ptr) (num 0) ^^ E.if1 I64Type
      (success env typ (value ptr)) otherwise

  (* Canonical two-to-nine-byte root integers fit an unboxed 63-bit payload.
     Inspect only ranges proven by the exact Blob length; malformed encodings
     retain the general decoder's validation order and precise first error. *)
  let root_integer_short env source signed otherwise =
    let set_ptr, ptr = new_local env "icwire_root_integer_bytes" in
    let set_packed, packed = new_local env "icwire_root_integer_packed" in
    let set_last, last = new_local env "icwire_root_integer_last" in
    let set_value, value = new_local env "icwire_root_integer_value" in
    let binary op = G.i (Binary (Wasm_exts.Values.I64 op)) in
    let load width offset =
      ptr ^^ G.i (Load {ty = I64Type; align = 0; offset = Int64.of_int offset;
        sz = (match width with 1 -> Some (Pack8, ZX) | 2 -> Some (Pack16, ZX)
          | 4 -> Some (Pack32, ZX) | 8 -> None | _ -> assert false)}) in
    let rec load_packed width offset =
      let chunk = if width >= 8 then 8 else if width >= 4 then 4
        else if width >= 2 then 2 else 1 in
      load chunk offset ^^
      (if width = chunk then G.nop else
        load_packed (width - chunk) (offset + chunk) ^^ num (chunk * 8) ^^
        binary I64Op.Shl ^^ binary I64Op.Or) in
    let mask count =
      let rec loop i bits = if i = count then bits else
        loop (i + 1) (Int64.logor bits (Int64.shift_left 128L (i * 8))) in
      loop 0 0L in
    let width_case width =
      let bytes = min width 8 in
      let rec payload index =
        let group = packed ^^
          (if index = 0 then G.nop else num index ^^ binary I64Op.ShrU) ^^
          compile_unboxed_const (Int64.shift_left 127L (index * 7)) ^^ binary I64Op.And in
        if index = 0 then group else payload (index - 1) ^^ group ^^ binary I64Op.Or in
      let bits = width * 7 in
      let assembled = payload (bytes - 1) ^^
        (if width = 9 then last ^^ num 56 ^^ binary I64Op.Shl ^^ binary I64Op.Or else G.nop) ^^
        (if signed then num (64 - bits) ^^ binary I64Op.Shl ^^
          num (64 - bits) ^^ binary I64Op.ShrS else G.nop) in
      let canonical =
        if signed then
          (* A shortest SLEB of this width lies outside the preceding width's
             signed interval. Unsigned wrapping addition tests both ends. *)
          value ^^ compile_unboxed_const (Int64.shift_left 1L (bits - 8)) ^^
          binary I64Op.Add ^^ compile_unboxed_const (Int64.shift_left 1L (bits - 7)) ^^
          compile_comparison I64Op.GeU
        else value ^^ compile_unboxed_const (Int64.shift_left 1L (bits - 7)) ^^
          compile_comparison I64Op.GeU in
      load_packed bytes 0 ^^ set_packed ^^
      (if width = 9 then load 1 8 ^^ set_last else G.nop) ^^
      packed ^^ compile_unboxed_const (mask bytes) ^^ binary I64Op.And ^^
      compile_unboxed_const (mask (width - 1)) ^^ compile_comparison I64Op.Eq ^^
      (if width = 9 then last ^^ num 128 ^^ compile_comparison I64Op.LtU ^^
        binary I64Op.And else G.nop) ^^
      E.if1 I64Type
        (assembled ^^ set_value ^^ canonical ^^ E.if1 I64Type
          (success env (Prim (if signed then Int else Nat)) (value ^^
            if signed then BigNum.from_signed_word64 env else BigNum.from_word64 env))
          otherwise)
        otherwise in
    source ^^ Blob.payload_ptr_unskewed env ^^ set_ptr ^^
    choose env (source ^^ Blob.len env)
      (List.init 8 (fun index -> let width = index + 2 in
        Int64.of_int width, width_case width)) (Some I64Type) otherwise

  let root_scalar env source p otherwise =
    let load p bits ptr =
      let signed, _ = word_kind p in
      let extension = if signed then SX else ZX in
      let size = match bits with
        | 8 -> Some (Pack8, extension) | 16 -> Some (Pack16, extension)
        | 32 -> Some (Pack32, extension) | 64 -> None | _ -> assert false in
      ptr ^^ G.i (Load {ty = I64Type; align = 0; offset = 0L; sz = size}) in
    let byte ptr = load Nat8 8 ptr in
    match p with
    | Null -> root_fixed env (Prim p) source 0 (fun _ -> num 1) (fun _ -> Opt.null_lit env) otherwise
    | Bool -> root_fixed env (Prim p) source 1
        (fun ptr -> byte ptr ^^ num 1 ^^ compile_comparison I64Op.LeU) byte otherwise
    | Nat | Int -> root_fixed env (Prim p) source 1
        (fun ptr -> byte ptr ^^ num 128 ^^ compile_comparison I64Op.LtU)
        (fun ptr -> byte ptr ^^
          if p = Int then num 57 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.Shl)) ^^
            num 57 ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.ShrS)) ^^ BigNum.from_signed_word64 env
          else BigNum.from_word64 env)
        (root_integer_short env source (p = Int) otherwise)
    | Nat8 | Nat16 | Nat32 | Nat64 | Int8 | Int16 | Int32 | Int64 ->
      let _, bits = word_kind p in
      root_fixed env (Prim p) source (bits / 8) (fun _ -> num 1)
        (fun ptr -> load p bits ptr ^^ box_word env p bits) otherwise
    | Char -> root_fixed env (Prim p) source 4
        (fun ptr -> load Nat32 32 ptr ^^ num 0x10ffff ^^ compile_comparison I64Op.LeU ^^
          load Nat32 32 ptr ^^ num 0xd800 ^^ compile_comparison I64Op.LtU ^^
          load Nat32 32 ptr ^^ num 0xdfff ^^ compile_comparison I64Op.GtU ^^
          G.i (Binary (Wasm_exts.Values.I64 I64Op.Or)) ^^
          G.i (Binary (Wasm_exts.Values.I64 I64Op.And)))
        (fun ptr -> load Nat32 32 ptr ^^ TaggedSmallWord.msb_adjust Char ^^ TaggedSmallWord.tag env Char)
        otherwise
    | Float | Float32 ->
      let bits = if p = Float then 64 else 32 in
      let exponent = if p = Float then 0x7ff0000000000000L else 0x7f800000L in
      root_fixed env (Prim p) source (bits / 8)
        (fun ptr -> load (if p = Float then Nat64 else Nat32) bits ptr ^^
          compile_unboxed_const exponent ^^ G.i (Binary (Wasm_exts.Values.I64 I64Op.And)) ^^
          compile_unboxed_const exponent ^^ compile_comparison I64Op.Ne)
        (fun ptr -> ptr ^^ G.i (Load {ty = (if p = Float then F64Type else F32Type); align = 0; offset = 0L; sz = None}) ^^
          (if p = Float then Float.box env else box_float32 env)) otherwise
    | _ -> otherwise

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.type_arguments with [typ] -> typ | _ -> assert false in
    let set_source, source = new_local env "icwire_source" in
    let fallback = general env typ source in
    let body = match Type.normalize typ with
      | Prim (Blob | Text | Principal as p) -> root_bytes env source p fallback
      | Prim p -> root_scalar env source p fallback
      | _ -> fallback in
    Plugin_codegen.{representation = Managed; code = G.concat arguments ^^ set_source ^^ body}
end

module Make (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let trap = false let optional = false end)
module MakeOrTrap (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let trap = true let optional = false end)

module MakeOptional (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let trap = false let optional = true end)
