module V = Mo_values.Value

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
  | _ -> Error ("ml_dsa_" ^ name ^ " received invalid interpreter arguments")
