(* Independent interpreter semantics for pure Ed25519, RFC 8032 sections
   5.1 and 6: https://www.rfc-editor.org/rfc/rfc8032.html
   Variable-time Big_int arithmetic is deliberately confined to the interpreter;
   the Wasm plugin uses ed25519-dalek. This reference does not call that runtime.

   Decoding requires canonical compressed encodings, excludes small-order A/R,
   and requires S < L. Verification uses the uncofactored equation, matching
   dalek verify_strict. Mixed-order points are not excluded merely because they
   are outside the prime-order subgroup. *)

module Sha512 = struct
(* SHA-512 constants and compression from the portable sha512 plugin reference;
   embedded here so loading Ed25519 does not require any other plugin. *)
let constants = [|
  0x428a2f98d728ae22L; 0x7137449123ef65cdL; 0xb5c0fbcfec4d3b2fL; 0xe9b5dba58189dbbcL;
  0x3956c25bf348b538L; 0x59f111f1b605d019L; 0x923f82a4af194f9bL; 0xab1c5ed5da6d8118L;
  0xd807aa98a3030242L; 0x12835b0145706fbeL; 0x243185be4ee4b28cL; 0x550c7dc3d5ffb4e2L;
  0x72be5d74f27b896fL; 0x80deb1fe3b1696b1L; 0x9bdc06a725c71235L; 0xc19bf174cf692694L;
  0xe49b69c19ef14ad2L; 0xefbe4786384f25e3L; 0x0fc19dc68b8cd5b5L; 0x240ca1cc77ac9c65L;
  0x2de92c6f592b0275L; 0x4a7484aa6ea6e483L; 0x5cb0a9dcbd41fbd4L; 0x76f988da831153b5L;
  0x983e5152ee66dfabL; 0xa831c66d2db43210L; 0xb00327c898fb213fL; 0xbf597fc7beef0ee4L;
  0xc6e00bf33da88fc2L; 0xd5a79147930aa725L; 0x06ca6351e003826fL; 0x142929670a0e6e70L;
  0x27b70a8546d22ffcL; 0x2e1b21385c26c926L; 0x4d2c6dfc5ac42aedL; 0x53380d139d95b3dfL;
  0x650a73548baf63deL; 0x766a0abb3c77b2a8L; 0x81c2c92e47edaee6L; 0x92722c851482353bL;
  0xa2bfe8a14cf10364L; 0xa81a664bbc423001L; 0xc24b8b70d0f89791L; 0xc76c51a30654be30L;
  0xd192e819d6ef5218L; 0xd69906245565a910L; 0xf40e35855771202aL; 0x106aa07032bbd1b8L;
  0x19a4c116b8d2d0c8L; 0x1e376c085141ab53L; 0x2748774cdf8eeb99L; 0x34b0bcb5e19b48a8L;
  0x391c0cb3c5c95a63L; 0x4ed8aa4ae3418acbL; 0x5b9cca4f7763e373L; 0x682e6ff3d6b2b8a3L;
  0x748f82ee5defb2fcL; 0x78a5636f43172f60L; 0x84c87814a1f0ab72L; 0x8cc702081a6439ecL;
  0x90befffa23631e28L; 0xa4506cebde82bde9L; 0xbef9a3f7b2c67915L; 0xc67178f2e372532bL;
  0xca273eceea26619cL; 0xd186b8c721c0c207L; 0xeada7dd6cde0eb1eL; 0xf57d4f7fee6ed178L;
  0x06f067aa72176fbaL; 0x0a637dc5a2c898a6L; 0x113f9804bef90daeL; 0x1b710b35131c471bL;
  0x28db77f523047d84L; 0x32caab7b40c72493L; 0x3c9ebe0a15c9bebcL; 0x431d67c49c100d4cL;
  0x4cc5d4becb3e42b6L; 0x597f299cfc657e2aL; 0x5fcb6fab3ad6faecL; 0x6c44198c4a475817L;
|]

let initial512 = [|
  0x6a09e667f3bcc908L; 0xbb67ae8584caa73bL; 0x3c6ef372fe94f82bL; 0xa54ff53a5f1d36f1L;
  0x510e527fade682d1L; 0x9b05688c2b3e6c1fL; 0x1f83d9abfb41bd6bL; 0x5be0cd19137e2179L;
|]

let ( +! ) = Int64.add
let ( ^! ) = Int64.logxor
let ( &! ) = Int64.logand
let shr = Int64.shift_right_logical
let ror x n = Int64.logor (shr x n) (Int64.shift_left x (64 - n))
let sigma0 x = ror x 1 ^! ror x 8 ^! shr x 7
let sigma1 x = ror x 19 ^! ror x 61 ^! shr x 6

let compress_with_words state words input offset =
  for i = 0 to 15 do
    words.(i) <- String.get_int64_be input (offset + i * 8)
  done;
  for i = 16 to 79 do
    words.(i) <- sigma1 words.(i - 2) +! words.(i - 7) +!
      sigma0 words.(i - 15) +! words.(i - 16)
  done;
  let a = ref state.(0) and b = ref state.(1) in
  let c = ref state.(2) and d = ref state.(3) in
  let e = ref state.(4) and f = ref state.(5) in
  let g = ref state.(6) and h = ref state.(7) in
  for i = 0 to 79 do
    let big1 = ror !e 14 ^! ror !e 18 ^! ror !e 41 in
    let choose = (!e &! !f) ^! (Int64.lognot !e &! !g) in
    let t1 = !h +! big1 +! choose +! constants.(i) +! words.(i) in
    let big0 = ror !a 28 ^! ror !a 34 ^! ror !a 39 in
    let majority = (!a &! !b) ^! (!a &! !c) ^! (!b &! !c) in
    let t2 = big0 +! majority in
    h := !g; g := !f; f := !e; e := !d +! t1;
    d := !c; c := !b; b := !a; a := t1 +! t2
  done;
  List.iteri (fun i x -> state.(i) <- state.(i) +! !x)
    [a; b; c; d; e; f; g; h]

let digest parts =
  let state = Array.copy initial512 in
  let words = Array.make 80 0L in
  let pending = Bytes.make 128 '\000' in
  let used = ref 0 in
  let length = ref 0L in
  List.iter (fun input ->
    let count = String.length input in
    length := Int64.add !length (Int64.of_int count);
    let offset = ref 0 in
    if !used <> 0 then begin
      let take = min (128 - !used) count in
      Bytes.blit_string input 0 pending !used take;
      used := !used + take;
      offset := take;
      if !used = 128 then begin
        compress_with_words state words (Bytes.unsafe_to_string pending) 0;
        used := 0
      end
    end;
    while count - !offset >= 128 do
      compress_with_words state words input !offset;
      offset := !offset + 128
    done;
    let tail = count - !offset in
    if tail <> 0 then begin
      Bytes.blit_string input !offset pending !used tail;
      used := !used + tail
    end
  ) parts;
  let padded = if !used < 112 then 128 else 256 in
  let tail = Bytes.make padded '\000' in
  Bytes.blit pending 0 tail 0 !used;
  Bytes.set tail !used '\128';
  Bytes.set_int64_be tail (padded - 16) (Int64.shift_right_logical !length 61);
  Bytes.set_int64_be tail (padded - 8) (Int64.shift_left !length 3);
  let tail = Bytes.unsafe_to_string tail in
  compress_with_words state words tail 0;
  if padded = 256 then compress_with_words state words tail 128;
  let output = Bytes.create 64 in
  Array.iteri (fun i word -> Bytes.set_int64_be output (i * 8) word) state;
  Bytes.unsafe_to_string output
end

module Z = struct
  type t = Big_int.big_int
  let zero = Big_int.zero_big_int
  let one = Big_int.unit_big_int
  let of_int = Big_int.big_int_of_int
  let of_string = Big_int.big_int_of_string
  let add = Big_int.add_big_int
  let sub = Big_int.sub_big_int
  let mul = Big_int.mult_big_int
  let equal = Big_int.eq_big_int
  let compare = Big_int.compare_big_int
  let rem = Big_int.mod_big_int
  let shl = Big_int.shift_left_big_int
  let shr = Big_int.shift_right_big_int
  let odd n = not (equal (rem n (of_int 2)) zero)
  let powm base exponent modulus =
    let rec loop base exponent total =
      if equal exponent zero then total
      else loop (rem (mul base base) modulus) (shr exponent 1)
        (if odd exponent then rem (mul total base) modulus else total)
    in loop (rem base modulus) exponent one
end

let prime = Z.sub (Z.shl Z.one 255) (Z.of_int 19)
let order = Z.add (Z.shl Z.one 252)
  (Z.of_string "27742317777372353535851937790883648493")
let field value = Z.rem value prime
let add a b = field (Z.add a b)
let sub a b = field (Z.sub a b)
let mul a b = field (Z.mul a b)
let square a = mul a a
let inverse a = Z.powm a (Z.sub prime (Z.of_int 2)) prime
let d = mul (Z.of_int (-121665)) (inverse (Z.of_int 121666))
let twice_d = add d d
let sqrt_minus_one = Z.powm (Z.of_int 2) (Z.shr (Z.sub prime Z.one) 2) prime
let sqrt_exponent = Z.shr (Z.add prime (Z.of_int 3)) 3

let from_le bytes =
  let value = ref Z.zero in
  for i = String.length bytes - 1 downto 0 do
    value := Z.add (Z.shl !value 8) (Z.of_int (Char.code bytes.[i]))
  done;
  !value

let to_le length value =
  let value = ref value in
  String.init length (fun _ ->
    let byte = Big_int.int_of_big_int (Z.rem !value (Z.of_int 256)) in
    value := Z.shr !value 8;
    Char.chr byte)

type point = { x : Z.t; y : Z.t; z : Z.t; t : Z.t }
let identity = { x = Z.zero; y = Z.one; z = Z.one; t = Z.zero }
let affine x y = { x; y; z = Z.one; t = mul x y }
let base = affine
  (Z.of_string "15112221349535400772501151409588531511454012693041857206046113283949847762202")
  (Z.of_string "46316835694926478169428394003475163141307993866256225615783033603165251855960")

let point_add p q =
  let a = mul (sub p.y p.x) (sub q.y q.x) in
  let b = mul (add p.y p.x) (add q.y q.x) in
  let c = mul twice_d (mul p.t q.t) in
  let d = add (mul p.z q.z) (mul p.z q.z) in
  let e = sub b a and f = sub d c and g = add d c and h = add b a in
  { x = mul e f; y = mul g h; z = mul f g; t = mul e h }

let point_equal p q =
  Z.equal (mul p.x q.z) (mul q.x p.z) &&
  Z.equal (mul p.y q.z) (mul q.y p.z)

let multiply scalar point =
  let rec loop scalar term total =
    if Z.equal scalar Z.zero then total
    else loop (Z.shr scalar 1) (point_add term term)
      (if Z.odd scalar then point_add total term else total)
  in loop scalar point identity

let encode point =
  let iz = inverse point.z in
  let x = mul point.x iz and y = mul point.y iz in
  to_le 32 (if Z.odd x then Z.add y (Z.shl Z.one 255) else y)

let decode bytes =
  if String.length bytes <> 32 then None
  else
    let encoded = from_le bytes in
    let sign = Z.compare encoded (Z.shl Z.one 255) >= 0 in
    let y = Z.rem encoded (Z.shl Z.one 255) in
    if Z.compare y prime >= 0 then None
    else
      let y2 = square y in
      let denominator = add (mul d y2) Z.one in
      (* The denominator cannot vanish on edwards25519 for a valid point. *)
      if Z.equal denominator Z.zero then None
      else
        let x2 = mul (sub y2 Z.one) (inverse denominator) in
        let x = Z.powm x2 sqrt_exponent prime in
        let x = if Z.equal (square x) x2 then x else mul x sqrt_minus_one in
        if not (Z.equal (square x) x2) || (Z.equal x Z.zero && sign) then None
        else
          let x = if Z.odd x = sign then x else sub Z.zero x in
          let point = affine x y in
          if point_equal (multiply (Z.of_int 8) point) identity then None
          else Some point

let expand seed =
  let hashed = Sha512.digest [seed] in
  let scalar = Bytes.of_string (String.sub hashed 0 32) in
  Bytes.set scalar 0 (Char.chr (Char.code (Bytes.get scalar 0) land 248));
  Bytes.set scalar 31 (Char.chr ((Char.code (Bytes.get scalar 31) land 63) lor 64));
  from_le (Bytes.unsafe_to_string scalar), String.sub hashed 32 32

let hash_scalar parts = Z.rem (from_le (Sha512.digest parts)) order
let public_key seed =
  let scalar, _ = expand seed in
  encode (multiply scalar base)

let sign seed message =
  let scalar, prefix = expand seed in
  let public_key = encode (multiply scalar base) in
  let nonce = hash_scalar [prefix; message] in
  let r = encode (multiply nonce base) in
  let challenge = hash_scalar [r; public_key; message] in
  r ^ to_le 32 (Z.rem (Z.add nonce (Z.mul challenge scalar)) order)

module V = Mo_values.Value
let err label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let ok value = Ok (V.Variant ("ok", value))

let evaluate name _type_arguments _types arguments =
  match name, arguments with
  | "public_key", [V.Blob seed] ->
      if String.length seed <> 32 then err "invalidSecretKey"
      else ok (V.Blob (public_key seed))
  | "validate_public_key", [V.Blob key] ->
      (match decode key with
      | None -> err "invalidPublicKey"
      | Some _ -> ok (V.Bool true))
  | "sign", [V.Blob seed; V.Blob message] ->
      if String.length seed <> 32 then err "invalidSecretKey"
      else ok (V.Blob (sign seed message))
  | "verify", [V.Blob key; V.Blob message; V.Blob signature] ->
      (match decode key with
      | None -> err "invalidPublicKey"
      | Some public_key ->
          if String.length signature <> 64 then err "invalidSignature"
          else
            let r_bytes = String.sub signature 0 32 in
            let scalar = from_le (String.sub signature 32 32) in
            if Z.compare scalar order >= 0 then err "invalidSignature"
            else match decode r_bytes with
            | None -> err "invalidSignature"
            | Some r ->
                let challenge = hash_scalar [r_bytes; key; message] in
                ok (V.Bool (point_equal (multiply scalar base)
                  (point_add r (multiply challenge public_key)))))
  | _ -> Error ("ed25519_" ^ name ^ " received invalid interpreter arguments")
