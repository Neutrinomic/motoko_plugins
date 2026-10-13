(* Portable RSA-PSS interpreter semantics, RFC 8017 sections 5.2 and 9.1.
   This uses variable-time Num arithmetic only in the interpreter. Generated
   canisters use the separately compiled constant-time private-key runtime.
   The fixed profile is RSA-3072/e=65537, SHA-256/MGF1-SHA256, 32-byte salt. *)

module V = Mo_values.Value
module Z = struct
  type t = Big_int.big_int
  let zero = Big_int.zero_big_int
  let one = Big_int.unit_big_int
  let of_int = Big_int.big_int_of_int
  let to_int = Big_int.int_of_big_int
  let add = Big_int.add_big_int
  let sub = Big_int.sub_big_int
  let mul = Big_int.mult_big_int
  let equal = Big_int.eq_big_int
  let compare = Big_int.compare_big_int
  let sign = Big_int.sign_big_int
  let modulo = Big_int.mod_big_int
  let shift_left = Big_int.shift_left_big_int
  let shift_right = Big_int.shift_right_big_int
  let odd x = not (equal (modulo x (of_int 2)) zero)
  let powm base exponent modulus =
    let rec loop base exponent product =
      if equal exponent zero then product
      else loop (modulo (mul base base) modulus) (shift_right exponent 1)
        (if odd exponent then modulo (mul product base) modulus else product)
    in
    loop (modulo base modulus) exponent one
end

let exponent = Z.of_int 65537
let modulus_min = Z.shift_left Z.one 3071
let from_bytes bytes =
  String.fold_left (fun n byte ->
    Z.add (Z.shift_left n 8) (Z.of_int (Char.code byte))) Z.zero bytes
let to_bytes length value =
  String.init length (fun i -> Char.chr (Z.to_int
    (Z.modulo (Z.shift_right value ((length - i - 1) * 8)) (Z.of_int 256))))

type secret = { p : Z.t; q : Z.t; dp : Z.t; dq : Z.t; qi : Z.t; n : Z.t }

let parse_public bytes =
  if String.length bytes <> 384 || Char.code bytes.[0] land 128 = 0 ||
      Char.code bytes.[383] land 1 = 0 then None
  else Some (from_bytes bytes)

(* This checks CRT consistency, not primality. Generate p and q with a trusted
   RSA key generator. Signing also verifies the result before releasing it. *)
let parse_secret bytes =
  if String.length bytes <> 960 ||
      Char.code bytes.[0] land 128 = 0 ||
      Char.code bytes.[192] land 128 = 0 ||
      Char.code bytes.[191] land 1 = 0 ||
      Char.code bytes.[383] land 1 = 0 then None
  else
    let component index = from_bytes (String.sub bytes (index * 192) 192) in
    let p = component 0 and q = component 1 in
    let dp = component 2 and dq = component 3 and qi = component 4 in
    let n = Z.mul p q in
    let valid_exp prime power =
      let phi = Z.sub prime Z.one in
      Z.sign power > 0 && Z.compare power phi < 0 &&
      Z.equal (Z.modulo (Z.mul exponent power) phi) Z.one
    in
    if Z.equal p q || Z.compare n modulus_min < 0 ||
        not (valid_exp p dp) || not (valid_exp q dq) ||
        Z.sign qi <= 0 || Z.compare qi p >= 0 ||
        not (Z.equal (Z.modulo (Z.mul q qi) p) Z.one) then None
    else Some { p; q; dp; dq; qi; n }

let mgf1 seed length =
  let result = Bytes.create length in
  for counter = 0 to (length + 31) / 32 - 1 do
    let encoded = Bytes.create 4 in
    Bytes.set_int32_be encoded 0 (Int32.of_int counter);
    let block = Rsa_sha256.digest (seed ^ Bytes.unsafe_to_string encoded) in
    Bytes.blit_string block 0 result (counter * 32) (min 32 (length - counter * 32))
  done;
  Bytes.unsafe_to_string result

let pss_encode digest salt =
  let hash = Rsa_sha256.digest (String.make 8 '\x00' ^ digest ^ salt) in
  let data = String.make 318 '\x00' ^ "\x01" ^ salt in
  let mask = mgf1 hash 351 in
  let masked = Bytes.init 351 (fun i ->
    Char.chr (Char.code data.[i] lxor Char.code mask.[i])) in
  Bytes.set masked 0 (Char.chr (Char.code (Bytes.get masked 0) land 127));
  Bytes.unsafe_to_string masked ^ hash ^ "\xbc"

let pss_verify digest encoded =
  if encoded.[383] <> '\xbc' || Char.code encoded.[0] land 128 <> 0 then false
  else
    let hash = String.sub encoded 351 32 in
    let mask = mgf1 hash 351 in
    let data = Bytes.init 351 (fun i ->
      Char.chr (Char.code encoded.[i] lxor Char.code mask.[i])) in
    Bytes.set data 0 (Char.chr (Char.code (Bytes.get data 0) land 127));
    let padding_ok = ref true in
    for i = 0 to 317 do
      if Bytes.get data i <> '\x00' then padding_ok := false
    done;
    !padding_ok && Bytes.get data 318 = '\x01' &&
      hash = Rsa_sha256.digest (String.make 8 '\x00' ^ digest ^ Bytes.sub_string data 319 32)

let sign secret digest salt =
  let encoded = from_bytes (pss_encode digest salt) in
  let m1 = Z.powm encoded secret.dp secret.p in
  let m2 = Z.powm encoded secret.dq secret.q in
  let h = Z.modulo (Z.mul (Z.sub m1 m2) secret.qi) secret.p in
  let signature = Z.add m2 (Z.mul secret.q h) in
  if Z.equal (Z.powm signature exponent secret.n) encoded then
    Some (to_bytes 384 signature)
  else None

let err label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let ok value = Ok (V.Variant ("ok", value))

let evaluate name _type_arguments _types arguments =
  match name, arguments with
  | "validate_public_key", [V.Blob bytes] ->
      (match parse_public bytes with None -> err "invalidPublicKey" | Some _ -> ok (V.Bool true))
  | "validate_private_key", [V.Blob bytes] ->
      (match parse_secret bytes with None -> err "invalidSecretKey" | Some _ -> ok (V.Bool true))
  | "public_key", [V.Blob bytes] ->
      (match parse_secret bytes with
      | None -> err "invalidSecretKey"
      | Some secret -> ok (V.Blob (to_bytes 384 secret.n)))
  | ("sign" | "sign_prehash"), [V.Blob bytes; V.Blob message; V.Blob salt] ->
      (match parse_secret bytes with
      | None -> err "invalidSecretKey"
      | Some secret ->
          if name = "sign_prehash" && String.length message <> 32 then err "invalidDigest"
          else if String.length salt <> 32 then err "invalidSalt"
          else
            let digest = if name = "sign_prehash" then message else Rsa_sha256.digest message in
            match sign secret digest salt with
            | None -> err "invalidSecretKey"
            | Some signature -> ok (V.Blob signature))
  | ("verify" | "verify_prehash"), [V.Blob bytes; V.Blob message; V.Blob signature] ->
      (match parse_public bytes with
      | None -> err "invalidPublicKey"
      | Some modulus ->
          if name = "verify_prehash" && String.length message <> 32 then err "invalidDigest"
          else if String.length signature <> 384 then err "invalidSignature"
          else
            let value = from_bytes signature in
            if Z.compare value modulus >= 0 then err "invalidSignature"
            else
              let digest = if name = "verify_prehash" then message else Rsa_sha256.digest message in
              let encoded = to_bytes 384 (Z.powm value exponent modulus) in
              ok (V.Bool (pss_verify digest encoded)))
  | _ -> Error ("rsa_" ^ name ^ " received invalid interpreter arguments")
