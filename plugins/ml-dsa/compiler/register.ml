module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
open G
open Mo_types
open Wasm_exts.Types

let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidSignature"; "invalidContext"; "invalidRandomness"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

type input = Blob | Prepared of C.Prepared.t
type output = Boolean | Bytes of int | Handle of C.Prepared.t * int
let input_type = function Blob -> Type.blob | Prepared descriptor -> C.Prepared.typ descriptor
let output_type = function
  | Boolean -> Type.bool | Bytes _ -> Type.blob
  | Handle (descriptor, _) -> C.Prepared.typ descriptor
let capacity = function Boolean -> None | Bytes size | Handle (_, size) -> Some size

module type Operation = sig
  val name : string
  val inputs : input list
  val output : output
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("mldsa_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "mldsa_result" in
      let set_status, status = B.new_local env "mldsa_status" in
      let operands = List.map2 (fun (input, actual_type) (_, get) ->
        match input with
        | Blob -> get ^^ B.Blob.payload_ptr_unskewed env ^^ get ^^ B.Blob.len env
        | Prepared descriptor ->
          B.Prepared.unwrap descriptor actual_type get ^^ B.Blob.payload_ptr_unskewed env)
        (List.combine O.inputs specialization.C.argument_types) locals in
      let errors = List.fold_right (fun (number,label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1,"invalidSecretKey"; -2,"invalidPublicKey"; -3,"invalidSignature"; -4,"invalidContext"]
        (B.Variant.inject env "invalidRandomness" (B.Tuple.compile_unit env)) in
      let payload = match O.output with
        | Boolean -> status | Bytes _ -> result
        | Handle (descriptor, _) -> B.Prepared.wrap descriptor result in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set,_) -> argument ^^ set) arguments locals) ^^
        (match capacity O.output with None -> G.nop | Some size -> B.alloc_blob env (num size) ^^ set_result) ^^
        G.concat operands ^^
        (match capacity O.output with None -> G.nop | Some _ -> result ^^ B.Blob.payload_ptr_unskewed env) ^^
        B.call env "ml-dsa" ("mldsa_" ^ O.name) ^^ set_status ^^
        status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        B.E.if1 I64Type (B.Variant.inject env "err" errors) (B.Variant.inject env "ok" payload)
      }
  end
end

let operation name inputs output =
  let module O = struct let name = name let inputs = inputs let output = output end in
  let module Generator = Generate(O) in
  let binding = C.{
    id = "mldsa_" ^ name; name = "mldsa_" ^ name;
    arguments = Fixed (fun _ -> Ok (List.map input_type inputs)); type_parameters = [];
    result_type = (fun _ _ -> Ok (result_type (output_type output)));
    evaluate = C.pure (Reference.evaluate name);
  } in
  let count = List.fold_left (fun n input -> n + (match input with Blob -> 2 | Prepared _ -> 1)) 0 inputs
    + (match capacity output with None -> 0 | Some _ -> 1) in
  (binding, (module Generator : P.Generator)),
  ("mldsa_" ^ name, List.init count (fun _ -> I64Type), [I64Type])

let () =
  let public = Prepared_types.public_key and secret = Prepared_types.secret_key in
  let operations = [
    operation "public_key" [Blob] (Bytes 1312);
    operation "sign" [Blob; Blob; Blob] (Bytes 2420);
    operation "sign_randomized" [Blob; Blob; Blob; Blob] (Bytes 2420);
    operation "verify" [Blob; Blob; Blob; Blob] Boolean;
    operation "prepare_public_key" [Blob] (Handle (public, 20576));
    operation "prepare_secret_key" [Blob] (Handle (secret, 28800));
    operation "sign_prepared" [Prepared secret; Blob; Blob] (Bytes 2420);
    operation "sign_randomized_prepared" [Prepared secret; Blob; Blob; Blob] (Bytes 2420);
    operation "verify_prepared" [Prepared public; Blob; Blob; Blob] Boolean;
  ] in
  P.register P.{ abi = 1; name = "ml-dsa"; runtime = Some "runtime.wasm";
    types = [public; secret];
    imports = List.map snd operations; bindings = List.map fst operations }
