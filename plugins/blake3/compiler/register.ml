module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
module T = Mo_types.Type
module V = Mo_values.Value
module N = Mo_values.Numerics

let max_output = 16 * 1024 * 1024
let errors = ["invalidKey"; "invalidState"; "outputTooLarge"; "inputTooLong"; "invalidSeek"]
let error_type = T.sum (List.map (fun label -> label, T.Tup []) errors)
let result_type = T.sum ["ok", T.blob; "err", error_type]

type spec = { op : int; name : string; args : T.typ list; checked : bool }
let specs = [
  {op = 0; name = "digest"; args = [T.blob]; checked = false};
  {op = 1; name = "keyed_hash"; args = [T.blob; T.blob]; checked = true};
  {op = 2; name = "derive_key"; args = [T.text; T.blob]; checked = false};
  {op = 3; name = "xof"; args = [T.blob; T.Prim T.Nat64; T.Prim T.Nat32]; checked = true};
  {op = 4; name = "new"; args = []; checked = false};
  {op = 5; name = "new_keyed"; args = [T.blob]; checked = true};
  {op = 6; name = "new_derive_key"; args = [T.text]; checked = false};
  {op = 7; name = "update"; args = [T.blob; T.blob]; checked = true};
  {op = 8; name = "finalize_xof"; args = [T.blob; T.Prim T.Nat64; T.Prim T.Nat32]; checked = true};
]

module Generator (S : sig val spec : spec end) = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let spec = S.spec in
      let const n = B.compile_unboxed_const (Int64.of_int n) in
      let set_a, get_a = B.new_local env "blake3_a" in
      let set_b, get_b = B.new_local env "blake3_b" in
      let set_output, get_output = B.new_local env "blake3_output" in
      let set_status, get_status = B.new_local env "blake3_status" in
      let variable_output = spec.op = 3 || spec.op = 8 in
      let length = if variable_output then
        G.concat [List.nth arguments 2; B.TaggedSmallWord.lsb_adjust T.Nat32]
        else const (if spec.op >= 4 && spec.op <= 7 then 2816 else 32) in
      let seek = if variable_output then
        G.concat [List.nth arguments 1; B.BoxedWord64.unbox env T.Nat64]
        else const 0 in
      let has_a = spec.op <> 4 in
      let has_b = spec.op = 1 || spec.op = 2 || spec.op = 7 in
      let error label = B.Variant.inject env "err"
        (B.Variant.inject env label (B.Tuple.compile_unit env)) in
      let rec error_status n = function
        | [] -> error "invalidState"
        | label :: tail -> G.concat [get_status; const n;
            B.compile_comparison Wasm_exts.Ast.I64Op.Eq;
            B.E.if1 Wasm_exts.Types.I64Type (error label) (error_status (n + 1) tail)] in
      let convert_a = if spec.op = 2 || spec.op = 6 then B.Text.to_blob env else (G.concat []) in
      let inputs = G.concat [
        (if has_a then G.concat [List.hd arguments; convert_a; set_a] else (G.concat []));
        (if has_b then G.concat [List.nth arguments 1; set_b] else (G.concat []));
      ] in
      let ptr_len get = G.concat [get; B.Blob.payload_ptr_unskewed env; get; B.Blob.len env] in
      let output_ptr = G.concat [get_output; B.Blob.payload_ptr_unskewed env] in
      let native_call = match spec.op with
        | 0 -> G.concat [ptr_len get_a; output_ptr; B.call env "blake3" "blake3_digest"]
        | 1 | 2 -> G.concat [ptr_len get_a; ptr_len get_b; output_ptr;
            B.call env "blake3" (if spec.op = 1 then "blake3_keyed_hash" else "blake3_derive_key")]
        | _ -> G.concat [const spec.op;
            (if has_a then ptr_len get_a else G.concat [const 0; const 0]);
            (if has_b then ptr_len get_b else G.concat [const 0; const 0]);
            seek; output_ptr; length; B.call env "blake3" "blake3_run"] in
      let finish = if spec.op = 0 then get_output else G.concat [
        set_status;
        get_status; const 0; B.compile_comparison Wasm_exts.Ast.I64Op.Eq;
        B.E.if1 Wasm_exts.Types.I64Type
          (if spec.checked then B.Variant.inject env "ok" get_output else get_output)
          (if spec.checked then error_status 1 errors
           else B.E.trap_with env "BLAKE3: invalid intrinsic arguments");
      ] in
      let call = G.concat [B.alloc_blob env length; set_output; native_call; finish] in
      let code = if variable_output then G.concat [
        length; const max_output; B.compile_comparison Wasm_exts.Ast.I64Op.GtU;
        B.E.if1 Wasm_exts.Types.I64Type (error "outputTooLarge") call;
      ] else call in
      P.{representation = Managed; code = G.concat [inputs; code]}
  end
end

let binding spec =
  let reference_evaluate _type_arguments _types arguments =
    let parsed = match spec.op, arguments with
      | 0, [V.Blob a] -> Some (a, "", 0L, 32)
      | 1, [V.Blob a; V.Blob b] | 2, [V.Text a; V.Blob b] -> Some (a, b, 0L, 32)
      | (3 | 8), [V.Blob a; V.Nat64 seek; V.Nat32 length] ->
        Some (a, "", N.Int_64.to_int64 (N.Int_64.wrapping_of_big_int (N.Nat64.to_big_int seek)), N.Nat32.to_int length)
      | 4, [] -> Some ("", "", 0L, 2816)
      | 5, [V.Blob a] | 6, [V.Text a] -> Some (a, "", 0L, 2816)
      | 7, [V.Blob a; V.Blob b] -> Some (a, b, 0L, 2816)
      | _ -> None in
    match parsed with
    | None -> Error ("blake3_" ^ spec.name ^ ": unexpected arguments")
    | Some (a, b, seek, length) -> match Reference.run spec.op a b seek length with
      | Ok bytes -> Ok (if spec.checked then V.Variant ("ok", V.Blob bytes) else V.Blob bytes)
      | Error label when spec.checked -> Ok (V.Variant ("err", V.Variant (label, V.unit)))
      | Error label -> Error ("blake3_" ^ spec.name ^ ": " ^ label)
  in
  C.{id = "blake3_" ^ spec.name; name = "blake3_" ^ spec.name;
    arguments = Fixed (fun _ -> Ok spec.args); type_parameters = [];
    result_type = (fun _ _ -> Ok (if spec.checked then result_type else T.blob));
    evaluate = C.pure reference_evaluate;}

let () =
  let bindings = List.map (fun spec ->
    let module S = struct let spec = spec end in
    let module Generated = Generator (S) in
    binding spec, (module Generated : P.Generator)) specs in
  P.register P.{
    abi = 1; name = "blake3"; runtime = Some "runtime.wasm";
    imports = [
      "blake3_run", List.init 8 (fun _ -> Wasm_exts.Types.I64Type), [Wasm_exts.Types.I64Type];
      "blake3_digest", List.init 3 (fun _ -> Wasm_exts.Types.I64Type), [];
      "blake3_keyed_hash", List.init 5 (fun _ -> Wasm_exts.Types.I64Type), [Wasm_exts.Types.I64Type];
      "blake3_derive_key", List.init 5 (fun _ -> Wasm_exts.Types.I64Type), [Wasm_exts.Types.I64Type];
    ];
    bindings;
  }
