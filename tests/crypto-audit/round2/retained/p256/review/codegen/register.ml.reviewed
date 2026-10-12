module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
open G
open Mo_types
open Wasm_exts.Types

let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidDigest"; "invalidSignature"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

module type Operation = sig
  val name : string
  val inputs : Type.typ list
  val capacity : int
  val boolean : bool
  val compressed : bool
  val variable : bool
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env _specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("p256_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "p256_result" in
      let set_status, status = B.new_local env "p256_status" in
      let size = if O.compressed then
        snd (List.nth locals 1) ^^ B.E.if1 I64Type (num 33) (num 65)
        else num O.capacity in
      let operands = List.map2 (fun typ (_, get) ->
        if typ = Type.blob then get ^^ B.Blob.payload_ptr_unskewed env ^^ get ^^ B.Blob.len env
        else get) O.inputs locals in
      let errors = List.fold_right (fun (number,label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1,"invalidSecretKey"; -2,"invalidPublicKey"; -3,"invalidDigest"]
        (B.Variant.inject env "invalidSignature" (B.Tuple.compile_unit env)) in
      let payload = if O.boolean then status
        else if O.variable then status ^^ B.compile_eq_const (Int64.of_int O.capacity) ^^
          B.E.if1 I64Type result
            (result ^^ B.Blob.payload_ptr_unskewed env ^^ status ^^ B.Blob.of_ptr_size env)
        else result in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set,_) -> argument ^^ set) arguments locals) ^^
        (if O.boolean then G.nop else B.alloc_blob env size ^^ set_result) ^^
        G.concat operands ^^
        (if O.boolean then G.nop else result ^^ B.Blob.payload_ptr_unskewed env) ^^
        B.call env "p256" ("p256_" ^ O.name) ^^ set_status ^^
        status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        B.E.if1 I64Type (B.Variant.inject env "err" errors) (B.Variant.inject env "ok" payload)
      }
  end
end

let operation name inputs capacity boolean compressed variable =
  let module O = struct
    let name = name let inputs = inputs let capacity = capacity
    let boolean = boolean let compressed = compressed let variable = variable
  end in
  let module Generator = Generate(O) in
  let binding = C.{
    id = "p256_" ^ name; name = "p256_" ^ name;
    arguments = Fixed (fun _ -> Ok inputs); type_parameters = [];
    result_type = (fun _ _ -> Ok (result_type (if boolean then Type.bool else Type.blob)));
    evaluate = C.pure (Reference.evaluate name);
  } in
  let count = List.fold_left (fun n typ -> n + if typ = Type.blob then 2 else 1) 0 inputs
    + if boolean then 0 else 1 in
  (binding, (module Generator : P.Generator)),
  ("p256_" ^ name, List.init count (fun _ -> I64Type), [I64Type])

let () =
  let operations = [
    operation "public_key" [Type.blob; Type.bool] 65 false true false;
    operation "convert_public_key" [Type.blob; Type.bool] 65 false true false;
    operation "sign_prehash" [Type.blob; Type.blob] 64 false false false;
    operation "verify_prehash" [Type.blob; Type.blob; Type.blob] 0 true false false;
    operation "signature_to_der" [Type.blob] 72 false false true;
    operation "signature_from_der" [Type.blob] 64 false false false;
    operation "normalize_signature" [Type.blob] 64 false false false;
  ] in
  P.register P.{ abi = 1; name = "p256"; runtime = Some "runtime.wasm";
    imports = List.map snd operations; bindings = List.map fst operations }
