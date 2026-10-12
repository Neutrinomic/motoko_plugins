(* RFC 9380 sections 5.3.1, 5.4.1, 6.6.3, 8.8, and Appendix E.
   Affine formulas keep the portable interpreter implementation auditable;
   generated canisters use the optimized Rust implementation. *)
module Fp = Bls_field.Fp
module Fp2 = Bls_field.Fp2
module G1 = Bls_group.G1
module G2 = Bls_group.G2
module C = Bls_hash_constants

let expand_message_xmd ~dst ~length message =
  if length < 0 || length > 255 * 32 then
    invalid_arg "BLS12-381 XMD output length must be in 0..8160";
  let digest = Bls_sha256.digest in
  let dst = if String.length dst > 255 then
      digest ("H2C-OVERSIZE-DST-" ^ dst) else dst in
  let dst_prime = dst ^ String.make 1 (Char.chr (String.length dst)) in
  let length_be = String.init 2 (function
      | 0 -> Char.chr (length lsr 8)
      | _ -> Char.chr (length land 255)) in
  let b0 = digest (String.make 64 '\000' ^ message ^ length_be ^ "\000" ^ dst_prime) in
  let blocks = (length + 31) / 32 in
  let output = Buffer.create (blocks * 32) in
  let previous = ref "" in
  for i = 1 to blocks do
    let input = if i = 1 then b0 else
        String.init 32 (fun j ->
            Char.chr (Char.code b0.[j] lxor Char.code !previous.[j])) in
    let block = digest (input ^ String.make 1 (Char.chr i) ^ dst_prime) in
    Buffer.add_string output block;
    previous := block
  done;
  String.sub (Buffer.contents output) 0 length

module Map (F : Bls_field.FIELD) = struct
  (* Appendix F.2 expressed with ordinary field inversion and square roots.
     The exceptional u = 0 case also covers Z*u^2 = -1. *)
  let swu ~a ~b ~z u =
    let zu2 = F.mul z (F.square u) in
    let t = F.add zu2 (F.square zu2) in
    let numerator = F.mul b (F.add t F.one) in
    let denominator = F.neg (F.mul a t) in
    let denominator = if F.is_zero denominator then F.mul z a else denominator in
    let x = F.div numerator denominator in
    let equation x = F.add (F.add (F.mul (F.square x) x) (F.mul a x)) b in
    let x, y = match F.sqrt (equation x) with
      | Some y -> x, y
      | None ->
        let x = F.mul zu2 x in
        match F.sqrt (equation x) with
        | Some y -> x, y
        | None -> failwith "BLS12-381 SWU invariant violated"
    in
    let y = if F.sgn0 u = F.sgn0 y then y else F.neg y in
    x, y

  let polynomial coefficients x =
    Array.fold_right (fun coefficient value -> F.add coefficient (F.mul x value))
      coefficients F.zero

  (* Rational-map poles represent the point at infinity, as required by
     RFC 9380 section 6.6.3. *)
  let isogeny coefficients (x, y) =
    let xn = polynomial coefficients.(0) x in
    let xd = polynomial coefficients.(1) x in
    let yn = polynomial coefficients.(2) x in
    let yd = polynomial coefficients.(3) x in
    if F.is_zero xd || F.is_zero yd then None
    else Some (F.div xn xd, F.mul y (F.div yn yd))
end

module Map1 = Map (Fp)
module Map2 = Map (Fp2)

let map_fp u =
  match Map1.isogeny C.iso_11_map_coefficients
      (Map1.swu ~a:C.iso_11_a ~b:C.iso_11_b ~z:C.iso_11_z u) with
  | None -> G1.infinity
  | Some (x, y) -> G1.Point (x, y)

let map_fp2 u =
  match Map2.isogeny C.iso_3_map_coefficients
      (Map2.swu ~a:C.iso_3_a ~b:C.iso_3_b ~z:C.iso_3_z u) with
  | None -> G2.infinity
  | Some (x, y) -> G2.Point (x, y)

let clear_g1 point = G1.mul point C.h_eff_g1
let clear_g2 point = G2.mul point C.h_eff_g2

let map_g1 bytes = match Fp.of_bytes bytes with
  | Error message -> Error message
  | Ok u -> Ok (clear_g1 (map_fp u))

let map_g2 bytes = match Fp2.of_bytes bytes with
  | Error message -> Error message
  | Ok u -> Ok (clear_g2 (map_fp2 u))

let hash_to_field ~dst ~count message =
  let uniform = expand_message_xmd ~dst ~length:(count * 64) message in
  Array.init count (fun i ->
      Fp.of_z (Bls_field.z_of_be (String.sub uniform (i * 64) 64)))

let hash_g1 ~dst message =
  let u = hash_to_field ~dst ~count:2 message in
  clear_g1 (G1.add (map_fp u.(0)) (map_fp u.(1)))

let hash_g2 ~dst message =
  let u = hash_to_field ~dst ~count:4 message in
  clear_g2 (G2.add (map_fp2 (u.(0), u.(1))) (map_fp2 (u.(2), u.(3))))
