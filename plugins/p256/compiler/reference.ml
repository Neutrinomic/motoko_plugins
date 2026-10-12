module V = Mo_values.Value
module Curve = P256_curve
module Z = Curve.Z

let zhex s = Z.of_string ("0x" ^ s)
let curve = Curve.{
  p = zhex "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF";
  n = zhex "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551";
  a = zhex "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC";
  b = zhex "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B";
  gx = zhex "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296";
  gy = zhex "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5";
}

let err label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let ok value = Ok (V.Variant ("ok", value))
let blob error = function Some value -> ok (V.Blob value) | None -> err error
let valid_secret bytes =
  if String.length bytes <> 32 then false else
  let value = String.fold_left (fun n c -> Z.add (Z.shift_left n 8) (Z.of_int (Char.code c))) Z.zero bytes in
  Z.sign value > 0 && Z.compare value curve.Curve.n < 0

let evaluate name _type_arguments _types arguments = match name, arguments with
  | "public_key", [V.Blob secret; V.Bool compressed] ->
      blob "invalidSecretKey" (Curve.ec_public_key curve secret compressed)
  | "convert_public_key", [V.Blob key; V.Bool compressed] ->
      blob "invalidPublicKey" (Curve.ec_public_key_convert curve key compressed)
  | "sign_prehash", [V.Blob secret; V.Blob digest] ->
      if not (valid_secret secret) then err "invalidSecretKey"
      else if String.length digest <> 32 then err "invalidDigest"
      else blob "invalidSignature" (Curve.ec_ecdsa_sign ~low_s:false curve secret digest)
  | "verify_prehash", [V.Blob key; V.Blob digest; V.Blob signature] ->
      if Curve.ec_public_key_convert curve key true = None then err "invalidPublicKey"
      else if String.length digest <> 32 then err "invalidDigest"
      else if Curve.ec_compact_to_der curve signature = None then err "invalidSignature"
      else ok (V.Bool (Curve.ec_ecdsa_verify curve key digest signature))
  | "signature_to_der", [V.Blob signature] ->
      blob "invalidSignature" (Curve.ec_compact_to_der curve signature)
  | "signature_from_der", [V.Blob signature] ->
      blob "invalidSignature" (Curve.ec_der_to_compact curve signature)
  | "normalize_signature", [V.Blob signature] ->
      blob "invalidSignature" (Curve.ec_normalize_signature curve signature)
  | _ -> Error ("p256_" ^ name ^ " received invalid interpreter arguments")
