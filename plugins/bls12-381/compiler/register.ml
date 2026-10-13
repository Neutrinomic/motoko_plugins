module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module T = Mo_types.Type
open Wasm_exts.Types
open Schema
let binding (operation : Schema.operation) =
  let module O = struct let operation = operation end in
  let module Generated = Generator.Operation(O) in
  C.{id="bls12_381_" ^ operation.name; name="bls12_381_" ^ operation.name;
    arguments=Fixed (fun _ -> Ok (Schema.arguments operation));
    type_parameters=[];
    result_type=(fun _ _ -> Ok (Schema.result_type (if operation.boolean then T.bool else T.blob)));
    evaluate=C.pure (Reference.evaluate operation.opcode)},
  (module Generated : P.Generator)
let () = P.register P.{
  abi=1; name="bls12-381"; runtime=Some "runtime.wasm";
  imports=[
    "bls_call", [I32Type; I64Type; I64Type; I64Type; I64Type; I64Type; I64Type; I64Type], [I32Type];
    "bls_aggregate", [I32Type; I64Type; I64Type; I64Type; I64Type; I64Type], [I32Type];
  ];
  bindings=List.map binding Schema.operations;
}
