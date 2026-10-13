module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
open G
open Mo_types
open Wasm_exts.Types

let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidDigest"; "invalidSalt"; "invalidSignature"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

module type Operation = sig
  val name : string
  val boolean : bool
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env _specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("rsa_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "rsa_result" in
      let set_status, status = B.new_local env "rsa_status" in
      let errors = List.fold_right (fun (number, label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1, "invalidSecretKey"; -2, "invalidPublicKey"; -3, "invalidDigest"; -4, "invalidSalt"]
        (B.Variant.inject env "invalidSignature" (B.Tuple.compile_unit env)) in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set, _) -> argument ^^ set) arguments locals) ^^
        (if O.boolean then G.nop else B.alloc_blob env (num 384) ^^ set_result) ^^
        G.concat (List.map (fun (_, get) ->
          get ^^ B.Blob.payload_ptr_unskewed env ^^ get ^^ B.Blob.len env) locals) ^^
        (if O.boolean then G.nop else result ^^ B.Blob.payload_ptr_unskewed env) ^^
        B.call env "rsa" ("rsa_" ^ O.name) ^^ set_status ^^
        status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        B.E.if1 I64Type (B.Variant.inject env "err" errors)
          (B.Variant.inject env "ok" (if O.boolean then status else result))
      }
  end
end

let operation name arity boolean =
  let module O = struct let name = name let boolean = boolean end in
  let module Generator = Generate(O) in
  let binding = C.{
    id = "rsa_" ^ name; name = "rsa_" ^ name;
    arguments = Fixed (fun _ -> Ok (List.init arity (fun _ -> Type.blob)));
    type_parameters = [];
    result_type = (fun _ _ -> Ok (result_type (if boolean then Type.bool else Type.blob)));
    evaluate = C.pure (Reference.evaluate name);
  } in
  let count = arity * 2 + if boolean then 0 else 1 in
  (binding, (module Generator : P.Generator)),
  ("rsa_" ^ name, List.init count (fun _ -> I64Type), [I64Type])

let () =
  let operations = [
    operation "public_key" 1 false;
    operation "validate_private_key" 1 true;
    operation "validate_public_key" 1 true;
    operation "sign_prehash" 3 false;
    operation "verify_prehash" 3 true;
    operation "sign" 3 false;
    operation "verify" 3 true;
  ] in
  P.register P.{ abi = 1; name = "rsa"; runtime = Some "runtime.wasm";
    imports = List.map snd operations; bindings = List.map fst operations }
