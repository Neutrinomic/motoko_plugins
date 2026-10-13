(* Portable executable specification of ML-DSA-44, FIPS 204 (August 2024),
   Algorithms 6--8 and 16--42:
   https://doi.org/10.6028/NIST.FIPS.204
   Ordinary modular arithmetic deliberately differs from the Montgomery
   arithmetic of the Wasm kernel. This interpreter reference is not a
   constant-time implementation and must not be used for production signing.
   Polynomial coefficients are reduced before multiplication: the product is
   less than 2^46 and fits the compiler host's 63-bit OCaml int. *)

module Shake = Mldsa_shake

let q = 8380417
let gamma1 = 131072
let gamma2 = 95232
let beta = 78
let omega = 80
let tau = 39
let n = 256
let dimension = 4

exception Invalid_encoding

let reduce x = let r = x mod q in if r < 0 then r + q else r
let center x = let r = reduce x in if r > q / 2 then r - q else r
let multiply a b = (a * b) mod q

let power base exponent =
  let rec loop base exponent product =
    if exponent = 0 then product else
    loop (multiply base base) (exponent lsr 1)
      (if exponent land 1 = 1 then multiply product base else product)
  in
  loop base exponent 1

let reverse8 x =
  let result = ref 0 in
  for i = 0 to 7 do result := (!result lsl 1) lor ((x lsr i) land 1) done;
  !result

let zetas = Array.init n (fun i -> power 1753 (reverse8 i))

let ntt polynomial =
  let a = Array.map reduce polynomial in
  let index = ref 0 and width = ref 128 in
  while !width > 0 do
    let start = ref 0 in
    while !start < n do
      incr index;
      let zeta = zetas.(!index) in
      for j = !start to !start + !width - 1 do
        let t = multiply zeta a.(j + !width) and u = a.(j) in
        a.(j) <- reduce (u + t);
        a.(j + !width) <- reduce (u - t)
      done;
      start := !start + 2 * !width
    done;
    width := !width / 2
  done;
  a

let inverse_ntt polynomial =
  let a = Array.map reduce polynomial in
  let index = ref 256 and width = ref 1 in
  while !width < n do
    let start = ref 0 in
    while !start < n do
      decr index;
      let zeta = q - zetas.(!index) in
      for j = !start to !start + !width - 1 do
        let u = a.(j) and v = a.(j + !width) in
        a.(j) <- reduce (u + v);
        a.(j + !width) <- multiply zeta (reduce (u - v))
      done;
      start := !start + 2 * !width
    done;
    width := !width * 2
  done;
  Array.map (multiply 8347681) a

let map_vector f = Array.map (Array.map f)
let map2_poly f a b = Array.init n (fun i -> f a.(i) b.(i))
let map2_vector f a b = Array.init dimension (fun i -> map2_poly f a.(i) b.(i))
let ntt_vector = Array.map ntt
let inverse_vector = Array.map inverse_ntt

let matrix_product matrix vector =
  Array.init dimension (fun row ->
    Array.init n (fun i ->
      let sum = ref 0 in
      for column = 0 to dimension - 1 do
        sum := reduce (!sum + multiply matrix.(row).(column).(i) vector.(column).(i))
      done;
      !sum))

let scalar_product scalar vector =
  Array.map (map2_poly multiply scalar) vector |> inverse_vector

let byte value = String.make 1 (Char.chr value)
let little16 value = byte (value land 255) ^ byte (value lsr 8)
let code data i = Char.code data.[i]

(* Encodings are little-endian bit streams. The polynomial widths all divide
   the complete byte length; there is no padding to normalize. *)
let pack bits translate polynomial =
  let output = Bytes.make (32 * bits) '\000' in
  Array.iteri (fun i value ->
    let value = translate value in
    for bit = 0 to bits - 1 do
      if value land (1 lsl bit) <> 0 then begin
        let index = i * bits + bit in
        let at = index / 8 in
        Bytes.set output at
          (Char.chr (Char.code (Bytes.get output at) lor (1 lsl (index mod 8))))
      end
    done) polynomial;
  Bytes.unsafe_to_string output

let unpack bits translate data offset =
  Array.init n (fun i ->
    let value = ref 0 in
    for bit = 0 to bits - 1 do
      let index = i * bits + bit in
      value := !value lor (((code data (offset + index / 8) lsr (index mod 8)) land 1) lsl bit)
    done;
    translate !value)

let pack_vector bits translate vector =
  Array.to_list (Array.map (pack bits translate) vector) |> String.concat ""

let unpack_vector bits translate data offset =
  Array.init dimension (fun i -> unpack bits translate data (offset + 32 * bits * i))

let uniform_ntt seed =
  let state = Shake.create128 seed in
  let output = Array.make n 0 in
  let i = ref 0 in
  while !i < n do
    let bytes = Shake.squeeze state 3 in
    let value = code bytes 0 lor (code bytes 1 lsl 8) lor ((code bytes 2 land 127) lsl 16) in
    if value < q then (output.(!i) <- value; incr i)
  done;
  output

let expand_matrix rho =
  Array.init dimension (fun row ->
    Array.init dimension (fun column -> uniform_ntt (rho ^ byte column ^ byte row)))

let bounded_poly seed =
  let state = Shake.create256 seed in
  let output = Array.make n 0 in
  let i = ref 0 in
  let accept nibble =
    if nibble < 15 && !i < n then begin
      output.(!i) <- 2 - nibble mod 5;
      incr i
    end
  in
  while !i < n do
    let b = code (Shake.squeeze state 1) 0 in
    accept (b land 15);
    accept (b lsr 4)
  done;
  output

let expand_secret rho =
  let all = Array.init (2 * dimension) (fun i -> bounded_poly (rho ^ little16 i)) in
  Array.sub all 0 dimension, Array.sub all dimension dimension

let expand_mask rho kappa =
  Array.init dimension (fun i ->
    unpack 18 (fun value -> gamma1 - value)
      (Shake.digest256 (rho ^ little16 (kappa + i)) (32 * 18)) 0)

let sample_ball seed =
  let state = Shake.create256 seed in
  let signs = Shake.squeeze state 8 in
  let polynomial = Array.make n 0 in
  for i = n - tau to n - 1 do
    let j = ref (code (Shake.squeeze state 1) 0) in
    while !j > i do j := code (Shake.squeeze state 1) 0 done;
    let sign_index = i + tau - n in
    polynomial.(i) <- polynomial.(!j);
    polynomial.(!j) <- 1 - 2 * ((code signs (sign_index / 8) lsr (sign_index mod 8)) land 1)
  done;
  polynomial

let power2round value =
  let value = reduce value in
  let high = (value + 4095) / 8192 in
  high, value - high * 8192

let decompose value =
  let value = reduce value in
  let low = value mod (2 * gamma2) in
  let low = if low > gamma2 then low - 2 * gamma2 else low in
  if value - low = q - 1 then 0, low - 1
  else (value - low) / (2 * gamma2), low

let high_bits value = fst (decompose value)
let low_bits value = snd (decompose value)

let use_hint hint value =
  let high, low = decompose value in
  if hint = 0 then high
  else if low > 0 then (high + 1) mod 44
  else (high + 43) mod 44

let norm vector =
  Array.fold_left (fun largest polynomial ->
    Array.fold_left (fun largest value -> max largest (abs (center value))) largest polynomial) 0 vector

type private_key = {
  rho : string;
  key : string;
  tr : string;
  s1 : int array array;
  s2 : int array array;
  t0 : int array array;
}

let encode_public rho t1 = rho ^ pack_vector 10 Fun.id t1

let encode_private secret =
  secret.rho ^ secret.key ^ secret.tr ^
  pack_vector 3 (fun value -> 2 - value) secret.s1 ^
  pack_vector 3 (fun value -> 2 - value) secret.s2 ^
  pack_vector 13 (fun value -> 4096 - value) secret.t0

let decode_private bytes =
  if String.length bytes <> 2560 then raise Invalid_encoding;
  let bounded value = if value > 4 then raise Invalid_encoding else 2 - value in
  {
    rho = String.sub bytes 0 32;
    key = String.sub bytes 32 32;
    tr = String.sub bytes 64 64;
    s1 = unpack_vector 3 bounded bytes 128;
    s2 = unpack_vector 3 bounded bytes 512;
    t0 = unpack_vector 13 (fun value -> 4096 - value) bytes 896;
  }

let keygen seed =
  if String.length seed <> 32 then raise Invalid_encoding;
  let expanded = Shake.digest256 (seed ^ "\004\004") 128 in
  let rho = String.sub expanded 0 32 in
  let rho_prime = String.sub expanded 32 64 in
  let key = String.sub expanded 96 32 in
  let matrix = expand_matrix rho in
  let s1, s2 = expand_secret rho_prime in
  let t = map2_vector (fun a b -> reduce (a + b))
    (inverse_vector (matrix_product matrix (ntt_vector s1))) s2 in
  let t1 = map_vector (fun value -> fst (power2round value)) t in
  let t0 = map_vector (fun value -> snd (power2round value)) t in
  let public = encode_public rho t1 in
  public, {rho; key; tr = Shake.digest256 public 64; s1; s2; t0}

let public_key seed = fst (keygen seed)

let encode_hints hints =
  let bytes = Bytes.make (omega + dimension) '\000' in
  let offset = ref 0 in
  Array.iteri (fun row polynomial ->
    Array.iteri (fun index value ->
      if value <> 0 then begin
        Bytes.set bytes !offset (Char.chr index);
        incr offset
      end) polynomial;
    Bytes.set bytes (omega + row) (Char.chr !offset)) hints;
  Bytes.unsafe_to_string bytes

let decode_hints signature =
  let offset = 32 + dimension * 32 * 18 in
  let previous = ref 0 in
  let hints = Array.init dimension (fun row ->
    let finish = code signature (offset + omega + row) in
    if finish < !previous || finish > omega then raise Invalid_encoding;
    let polynomial = Array.make n 0 in
    for i = !previous to finish - 1 do
      let index = code signature (offset + i) in
      if i > !previous && index <= code signature (offset + i - 1) then raise Invalid_encoding;
      polynomial.(index) <- 1
    done;
    previous := finish;
    polynomial) in
  for i = !previous to omega - 1 do
    if code signature (offset + i) <> 0 then raise Invalid_encoding
  done;
  hints

let domain_message message context =
  if String.length context > 255 then raise Invalid_encoding;
  "\000" ^ byte (String.length context) ^ context ^ message

(* Formatted-message variants are private helpers for the official internal
   FIPS vectors. The registered Motoko API always adds its context domain. *)
let sign_internal secret formatted_message randomness =
  if String.length randomness <> 32 then raise Invalid_encoding;
  let matrix = expand_matrix secret.rho in
  let s1 = ntt_vector secret.s1 and s2 = ntt_vector secret.s2 and t0 = ntt_vector secret.t0 in
  let mu = Shake.digest256 (secret.tr ^ formatted_message) 64 in
  let rho = Shake.digest256 (secret.key ^ randomness ^ mu) 64 in
  let rec attempt kappa =
    (* Match the pinned Wasm implementation's release-mode u16 nonce counter.
       Rejection sampling has variable cost; the counter wraps after 16,384
       attempts, rather than introducing an interpreter-only failure. *)
    let y = expand_mask rho kappa in
    let w = inverse_vector (matrix_product matrix (ntt_vector y)) in
    let w1 = map_vector high_bits w in
    let challenge = Shake.digest256 (mu ^ pack_vector 6 Fun.id w1) 32 in
    let c = ntt (sample_ball challenge) in
    let cs1 = scalar_product c s1 in
    let cs2 = scalar_product c s2 in
    let z = map2_vector (fun a b -> center (a + b)) y cs1 in
    let residual = map2_vector (fun a b -> reduce (a - b)) w cs2 in
    let r0 = map_vector low_bits residual in
    if norm z >= gamma1 - beta || norm r0 >= gamma2 - beta then attempt ((kappa + dimension) land 65535)
    else
      let ct0 = scalar_product c t0 in
      if norm ct0 >= gamma2 then attempt ((kappa + dimension) land 65535)
      else
        let hints = map2_vector (fun r t ->
          if high_bits r <> high_bits (r + t) then 1 else 0) residual ct0 in
        let weight = Array.fold_left (fun total polynomial ->
          Array.fold_left (+) total polynomial) 0 hints in
        if weight > omega then attempt ((kappa + dimension) land 65535)
        else challenge ^ pack_vector 18 (fun value -> gamma1 - value) z ^ encode_hints hints
  in
  attempt 0

let sign seed message context randomness =
  let _, secret = keygen seed in
  sign_internal secret (domain_message message context) randomness

let verify_internal public formatted_message signature =
  if String.length public <> 1312 || String.length signature <> 2420 then false else
  try
    let rho = String.sub public 0 32 in
    let t1 = unpack_vector 10 Fun.id public 32 in
    let challenge = String.sub signature 0 32 in
    let z = unpack_vector 18 (fun value -> gamma1 - value) signature 32 in
    let hints = decode_hints signature in
    if norm z >= gamma1 - beta then false else
    let matrix = expand_matrix rho in
    let c = ntt (sample_ball challenge) in
    let az = matrix_product matrix (ntt_vector z) in
    let ct = Array.map (map2_poly multiply c) (ntt_vector (map_vector (fun t -> t * 8192) t1)) in
    let w = inverse_vector (map2_vector (fun a b -> reduce (a - b)) az ct) in
    let w1 = map2_vector use_hint hints w in
    let tr = Shake.digest256 public 64 in
    let mu = Shake.digest256 (tr ^ formatted_message) 64 in
    challenge = Shake.digest256 (mu ^ pack_vector 6 Fun.id w1) 32
  with Invalid_encoding -> false

let verify public message signature context =
  verify_internal public (domain_message message context) signature
