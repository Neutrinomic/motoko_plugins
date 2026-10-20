module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
open Wasm_exts.Types
open Wasm_exts.Ast

module Generator = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let set_input, get_input = B.new_local env "sha256_input" in
      let set_result, get_result = B.new_local env "sha256_result" in
      let size = G.i (Wasm_exts.Ast.Const Wasm.Source.{
        it = Wasm_exts.Values.I64 32L; at = no_region}) in
      P.{representation = Managed; code = G.concat [G.concat arguments;
        set_input;
        B.alloc_blob env size;
        set_result;
        get_input; B.Blob.payload_ptr_unskewed env;
        get_input; B.Blob.len env;
        get_result; B.Blob.payload_ptr_unskewed env;
        B.call env "sha256" "sha256_digest";
        get_result;
      ]}
  end
end

module Parts_generator = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let set_parts, get_parts = B.new_local env "sha256_parts" in
      let set_count, get_count = B.new_local env "sha256_count" in
      let set_rows, get_rows = B.new_local env "sha256_rows" in
      let set_row, get_row = B.new_local env "sha256_row" in
      let set_part, get_part = B.new_local env "sha256_part" in
      let set_result, get_result = B.new_local env "sha256_result" in
      let store offset value = G.concat [get_row; value;
        G.i (Store {ty = I64Type; align = 0; offset; sz = None})] in
      P.{representation = Managed; code = G.concat [G.concat arguments;
        set_parts; get_parts; B.Arr.len env; set_count;
        (* Descriptor pointers are borrowed only for this synchronous kernel.
           Resolve all array/Blob layouts through the compiler's barriers. *)
        B.alloc_blob env (G.concat [get_count; B.compile_unboxed_const 16L;
          G.i (Binary (Wasm_exts.Values.I64 I64Op.Mul))]); set_rows;
        get_rows; B.Blob.payload_ptr_unskewed env; set_row;
        B.Arr.for_each env get_parts get_count (fun part -> G.concat [
          part; set_part;
          store 0L (G.concat [get_part; B.Blob.payload_ptr_unskewed env]);
          store 8L (G.concat [get_part; B.Blob.len env]);
          get_row; B.compile_add_const 16L; set_row]);
        B.alloc_blob env (B.compile_unboxed_const 32L); set_result;
        get_rows; B.Blob.payload_ptr_unskewed env; get_count;
        get_result; B.Blob.payload_ptr_unskewed env;
        B.call env "sha256" "sha256_digest_parts"; get_result;
      ]}
  end
end

let binding = Mo_values.Compute_plugin.{
  id = "sha256_digest";
  name = "sha256";
  arguments = Fixed (fun _ -> Ok [Mo_types.Type.blob]);
  type_parameters = [];
  result_type = (fun _ _ -> Ok Mo_types.Type.blob);
  evaluate = Mo_values.Compute_plugin.pure (fun _type_arguments _types -> function
    | [Mo_values.Value.Blob bytes] -> Ok (Mo_values.Value.Blob (Sha256_reference.digest bytes))
    | _ -> Error "sha256 expects one Blob argument");
}

let parts_binding = Mo_values.Compute_plugin.{
  id = "sha256_digest_parts";
  name = "sha256_parts";
  arguments = Fixed (fun _ -> Ok [T.Array T.blob]);
  type_parameters = [];
  result_type = (fun _ _ -> Ok T.blob);
  evaluate = Mo_values.Compute_plugin.pure (fun _type_arguments _types -> function
    | [Mo_values.Value.Array parts] ->
      let parts = Array.map (function
        | Mo_values.Value.Blob bytes -> bytes
        | _ -> assert false) parts in
      Ok (Mo_values.Value.Blob
        (Sha256_reference.digest (String.concat "" (Array.to_list parts))))
    | _ -> Error "sha256_parts expects one Blob array argument");
}

let () =
  P.register P.{
    abi = 1; types = [];
    name = "sha256";
    runtime = Some "runtime.wasm";
    imports = [
      "sha256_digest", [I64Type; I64Type; I64Type], [];
      "sha256_digest_parts", [I64Type; I64Type; I64Type], [];
    ];
    bindings = [binding, (module Generator);
      parts_binding, (module Parts_generator)];
  }
