module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
open G
open Mo_types
open Wasm_exts.Types

let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidSignature"; "invalidContext"; "invalidRandomness"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

module type Operation = sig
  val name : string
  val inputs : Type.typ list
  val capacity : int
  val boolean : bool
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env _specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("mldsa_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "mldsa_result" in
      let set_status, status = B.new_local env "mldsa_status" in
      let size = num O.capacity in
      let operands = List.map2 (fun typ (_, get) ->
        if typ = Type.blob then get ^^ B.Blob.payload_ptr_unskewed env ^^ get ^^ B.Blob.len env
        else get) O.inputs locals in
      let errors = List.fold_right (fun (number,label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1,"invalidSecretKey"; -2,"invalidPublicKey"; -3,"invalidSignature"; -4,"invalidContext"]
        (B.Variant.inject env "invalidRandomness" (B.Tuple.compile_unit env)) in
      let payload = if O.boolean then status else result in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set,_) -> argument ^^ set) arguments locals) ^^
        (if O.boolean then G.nop else B.alloc_blob env size ^^ set_result) ^^
        G.concat operands ^^
        (if O.boolean then G.nop else result ^^ B.Blob.payload_ptr_unskewed env) ^^
        B.call env "ml-dsa" ("mldsa_" ^ O.name) ^^ set_status ^^
        status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        B.E.if1 I64Type (B.Variant.inject env "err" errors) (B.Variant.inject env "ok" payload)
      }
  end
end

let operation name inputs capacity boolean =
  let module O = struct
    let name = name let inputs = inputs let capacity = capacity
    let boolean = boolean
  end in
  let module Generator = Generate(O) in
  let binding = C.{
    id = "mldsa_" ^ name; name = "mldsa_" ^ name;
    arguments = Fixed (fun _ -> Ok inputs); type_parameters = [];
    result_type = (fun _ _ -> Ok (result_type (if boolean then Type.bool else Type.blob)));
    evaluate = C.pure (Reference.evaluate name);
  } in
  let count = List.fold_left (fun n typ -> n + if typ = Type.blob then 2 else 1) 0 inputs
    + if boolean then 0 else 1 in
  (binding, (module Generator : P.Generator)),
  ("mldsa_" ^ name, List.init count (fun _ -> I64Type), [I64Type])

let () =
  let operations = [
    operation "public_key" [Type.blob] 1312 false;
    operation "sign" [Type.blob; Type.blob; Type.blob] 2420 false;
    operation "sign_randomized" [Type.blob; Type.blob; Type.blob; Type.blob] 2420 false;
    operation "verify" [Type.blob; Type.blob; Type.blob; Type.blob] 0 true;
  ] in
  P.register P.{ abi = 1; name = "ml-dsa"; runtime = Some "runtime.wasm";
    imports = List.map snd operations; bindings = List.map fst operations }
