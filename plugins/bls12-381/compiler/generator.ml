module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module C = Mo_values.Compute_plugin
module T = Mo_types.Type
open Wasm_exts.Types
open Wasm_exts.Ast
open Schema

module Operation (O : sig val operation : Schema.operation end) = struct
  module Make (B : P.Backend) = struct
    let compile_aggregate env specialization op arguments =
      let keys = List.nth arguments 0 in
      let proofs = if op.opcode = 20 || op.opcode = 21
        then Some (List.nth arguments 1) else None in
      let messages = List.nth arguments (match proofs with None -> 1 | Some _ -> 2) in
      let signature = List.nth arguments (op.arity - 1) in
      let key_payload key = match Schema.prepared_input op.opcode with
        | None -> key
        | Some descriptor ->
          let actual = T.as_array_sub (List.hd specialization.C.argument_types) in
          B.Prepared.unwrap descriptor actual key in
      let set_count, get_count = B.new_local env "bls_count" in
      let set_index, get_index = B.new_local env "bls_index" in
      let set_rows, get_rows = B.new_local env "bls_rows" in
      let set_row, get_row = B.new_local env "bls_row" in
      let set_output, get_output = B.new_local env "bls_output" in
      let set_status, get_status = B.new_local env "bls_status" in
      let error label = B.Variant.inject env "err"
        (B.Variant.inject env label (B.Tuple.compile_unit env)) in
      let rec status_error index = function
        | [] -> error "invalidArgument"
        | label :: rest -> G.concat [get_status; B.compile_eq_const (Int64.of_int index);
            B.E.if1 I64Type (error label) (status_error (index + 1) rest)] in
      let store offset value = G.concat [get_row; value;
        G.i (Store {ty = I64Type; align = 0; offset; sz = None})] in
      let blob offset value =
        let set_blob, get_blob = B.new_local env "bls_row_blob" in
        G.concat [value; set_blob;
          store offset (G.concat [get_blob; B.Blob.payload_ptr_unskewed env]);
          store (Int64.add offset 8L) (G.concat [get_blob; B.Blob.len env])] in
      let indexed array = G.concat [array; get_index; B.Arr.get env] in
      let run = G.concat [
        (* Each fixed-size descriptor borrows Blob bytes for this synchronous call.
           Array and Blob layout/barriers remain entirely compiler-owned. *)
        B.alloc_blob env (G.concat [get_count; B.compile_unboxed_const 48L;
          G.i (Binary (Wasm_exts.Values.I64 I64Op.Mul))]);
        set_rows; get_rows; B.Blob.payload_ptr_unskewed env; set_row;
        B.compile_unboxed_zero; set_index;
        B.Arr.for_each env keys get_count (fun key -> G.concat [
          blob 0L (key_payload key);
          (match proofs with
          | None -> G.concat [store 16L B.compile_unboxed_zero; store 24L B.compile_unboxed_zero]
          | Some proofs -> blob 16L (indexed proofs));
          blob 32L (if Schema.fast_aggregate op.opcode then messages else indexed messages);
          get_index; B.compile_add_const 1L; set_index;
          get_row; B.compile_add_const 48L; set_row]);
        B.alloc_blob env (B.compile_unboxed_const 1L); set_output;
        B.compile_const_32 (Int32.of_int op.opcode);
        get_rows; B.Blob.payload_ptr_unskewed env; get_count;
        signature; B.Blob.payload_ptr_unskewed env; signature; B.Blob.len env;
        get_output; B.Blob.payload_ptr_unskewed env;
        B.call env "bls12-381" "bls_aggregate";
        G.i (Convert (Wasm_exts.Values.I64 I64Op.ExtendUI32)); set_status;
        get_status; B.compile_eq_const 0L;
        B.E.if1 I64Type
          (B.Variant.inject env "ok" (G.concat [get_output;
            B.Blob.payload_ptr_unskewed env;
            G.i (Load {ty = I32Type; align = 0; offset = 0L; sz = Some (Pack8, ZX)});
            B.Bool.from_rts_int32]))
          (status_error 1 Schema.errors)] in
      let arrays = (match proofs with None -> [] | Some proofs -> [proofs]) @
        (if Schema.fast_aggregate op.opcode then [] else [messages]) in
      let checked = G.concat [get_count; B.compile_eq_const 0L;
        B.E.if1 I64Type (error "emptyBatch") (G.concat [
          get_count; B.compile_unboxed_const (if Schema.fast_aggregate op.opcode then 128L else 127L);
          B.compile_comparison I64Op.GtU;
          B.E.if1 I64Type (error "tooManyItems") run])] in
      let checked = List.fold_right (fun array rest -> G.concat [
        get_count; array; B.Arr.len env;
        B.compile_comparison I64Op.Eq;
        B.E.if1 I64Type rest (error "invalidLength")]) arrays checked in
      P.{representation = Managed;
        code = G.concat [keys; B.Arr.len env; set_count; checked]}

    let compile env specialization arguments =
      let op = O.operation in
      if Schema.aggregate op.opcode then compile_aggregate env specialization op arguments else
      let set_output,get_output = B.new_local env "bls_output" in
      let set_status,get_status = B.new_local env "bls_status" in
      let rec error_code index = function
        | [] -> B.Variant.inject env "invalidArgument" (B.Tuple.compile_unit env)
        | label::rest -> G.concat [get_status; B.compile_eq_const (Int64.of_int index);
            B.E.if1 I64Type
              (B.Variant.inject env label (B.Tuple.compile_unit env))
              (error_code (index+1) rest)] in
      let arguments = match Schema.prepared_input op.opcode with
        | None -> arguments
        | Some descriptor -> List.mapi (fun index argument ->
          if index = 0 then B.Prepared.unwrap descriptor
            (List.hd specialization.C.argument_types) argument else argument) arguments in
      let args = List.map (fun argument -> G.concat [argument;
        B.Blob.payload_ptr_unskewed env; argument; B.Blob.len env]) arguments in
      let unused = List.init (3 - op.arity) (fun _ -> G.concat [
        B.compile_unboxed_zero; B.compile_unboxed_zero]) in
      let success = if op.boolean then G.concat [get_output;
        B.Blob.payload_ptr_unskewed env;
        G.i (Wasm_exts.Ast.Load {ty=I32Type; align=0; offset=0L; sz=Some (Pack8,ZX)});
        B.Bool.from_rts_int32]
        else match Schema.prepared_output op.opcode with
          | Some descriptor -> B.Prepared.wrap descriptor get_output
          | None -> get_output in
      P.{representation=Managed; code=G.concat [
        B.alloc_blob env (B.compile_unboxed_const (Int64.of_int op.output_size));
        set_output;
        B.compile_const_32 (Int32.of_int op.opcode);
        G.concat args; G.concat unused;
        get_output; B.Blob.payload_ptr_unskewed env;
        B.call env "bls12-381" "bls_call";
        G.i (Wasm_exts.Ast.Convert (Wasm_exts.Values.I64 Wasm_exts.Ast.I64Op.ExtendUI32));
        set_status; get_status; B.compile_eq_const 0L;
        B.E.if1 I64Type
          (B.Variant.inject env "ok" success)
          (B.Variant.inject env "err" (error_code 1 Schema.errors));
      ]}
  end
end
