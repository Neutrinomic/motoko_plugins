module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
module R = Prepared
open G
open Mo_types
open Wasm_exts.Types

let error_type = Type.sum (List.map (fun label -> label, Type.unit)
  ["invalidSecretKey"; "invalidPublicKey"; "invalidDigest"; "invalidSalt"; "invalidSignature"])
let result_type typ = Type.sum ["err", error_type; "ok", typ]

type payload = Blob | Prepared of C.Prepared.t
type output = Boolean | Payload of payload * int
let payload_type = function Blob -> Type.blob | Prepared key -> C.Prepared.typ key
let output_type = function Boolean -> Type.bool | Payload (kind, _) -> payload_type kind

module type Operation = sig
  val name : string
  val inputs : payload list
  val output : output
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let num n = B.compile_unboxed_const (Int64.of_int n)
    let compile env specialization arguments =
      let locals = List.mapi (fun index _ -> B.new_local env ("rsa_arg" ^ string_of_int index)) arguments in
      let set_result, result = B.new_local env "rsa_result" in
      let set_status, status = B.new_local env "rsa_status" in
      let inputs = List.map2 (fun kind actual -> kind, actual) O.inputs specialization.C.argument_types in
      let operands = List.map2 (fun (kind, actual) (_, get) ->
        let blob = match kind with
          | Blob -> get
          | Prepared key -> B.Prepared.unwrap key actual get
        in
        blob ^^ B.Blob.payload_ptr_unskewed env ^^ blob ^^ B.Blob.len env) inputs locals in
      let allocate, output_pointer, payload = match O.output with
        | Boolean -> G.nop, G.nop, status
        | Payload (kind, size) ->
            B.alloc_blob env (num size) ^^ set_result,
            result ^^ B.Blob.payload_ptr_unskewed env,
            (match kind with Blob -> result | Prepared key -> B.Prepared.wrap key result)
      in
      let errors = List.fold_right (fun (number, label) rest ->
        status ^^ B.compile_eq_const (Int64.of_int number) ^^
        B.E.if1 I64Type (B.Variant.inject env label (B.Tuple.compile_unit env)) rest)
        [-1, "invalidSecretKey"; -2, "invalidPublicKey"; -3, "invalidDigest"; -4, "invalidSalt"]
        (B.Variant.inject env "invalidSignature" (B.Tuple.compile_unit env)) in
      P.{ representation = Managed; code =
        G.concat (List.map2 (fun argument (set, _) -> argument ^^ set) arguments locals) ^^
        allocate ^^ G.concat operands ^^ output_pointer ^^
        B.call env "rsa" ("rsa_" ^ O.name) ^^ set_status ^^
        status ^^ num 0 ^^ B.compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        B.E.if1 I64Type (B.Variant.inject env "err" errors)
          (B.Variant.inject env "ok" payload)
      }
  end
end

let operation name inputs output =
  let module O = struct let name = name let inputs = inputs let output = output end in
  let module Generator = Generate(O) in
  let binding = C.{
    id = "rsa_" ^ name; name = "rsa_" ^ name;
    arguments = Fixed (fun _ -> Ok (List.map payload_type inputs));
    type_parameters = [];
    result_type = (fun _ _ -> Ok (result_type (output_type output)));
    evaluate = C.pure (R.evaluate name);
  } in
  let count = List.length inputs * 2 + (match output with Boolean -> 0 | Payload _ -> 1) in
  (binding, (module Generator : P.Generator)),
  ("rsa_" ^ name, List.init count (fun _ -> I64Type), [I64Type])

let () =
  let signature = Payload (Blob, 384) in
  let public = Prepared R.public_key and secret = Prepared R.secret_key in
  let operations = [
    operation "public_key" [Blob] signature;
    operation "validate_private_key" [Blob] Boolean;
    operation "validate_public_key" [Blob] Boolean;
    operation "sign_prehash" [Blob; Blob; Blob] signature;
    operation "verify_prehash" [Blob; Blob; Blob] Boolean;
    operation "sign" [Blob; Blob; Blob] signature;
    operation "verify" [Blob; Blob; Blob] Boolean;
    operation "prepare_public_key" [Blob] (Payload (public, 824));
    operation "prepare_secret_key" [Blob] (Payload (secret, 1840));
    operation "sign_prepared" [secret; Blob; Blob] signature;
    operation "sign_prehash_prepared" [secret; Blob; Blob] signature;
    operation "verify_prepared" [public; Blob; Blob] Boolean;
    operation "verify_prehash_prepared" [public; Blob; Blob] Boolean;
  ] in
  P.register P.{ abi = 1; name = "rsa"; runtime = Some "runtime.wasm";
    types = [R.public_key; R.secret_key];
    imports = List.map snd operations; bindings = List.map fst operations }
