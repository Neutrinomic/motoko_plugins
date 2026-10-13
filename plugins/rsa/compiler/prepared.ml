module C = Mo_values.Compute_plugin
module V = Mo_values.Value

let public_key = C.Prepared.create ~owner:"rsa" ~name:"RSAPreparedPublicKey"
let secret_key = C.Prepared.create ~owner:"rsa" ~name:"RSAPreparedSecretKey"

(* Interpreter payloads retain the validated raw key. Native payloads instead
   contain the runtime's prepared arithmetic context; neither is observable
   through the nominal Motoko type. Reuse direct cryptographic semantics. *)
let evaluate name type_arguments types arguments =
  let prepare descriptor validation =
    match Reference.evaluate validation type_arguments types arguments, arguments with
    | Ok (V.Variant ("ok", V.Bool true)), [V.Blob bytes] ->
        Ok (V.Variant ("ok", C.Prepared.wrap descriptor bytes))
    | result, _ -> result
  in
  let invoke descriptor operation =
    match arguments with
    | key :: rest ->
        let bytes = C.Prepared.unwrap descriptor key in
        Reference.evaluate operation type_arguments types (V.Blob bytes :: rest)
    | [] -> Error ("rsa_" ^ name ^ " received invalid interpreter arguments")
  in
  match name with
  | "prepare_public_key" -> prepare public_key "validate_public_key"
  | "prepare_secret_key" -> prepare secret_key "validate_private_key"
  | "verify_prepared" -> invoke public_key "verify"
  | "verify_prehash_prepared" -> invoke public_key "verify_prehash"
  | "sign_prepared" -> invoke secret_key "sign"
  | "sign_prehash_prepared" -> invoke secret_key "sign_prehash"
  | _ -> Reference.evaluate name type_arguments types arguments
