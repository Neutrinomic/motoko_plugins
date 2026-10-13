module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
open G
open Mo_types
open Wasm_exts.Types

let prepared_public = C.Prepared.create ~owner:"ed25519" ~name:"Ed25519PreparedPublicKey"
let prepared_secret = C.Prepared.create ~owner:"ed25519" ~name:"Ed25519PreparedSecretKey"
let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidSignature"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

type argument = Blob | Prepared of C.Prepared.t
let argument_type = function Blob -> Type.blob | Prepared descriptor -> C.Prepared.typ descriptor

module type Operation = sig
  val name : string
  val arguments : argument list
  val capacity : int
  val prepared_result : C.Prepared.t option
  val infallible : bool
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("ed25519_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "ed25519_result" in
      let set_status, status = B.new_local env "ed25519_status" in
      let errors = List.fold_right (fun (number,label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1,"invalidSecretKey"; -2,"invalidPublicKey"]
        (B.Variant.inject env "invalidSignature" (B.Tuple.compile_unit env)) in
      let arguments = List.map2 (fun kind (actual, code) -> match kind with
        | Blob -> code
        | Prepared descriptor -> B.Prepared.unwrap descriptor actual code)
        O.arguments (List.combine specialization.C.argument_types arguments) in
      let success = match O.prepared_result with
        | Some descriptor -> B.Prepared.wrap descriptor result
        | None -> if O.capacity = 0 then status else result in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set,_) -> argument ^^ set) arguments locals) ^^
        (if O.capacity = 0 then G.nop else B.alloc_blob env (num O.capacity) ^^ set_result) ^^
        G.concat (List.map2 (fun kind (_,get) ->
          get ^^ B.Blob.payload_ptr_unskewed env ^^
          (match kind with Blob -> get ^^ B.Blob.len env | Prepared _ -> G.nop)) O.arguments locals) ^^
        (if O.capacity = 0 then G.nop else result ^^ B.Blob.payload_ptr_unskewed env) ^^
        B.call env "ed25519" ("ed25519_" ^ O.name) ^^
        (if O.infallible then success else
          set_status ^^ status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
          B.E.if1 I64Type (B.Variant.inject env "err" errors)
            (B.Variant.inject env "ok" success))
      }
  end
end

let operation ?(prepared_result=None) ?(infallible=false) name arguments capacity =
  let module O = struct
    let name = name
    let arguments = arguments
    let capacity = capacity
    let prepared_result = prepared_result
    let infallible = infallible
  end in
  let module Generator = Generate(O) in
  let prepared = prepared_result <> None || List.exists (function Prepared _ -> true | Blob -> false) arguments in
  let reference_evaluate = if prepared then
    Reference.evaluate_prepared ~public_key:prepared_public ~secret_key:prepared_secret name
    else Reference.evaluate name in
  let typ = match prepared_result with
    | Some descriptor -> C.Prepared.typ descriptor
    | None -> if capacity = 0 then Type.bool else Type.blob in
  let binding = C.{
    id = "ed25519_" ^ name; name = "ed25519_" ^ name;
    arguments = Fixed (fun _ -> Ok (List.map argument_type arguments));
    type_parameters = [];
    result_type = (fun _ _ -> Ok (if infallible then typ else result_type typ));
    evaluate = C.pure reference_evaluate;
  } in
  let count = List.fold_left (fun sum -> function Blob -> sum + 2 | Prepared _ -> sum + 1) 0 arguments
    + if capacity = 0 then 0 else 1 in
  (binding, (module Generator : P.Generator)),
  ("ed25519_" ^ name, List.init count (fun _ -> I64Type), if infallible then [] else [I64Type])

let () =
  let operations = [
    operation "public_key" [Blob] 32;
    operation "validate_public_key" [Blob] 0;
    operation "sign" [Blob; Blob] 64;
    operation "verify" [Blob; Blob; Blob] 0;
    operation ~prepared_result:(Some prepared_public) "prepare_public_key" [Blob] 1056;
    operation ~prepared_result:(Some prepared_secret) "prepare_secret_key" [Blob] 96;
    operation "verify_prepared" [Prepared prepared_public; Blob; Blob] 0;
    operation ~infallible:true "sign_prepared" [Prepared prepared_secret; Blob] 64;
  ] in
  P.register P.{ abi = 1; name = "ed25519"; runtime = Some "runtime.wasm";
    types = [prepared_public; prepared_secret];
    imports = List.map snd operations; bindings = List.map fst operations }
