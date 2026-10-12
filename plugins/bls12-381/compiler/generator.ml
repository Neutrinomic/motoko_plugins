module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
open Wasm_exts.Types
open Wasm_exts.Ast
open Schema

module Operation (O : sig val operation : Schema.operation end) = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let op = O.operation in
      let set_output,get_output = B.new_local env "bls_output" in
      let set_status,get_status = B.new_local env "bls_status" in
      let rec error_code index = function
        | [] -> B.Variant.inject env "invalidArgument" (B.Tuple.compile_unit env)
        | label::rest -> G.concat [get_status; B.compile_eq_const (Int64.of_int index);
            B.E.if1 I64Type
              (B.Variant.inject env label (B.Tuple.compile_unit env))
              (error_code (index+1) rest)] in
      let args = List.map (fun argument -> G.concat [argument;
        B.Blob.payload_ptr_unskewed env; argument; B.Blob.len env]) arguments in
      let unused = List.init (3 - op.arity) (fun _ -> G.concat [
        B.compile_unboxed_zero; B.compile_unboxed_zero]) in
      let success = if op.boolean then G.concat [get_output;
        B.Blob.payload_ptr_unskewed env;
        G.i (Wasm_exts.Ast.Load {ty=I32Type; align=0; offset=0L; sz=Some (Pack8,ZX)});
        B.Bool.from_rts_int32]
        else get_output in
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
