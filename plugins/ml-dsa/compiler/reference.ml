module V = Mo_values.Value
module Prepared = Mo_values.Compute_plugin.Prepared

let error label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let ok value = Ok (V.Variant ("ok", value))

let evaluate name _type_arguments _types arguments =
  match name, arguments with
  | "public_key", [V.Blob seed] ->
      if String.length seed <> 32 then error "invalidSecretKey"
      else ok (V.Blob (Mldsa.public_key seed))
  | "sign", [V.Blob seed; V.Blob message; V.Blob context] ->
      if String.length seed <> 32 then error "invalidSecretKey"
      else if String.length context > 255 then error "invalidContext"
      else ok (V.Blob (Mldsa.sign seed message context (String.make 32 '\000')))
  | "sign_randomized", [V.Blob seed; V.Blob message; V.Blob context; V.Blob randomness] ->
      if String.length seed <> 32 then error "invalidSecretKey"
      else if String.length context > 255 then error "invalidContext"
      else if String.length randomness <> 32 then error "invalidRandomness"
      else ok (V.Blob (Mldsa.sign seed message context randomness))
  | "verify", [V.Blob public; V.Blob message; V.Blob signature; V.Blob context] ->
      if String.length public <> 1312 then error "invalidPublicKey"
      else if String.length signature <> 2420 then error "invalidSignature"
      else if String.length context > 255 then error "invalidContext"
      else ok (V.Bool (Mldsa.verify public message signature context))
  (* Opaque interpreter payloads retain canonical inputs, not the Wasm
     implementation's private cache representation. Recomputing through the
     independent reference preserves exact semantics without duplicating its
     optimization. Nominal typing prevents callers from fabricating handles. *)
  | "prepare_public_key", [V.Blob public] ->
      if String.length public <> 1312 then error "invalidPublicKey"
      else ok (Prepared.wrap Prepared_types.public_key public)
  | "prepare_secret_key", [V.Blob seed] ->
      if String.length seed <> 32 then error "invalidSecretKey"
      else ok (Prepared.wrap Prepared_types.secret_key seed)
  | "verify_prepared", [(V.Blob _ as prepared); V.Blob message; V.Blob signature; V.Blob context] ->
      if String.length signature <> 2420 then error "invalidSignature"
      else if String.length context > 255 then error "invalidContext"
      else
        let public = Prepared.unwrap Prepared_types.public_key prepared in
        ok (V.Bool (Mldsa.verify public message signature context))
  | "sign_prepared", [(V.Blob _ as prepared); V.Blob message; V.Blob context] ->
      if String.length context > 255 then error "invalidContext"
      else
        let seed = Prepared.unwrap Prepared_types.secret_key prepared in
        ok (V.Blob (Mldsa.sign seed message context (String.make 32 '\000')))
  | "sign_randomized_prepared", [(V.Blob _ as prepared); V.Blob message; V.Blob context; V.Blob randomness] ->
      if String.length context > 255 then error "invalidContext"
      else if String.length randomness <> 32 then error "invalidRandomness"
      else
        let seed = Prepared.unwrap Prepared_types.secret_key prepared in
        ok (V.Blob (Mldsa.sign seed message context randomness))
  | _ -> Error ("ml_dsa_" ^ name ^ " received invalid interpreter arguments")
