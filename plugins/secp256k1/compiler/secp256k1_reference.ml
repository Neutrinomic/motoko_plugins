(* Portable interpreter semantics. This deliberately uses variable-time big
   integer arithmetic: the generated Wasm runtime supplies the native primitive.
   The generic curve layer is also compiled under P256_curve for P-256. *)

module Sha256 = struct
(* SHA-256 reference semantics for both Motoko interpreters. Keep this portable:
   the canister's implementation is in plugins/sha256/runtime/src/lib.rs. *)

let constants = [|
  0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l;
  0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
  0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
  0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
  0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
  0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
  0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l;
  0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
  0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
  0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
  0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l;
  0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
  0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l;
  0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
  0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
  0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l;
|]

let ( +! ) = Int32.add
let ( ^! ) = Int32.logxor
let ( &! ) = Int32.logand
let shr = Int32.shift_right_logical
let ror x n = Int32.logor (shr x n) (Int32.shift_left x (32 - n))
let sigma0 x = ror x 7 ^! ror x 18 ^! shr x 3
let sigma1 x = ror x 17 ^! ror x 19 ^! shr x 10

let digest input =
  let state = [|
    0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
    0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l;
  |] in
  let words = Array.make 64 0l in
  let compress bytes offset =
    for i = 0 to 15 do
      words.(i) <- String.get_int32_be bytes (offset + i * 4)
    done;
    for i = 16 to 63 do
      words.(i) <- sigma1 words.(i - 2) +! words.(i - 7) +!
        sigma0 words.(i - 15) +! words.(i - 16)
    done;
    let a = ref state.(0) and b = ref state.(1) in
    let c = ref state.(2) and d = ref state.(3) in
    let e = ref state.(4) and f = ref state.(5) in
    let g = ref state.(6) and h = ref state.(7) in
    for i = 0 to 63 do
      let big1 = ror !e 6 ^! ror !e 11 ^! ror !e 25 in
      let choose = (!e &! !f) ^! (Int32.lognot !e &! !g) in
      let t1 = !h +! big1 +! choose +! constants.(i) +! words.(i) in
      let big0 = ror !a 2 ^! ror !a 13 ^! ror !a 22 in
      let majority = (!a &! !b) ^! (!a &! !c) ^! (!b &! !c) in
      let t2 = big0 +! majority in
      h := !g; g := !f; f := !e; e := !d +! t1;
      d := !c; c := !b; b := !a; a := t1 +! t2
    done;
    List.iteri (fun i x -> state.(i) <- state.(i) +! !x)
      [a; b; c; d; e; f; g; h]
  in
  let length = String.length input in
  let complete = length / 64 in
  for i = 0 to complete - 1 do compress input (i * 64) done;
  let remaining = length mod 64 in
  let padded = if remaining < 56 then 64 else 128 in
  let tail = Bytes.make padded '\x00' in
  Bytes.blit_string input (complete * 64) tail 0 remaining;
  Bytes.set tail remaining '\x80';
  Bytes.set_int64_be tail (padded - 8)
    (Int64.shift_left (Int64.of_int length) 3);
  let tail = Bytes.unsafe_to_string tail in
  compress tail 0;
  if padded = 128 then compress tail 64;
  let result = Bytes.create 32 in
  Array.iteri (fun i word -> Bytes.set_int32_be result (i * 4) word) state;
  Bytes.unsafe_to_string result

end

(* Use the compiler's Num arithmetic, whose native stubs are already exported
   by moc. Linking an independent Zarith runtime into a plugin is unnecessary. *)
module Z = struct
  type t = Big_int.big_int
  let zero = Big_int.zero_big_int
  let one = Big_int.unit_big_int
  let of_int = Big_int.big_int_of_int
  let to_int = Big_int.int_of_big_int
  let of_string = Big_int.big_int_of_string
  let add = Big_int.add_big_int
  let sub = Big_int.sub_big_int
  let mul = Big_int.mult_big_int
  let neg = Big_int.minus_big_int
  let succ = Big_int.succ_big_int
  let sign = Big_int.sign_big_int
  let compare = Big_int.compare_big_int
  let equal = Big_int.eq_big_int
  let erem = Big_int.mod_big_int
  let shift_left = Big_int.shift_left_big_int
  let shift_right = Big_int.shift_right_big_int
  let extract n offset length = erem (shift_right n offset) (shift_left one length)
  let testbit n offset = not (equal (extract n offset 1) zero)
  let powm base exponent modulus =
    let rec loop base exponent total =
      if equal exponent zero then total
      else loop (erem (mul base base) modulus) (shift_right exponent 1)
        (if testbit exponent 0 then erem (mul total base) modulus else total)
    in
    loop (erem base modulus) exponent one
  let invert value modulus =
    let rec loop r next_r coefficient next_coefficient =
      if equal next_r zero then
        if equal r one then erem coefficient modulus else raise Division_by_zero
      else
        let quotient, remainder = Big_int.quomod_big_int r next_r in
        loop next_r remainder next_coefficient (sub coefficient (mul quotient next_coefficient))
    in
    loop modulus (erem value modulus) zero one
end

type curve = { p : Z.t; n : Z.t; a : Z.t; b : Z.t; gx : Z.t; gy : Z.t }
type point = Infinity | Point of Z.t * Z.t

let zhex text = Z.of_string ("0x" ^ text)
let secp256k1 = {
  p = zhex "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F";
  n = zhex "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141";
  a = Z.zero;
  b = Z.of_int 7;
  gx = zhex "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798";
  gy = zhex "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8";
}

let modulo x modulus = Z.erem (Z.add (Z.erem x modulus) modulus) modulus
let of_bytes bytes =
  String.fold_left (fun n c -> Z.add (Z.shift_left n 8) (Z.of_int (Char.code c))) Z.zero bytes
let to_bytes size value =
  String.init size (fun i -> Char.chr (Z.to_int (Z.extract value ((size - i - 1) * 8) 8)))
let valid_scalar curve scalar = Z.sign scalar > 0 && Z.compare scalar curve.n < 0
let generator curve = Point (curve.gx, curve.gy)
let ( let* ) value fn = match value with None -> None | Some x -> fn x

let add curve left right =
  match left, right with
  | Infinity, point | point, Infinity -> point
  | Point (x1, y1), Point (x2, y2) ->
    if Z.equal x1 x2 && Z.equal (modulo (Z.add y1 y2) curve.p) Z.zero then Infinity
    else
      let numerator, denominator =
        if Z.equal x1 x2 then
          Z.add (Z.mul (Z.of_int 3) (Z.mul x1 x1)) curve.a,
          Z.mul (Z.of_int 2) y1
        else Z.sub y2 y1, Z.sub x2 x1
      in
      let slope = modulo (Z.mul numerator (Z.invert (modulo denominator curve.p) curve.p)) curve.p in
      let x3 = modulo (Z.sub (Z.sub (Z.mul slope slope) x1) x2) curve.p in
      let y3 = modulo (Z.sub (Z.mul slope (Z.sub x1 x3)) y1) curve.p in
      Point (x3, y3)

let multiply curve scalar point =
  let rec go n term total =
    if Z.equal n Z.zero then total
    else go (Z.shift_right n 1) (add curve term term)
      (if Z.testbit n 0 then add curve total term else total)
  in
  go scalar point Infinity

let lift_x curve x odd =
  if Z.sign x < 0 || Z.compare x curve.p >= 0 then None
  else
    let rhs = modulo (Z.add (Z.add (Z.mul (Z.mul x x) x) (Z.mul curve.a x)) curve.b) curve.p in
    (* Both supported primes are 3 modulo 4. *)
    let y = Z.powm rhs (Z.shift_right (Z.succ curve.p) 2) curve.p in
    if not (Z.equal (modulo (Z.mul y y) curve.p) rhs) then None
    else Some (Point (x, if Z.testbit y 0 = odd then y else Z.sub curve.p y))

let decode curve bytes =
  let size = String.length bytes in
  if size = 33 && (bytes.[0] = '\x02' || bytes.[0] = '\x03') then
    lift_x curve (of_bytes (String.sub bytes 1 32)) (bytes.[0] = '\x03')
  else if size = 65 && bytes.[0] = '\x04' then
    let x = of_bytes (String.sub bytes 1 32) and y = of_bytes (String.sub bytes 33 32) in
    if Z.compare x curve.p >= 0 || Z.compare y curve.p >= 0 then None
    else
      let rhs = modulo (Z.add (Z.add (Z.mul (Z.mul x x) x) (Z.mul curve.a x)) curve.b) curve.p in
      if Z.equal (modulo (Z.mul y y) curve.p) rhs then Some (Point (x,y)) else None
  else None

let encode compressed = function
  | Infinity -> None
  | Point (x,y) -> Some (
      if compressed then (if Z.testbit y 0 then "\x03" else "\x02") ^ to_bytes 32 x
      else "\x04" ^ to_bytes 32 x ^ to_bytes 32 y)

let ec_public_key curve secret compressed =
  if String.length secret <> 32 then None
  else let scalar = of_bytes secret in
    if not (valid_scalar curve scalar) then None
    else encode compressed (multiply curve scalar (generator curve))

let ec_public_key_convert curve public compressed =
  let* point = decode curve public in encode compressed point

let ec_point_add curve left right compressed =
  let* left = decode curve left in
  let* right = decode curve right in
  encode compressed (add curve left right)

let ec_point_mul curve public scalar compressed =
  if String.length scalar <> 32 then None
  else let scalar = of_bytes scalar in
    if not (valid_scalar curve scalar) then None
    else let* point = decode curve public in encode compressed (multiply curve scalar point)

let ec_public_key_tweak_add curve public tweak compressed =
  if String.length tweak <> 32 then None
  else let scalar = of_bytes tweak in
    if Z.compare scalar curve.n >= 0 then None
    else let* point = decode curve public in
      encode compressed (add curve point (multiply curve scalar (generator curve)))

let hmac key message =
  let key = if String.length key > 64 then Sha256.digest key else key in
  let pad byte = String.init 64 (fun i ->
    Char.chr (byte lxor (if i < String.length key then Char.code key.[i] else 0))) in
  Sha256.digest (pad 0x5c ^ Sha256.digest (pad 0x36 ^ message))

let nonce_generator curve secret message =
  let octets = to_bytes 32 (modulo (of_bytes message) curve.n) in
  let k = ref (String.make 32 '\x00') and v = ref (String.make 32 '\x01') in
  k := hmac !k (!v ^ "\x00" ^ secret ^ octets);
  v := hmac !k !v;
  k := hmac !k (!v ^ "\x01" ^ secret ^ octets);
  v := hmac !k !v;
  let first = ref true in
  let rec next () =
    if !first then first := false
    else begin k := hmac !k (!v ^ "\x00"); v := hmac !k !v end;
    v := hmac !k !v;
    let candidate = of_bytes !v in
    if valid_scalar curve candidate then candidate else next ()
  in next

let ec_ecdsa_sign ?(low_s=true) curve secret message =
  if String.length secret <> 32 || String.length message <> 32 then None
  else let d = of_bytes secret in
    if not (valid_scalar curve d) then None
    else
      let next_nonce = nonce_generator curve secret message in
      let rec sign () =
        let k = next_nonce () in
        match multiply curve k (generator curve) with
        | Infinity -> sign ()
        | Point (x, _) ->
          let r = modulo x curve.n in
          let s = modulo (Z.mul (Z.invert k curve.n) (Z.add (of_bytes message) (Z.mul r d))) curve.n in
          if Z.equal r Z.zero || Z.equal s Z.zero then sign ()
          else
            let s = if low_s && Z.compare s (Z.shift_right curve.n 1) > 0 then Z.sub curve.n s else s in
            Some (to_bytes 32 r ^ to_bytes 32 s)
      in sign ()

let signature_scalars curve signature =
  if String.length signature <> 64 then None
  else
    let r = of_bytes (String.sub signature 0 32) and s = of_bytes (String.sub signature 32 32) in
    if valid_scalar curve r && valid_scalar curve s then Some (r,s) else None

let ec_normalize_signature curve signature =
  let* r,s = signature_scalars curve signature in
  let s = if Z.compare s (Z.shift_right curve.n 1) > 0 then Z.sub curve.n s else s in
  Some (to_bytes 32 r ^ to_bytes 32 s)

let ec_ecdsa_verify ?(low_s=false) curve public message signature =
  if String.length message <> 32 then false
  else match decode curve public, signature_scalars curve signature with
    | Some public, Some (r,s) when not low_s || Z.compare s (Z.shift_right curve.n 1) <= 0 ->
      let inv_s = Z.invert s curve.n in
      let u1 = modulo (Z.mul (of_bytes message) inv_s) curve.n in
      let u2 = modulo (Z.mul r inv_s) curve.n in
      begin match add curve (multiply curve u1 (generator curve)) (multiply curve u2 public) with
      | Infinity -> false
      | Point (x,_) -> Z.equal (modulo x curve.n) r
      end
    | _ -> false

let ec_compact_to_der curve signature =
  let* r,s = signature_scalars curve signature in
  let integer value =
    let bytes = to_bytes 32 value in
    let first = ref 0 in
    while !first < 31 && bytes.[!first] = '\x00' do incr first done;
    let encoded = String.sub bytes !first (32 - !first) in
    let encoded = if Char.code encoded.[0] >= 128 then "\x00" ^ encoded else encoded in
    "\x02" ^ String.make 1 (Char.chr (String.length encoded)) ^ encoded
  in
  let contents = integer r ^ integer s in
  Some ("\x30" ^ String.make 1 (Char.chr (String.length contents)) ^ contents)

let ec_der_to_compact curve der =
  let size = String.length der in
  if size < 8 || size > 72 || der.[0] <> '\x30' || Char.code der.[1] <> size - 2 then None
  else
    let integer offset =
      if offset + 2 > size || der.[offset] <> '\x02' then None
      else
        let length = Char.code der.[offset + 1] in
        let start = offset + 2 in
        if length < 1 || length > 33 || start + length > size then None
        else if Char.code der.[start] >= 128 then None
        else if length > 1 && der.[start] = '\x00' && Char.code der.[start+1] < 128 then None
        else
          let value = of_bytes (String.sub der start length) in
          if valid_scalar curve value then Some (value,start+length) else None
    in
    let* r,next = integer 2 in
    let* s,last = integer next in
    if last <> size then None else Some (to_bytes 32 r ^ to_bytes 32 s)

let tagged_hash tag message =
  let tag = Sha256.digest tag in Sha256.digest (tag ^ tag ^ message)

let schnorr_normalized_key_option secret =
  if String.length secret <> 32 then None
  else
    let d = of_bytes secret in
    if not (valid_scalar secp256k1 d) then None
    else match multiply secp256k1 d (generator secp256k1) with
    | Infinity -> None
    | Point (px,py) ->
      Some ((if Z.testbit py 0 then Z.sub secp256k1.n d else d), px)

(* Both ordinary and factory-owned prepared signing use this same equation. *)
let schnorr_sign_normalized_option d px message aux =
  let d_bytes = to_bytes 32 d in
  let aux_hash = tagged_hash "BIP0340/aux" aux in
  let t = String.init 32 (fun i -> Char.chr (Char.code d_bytes.[i] lxor Char.code aux_hash.[i])) in
  let k = modulo (of_bytes (tagged_hash "BIP0340/nonce" (t ^ to_bytes 32 px ^ message))) secp256k1.n in
  if Z.equal k Z.zero then None
  else match multiply secp256k1 k (generator secp256k1) with
  | Infinity -> None
  | Point (rx,ry) ->
    let k = if Z.testbit ry 0 then Z.sub secp256k1.n k else k in
    let e = modulo (of_bytes (tagged_hash "BIP0340/challenge" (to_bytes 32 rx ^ to_bytes 32 px ^ message))) secp256k1.n in
    Some (to_bytes 32 rx ^ to_bytes 32 (modulo (Z.add k (Z.mul e d)) secp256k1.n))

let schnorr_sign_option secret message aux =
  if String.length aux <> 32 then None
  else let* d, px = schnorr_normalized_key_option secret in
    schnorr_sign_normalized_option d px message aux

let schnorr_verify_bool public message signature =
  if String.length public <> 32 || String.length signature <> 64 then false
  else
    let r = of_bytes (String.sub signature 0 32) and s = of_bytes (String.sub signature 32 32) in
    if Z.compare r secp256k1.p >= 0 || Z.compare s secp256k1.n >= 0 then false
    else match lift_x secp256k1 (of_bytes public) false with
    | None -> false
    | Some point ->
      let e = modulo (of_bytes (tagged_hash "BIP0340/challenge" (String.sub signature 0 32 ^ public ^ message))) secp256k1.n in
      let neg_e = modulo (Z.neg e) secp256k1.n in
      match add secp256k1 (multiply secp256k1 s (generator secp256k1)) (multiply secp256k1 neg_e point) with
      | Infinity -> false
      | Point (rx,ry) -> not (Z.testbit ry 0) && Z.equal rx r

let ( let@ ) value fn = match value with Error error -> Error error | Ok x -> fn x
let result error = function None -> Error error | Some value -> Ok value
let secret_scalar secret =
  if String.length secret = 32 && valid_scalar secp256k1 (of_bytes secret)
  then Ok (of_bytes secret) else Error "invalidSecretKey"
let scalar_bytes scalar =
  if String.length scalar = 32 && Z.compare (of_bytes scalar) secp256k1.n < 0
  then Ok (of_bytes scalar) else Error "invalidScalar"
let public_point public = result "invalidPublicKey" (decode secp256k1 public)
let digest_bytes message =
  if String.length message = 32 then Ok message else Error "invalidDigest"
let signature_bytes signature =
  result "invalidSignature" (signature_scalars secp256k1 signature)
let point_result compressed point = result "pointAtInfinity" (encode compressed point)

let public_key secret compressed =
  let@ scalar = secret_scalar secret in
  point_result compressed (multiply secp256k1 scalar (generator secp256k1))
let public_key_convert public compressed =
  let@ point = public_point public in point_result compressed point
let point_add left right compressed =
  let@ left = public_point left in
  let@ right = public_point right in
  point_result compressed (add secp256k1 left right)
let point_mul public scalar compressed =
  let@ point = public_point public in
  let@ scalar = scalar_bytes scalar in
  point_result compressed (multiply secp256k1 scalar point)
let base_multiply scalar compressed =
  let@ scalar = scalar_bytes scalar in
  point_result compressed (multiply secp256k1 scalar (generator secp256k1))
let public_key_tweak_add public tweak compressed =
  let@ point = public_point public in
  let@ scalar = scalar_bytes tweak in
  point_result compressed (add secp256k1 point (multiply secp256k1 scalar (generator secp256k1)))
let ecdsa_sign secret message =
  let@ _ = secret_scalar secret in
  let@ _ = digest_bytes message in
  result "invalidSignature" (ec_ecdsa_sign secp256k1 secret message)
let ecdsa_verify public message signature =
  let@ _ = public_point public in
  let@ _ = digest_bytes message in
  let@ _ = signature_bytes signature in
  Ok (ec_ecdsa_verify secp256k1 public message signature)
let compact_to_der signature = result "invalidSignature" (ec_compact_to_der secp256k1 signature)
let der_to_compact signature = result "invalidSignature" (ec_der_to_compact secp256k1 signature)
let normalize_signature signature = result "invalidSignature" (ec_normalize_signature secp256k1 signature)
let xonly_public_key public =
  let@ point = public_point public in
  match point with Infinity -> Error "invalidPublicKey" | Point (x,_) -> Ok (to_bytes 32 x)
let xonly_point public =
  if String.length public <> 32 then Error "invalidPublicKey"
  else result "invalidPublicKey" (lift_x secp256k1 (of_bytes public) false)
let xonly_tweak_add public tweak =
  let@ point = xonly_point public in
  let@ scalar = scalar_bytes tweak in
  point_result true (add secp256k1 point (multiply secp256k1 scalar (generator secp256k1)))
let xonly_tweak_secret secret tweak =
  let@ scalar = secret_scalar secret in
  let@ tweak = scalar_bytes tweak in
  match multiply secp256k1 scalar (generator secp256k1) with
  | Infinity -> Error "pointAtInfinity"
  | Point (_, y) ->
    let scalar = if Z.testbit y 0 then Z.sub secp256k1.n scalar else scalar in
    let tweaked = modulo (Z.add scalar tweak) secp256k1.n in
    if Z.equal tweaked Z.zero then Error "pointAtInfinity"
    else Ok (to_bytes 32 tweaked)
let schnorr_sign secret message aux =
  let@ _ = secret_scalar secret in
  if String.length aux <> 32 then Error "invalidAuxiliaryRandomness"
  else result "invalidSignature" (schnorr_sign_option secret message aux)
let schnorr_verify public message signature =
  let@ _ = xonly_point public in
  if String.length signature <> 64
     || Z.compare (of_bytes (String.sub signature 0 32)) secp256k1.p >= 0
     || Z.compare (of_bytes (String.sub signature 32 32)) secp256k1.n >= 0
  then Error "invalidSignature"
  else Ok (schnorr_verify_bool public message signature)

(* Opaque verification cache: eight canonical affine odd multiples Q..15Q. *)
let prepare_public_point point =
  let delta = add secp256k1 point point in
  let rec collect remaining point odd =
    match point with
    | Infinity -> Error "invalidPublicKey"
    | Point (x, y) ->
      let odd = (to_bytes 32 x ^ to_bytes 32 y) :: odd in
      if remaining = 1 then Ok (String.concat "" (List.rev odd))
      else collect (remaining - 1) (add secp256k1 point delta) odd
  in collect 8 point []

let prepare_public_key public =
  let@ point = public_point public in
  prepare_public_point point

let prepare_schnorr_public_key public =
  let@ point = xonly_point public in
  prepare_public_point point

let ecdsa_verify_prepared prepared message signature =
  if String.length prepared <> 512 then Error "invalidPublicKey"
  else ecdsa_verify ("\x04" ^ String.sub prepared 0 64) message signature

let schnorr_verify_prepared prepared message signature =
  if String.length prepared <> 512 then Error "invalidPublicKey"
  else schnorr_verify (String.sub prepared 0 32) message signature

let prepare_schnorr_secret_key secret =
  let@ d, px = result "invalidSecretKey" (schnorr_normalized_key_option secret) in
  Ok (to_bytes 32 d ^ to_bytes 32 px)

let schnorr_sign_prepared prepared message aux =
  if String.length prepared <> 64 then Error "invalidSecretKey"
  else
    let@ d = secret_scalar (String.sub prepared 0 32) in
    if String.length aux <> 32 then Error "invalidAuxiliaryRandomness"
    else
      let px = of_bytes (String.sub prepared 32 32) in
      result "invalidSignature" (schnorr_sign_normalized_option d px message aux)
