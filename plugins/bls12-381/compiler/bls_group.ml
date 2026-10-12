open Bls_field

let scalar_of_bytes bytes =
  if String.length bytes <> 32 then Error "invalid scalar length"
  else let n = z_of_be bytes in
    if Z.compare n r >= 0 then Error "noncanonical scalar" else Ok n

let scalar_to_bytes n =
  if Z.sign n < 0 || Z.compare n r >= 0 then invalid_arg "BLS12-381 scalar out of range";
  be_of_z 32 n

(* Jacobian arithmetic avoids an inverse on every addition while preserving a
   straightforward affine interface for the hash and pairing references. *)
module Make (F : FIELD) (C : sig
  val b : F.t
  val generator : F.t * F.t
end) = struct
  type t = Infinity | Point of F.t * F.t
  let infinity = Infinity
  let generator = let x,y = C.generator in Point (x,y)
  let is_infinity = function Infinity -> true | Point _ -> false
  let is_on_curve = function
    | Infinity -> true
    | Point (x,y) -> F.equal (F.square y) (F.add (F.mul (F.square x) x) C.b)
  let equal a b = match a,b with
    | Infinity, Infinity -> true
    | Point (x,y), Point (u,v) -> F.equal x u && F.equal y v
    | _ -> false
  let neg = function Infinity -> Infinity | Point (x,y) -> Point (x,F.neg y)
  let jac_infinity = F.zero, F.one, F.zero
  let jac_of_affine = function Infinity -> jac_infinity | Point (x,y) -> x,y,F.one
  let affine_of_jac (x,y,z) =
    if F.is_zero z then Infinity else
      let zi = F.inv z in
      let zi2 = F.square zi in
      Point (F.mul x zi2, F.mul y (F.mul zi2 zi))
  let double (x,y,z) =
    if F.is_zero z || F.is_zero y then jac_infinity else
      let a = F.square x in
      let b = F.square y in
      let c = F.square b in
      let d = F.mul (F.of_int 2) (F.sub (F.sub (F.square (F.add x b)) a) c) in
      let e = F.mul (F.of_int 3) a in
      let xx = F.sub (F.square e) (F.add d d) in
      let yy = F.sub (F.mul e (F.sub d xx)) (F.mul (F.of_int 8) c) in
      let zz = F.mul (F.add y y) z in
      xx,yy,zz
  let jac_add ((x1,y1,z1) as p1) ((x2,y2,z2) as p2) =
    if F.is_zero z1 then p2 else if F.is_zero z2 then p1 else
      let z1z1 = F.square z1 in
      let z2z2 = F.square z2 in
      let u1 = F.mul x1 z2z2 in
      let u2 = F.mul x2 z1z1 in
      let s1 = F.mul y1 (F.mul z2 z2z2) in
      let s2 = F.mul y2 (F.mul z1 z1z1) in
      if F.equal u1 u2 then
        if F.equal s1 s2 then double p1 else jac_infinity
      else
        let h = F.sub u2 u1 in
        let i = F.square (F.add h h) in
        let j = F.mul h i in
        let rr = F.mul (F.of_int 2) (F.sub s2 s1) in
        let v = F.mul u1 i in
        let xx = F.sub (F.sub (F.square rr) j) (F.add v v) in
        let yy = F.sub (F.mul rr (F.sub v xx)) (F.mul (F.add s1 s1) j) in
        let zz = F.mul (F.sub (F.sub (F.square (F.add z1 z2)) z1z1) z2z2) h in
        xx,yy,zz
  let jac_mul p scalar =
    let p, scalar = if Z.sign scalar < 0 then neg p, Z.neg scalar else p, scalar in
    let p = jac_of_affine p in
    let acc = ref jac_infinity in
    for bit = Z.numbits scalar - 1 downto 0 do
      acc := double !acc;
      if Z.testbit scalar bit then acc := jac_add !acc p
    done;
    !acc
  let add a b = affine_of_jac (jac_add (jac_of_affine a) (jac_of_affine b))
  let mul p scalar = affine_of_jac (jac_mul p scalar)
  let msm terms = affine_of_jac
      (List.fold_left (fun acc (p,n) -> jac_add acc (jac_mul p n)) jac_infinity terms)
  let is_in_subgroup p = is_on_curve p && is_infinity (mul p r)
end

(* The top three bits are compression, infinity and lexicographic y sign. *)
let encode_flags size bytes infinity sign =
  let encoded = Bytes.of_string bytes in
  if Bytes.length encoded <> size then invalid_arg "BLS12-381 encoding size";
  let first = Char.code (Bytes.get encoded 0) lor 0x80
      lor (if infinity then 0x40 else 0) lor (if sign then 0x20 else 0) in
  Bytes.set encoded 0 (Char.chr first);
  Bytes.unsafe_to_string encoded

let decode_flags size bytes =
  if String.length bytes <> size then Error "invalid point length"
  else let first = Char.code bytes.[0] in
    if first land 0x80 = 0 then Error "point is not compressed"
    else
      let coordinates = Bytes.of_string bytes in
      Bytes.set coordinates 0 (Char.chr (first land 0x1f));
      Ok (first land 0x40 <> 0, first land 0x20 <> 0, Bytes.unsafe_to_string coordinates)

module G1 = struct
  include Make (Fp) (struct
    let b = Fp.of_int 4
    let generator =
      Z.of_string "0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb",
      Z.of_string "0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
  end)
  let to_compressed = function
    | Infinity -> encode_flags 48 (String.make 48 '\000') true false
    | Point (x,y) -> encode_flags 48 (Fp.to_bytes x) false (Fp.sign y)
  let of_compressed_unchecked bytes =
    match decode_flags 48 bytes with
    | Error e -> Error e
    | Ok (true, sign, coordinates) ->
      if sign || not (Z.equal (z_of_be coordinates) Z.zero) then Error "noncanonical infinity"
      else Ok Infinity
    | Ok (false, sign, coordinates) ->
      match Fp.of_bytes coordinates with
      | Error e -> Error e
      | Ok x ->
        match Fp.sqrt (Fp.add (Fp.mul (Fp.square x) x) (Fp.of_int 4)) with
        | None -> Error "point is not on G1"
        | Some y ->
          let y = if Fp.sign y = sign then y else Fp.neg y in
          if Fp.sign y <> sign then Error "invalid point sign" else Ok (Point (x,y))
  let of_compressed bytes = match of_compressed_unchecked bytes with
    | Ok p when not (is_in_subgroup p) -> Error "point is not in G1 subgroup"
    | answer -> answer
end

module G2 = struct
  include Make (Fp2) (struct
    let b = Fp.of_int 4, Fp.of_int 4
    let generator =
      (Z.of_string "352701069587466618187139116011060144890029952792775240219908644239793785735715026873347600343865175952761926303160",
       Z.of_string "3059144344244213709971259814753781636986470325476647558659373206291635324768958432433509563104347017837885763365758"),
      (Z.of_string "1985150602287291935568054521177171638300868978215655730859378665066344726373823718423869104263333984641494340347905",
       Z.of_string "927553665492332455747201965776037880757740193453592970025027978793976877002675564980949289727957565575433344219582")
  end)
  let to_compressed = function
    | Infinity -> encode_flags 96 (String.make 96 '\000') true false
    | Point ((real,imag), y) ->
      encode_flags 96 (Fp.to_bytes imag ^ Fp.to_bytes real) false (Fp2.sign y)
  let of_compressed_unchecked bytes =
    match decode_flags 96 bytes with
    | Error e -> Error e
    | Ok (true, sign, coordinates) ->
      if sign || not (Z.equal (z_of_be coordinates) Z.zero) then Error "noncanonical infinity"
      else Ok Infinity
    | Ok (false, sign, coordinates) ->
      match Fp.of_bytes (String.sub coordinates 0 48), Fp.of_bytes (String.sub coordinates 48 48) with
      | Error e, _ | _, Error e -> Error e
      | Ok imag, Ok real ->
        let x = real,imag in
        match Fp2.sqrt (Fp2.add (Fp2.mul (Fp2.square x) x) (Fp.of_int 4,Fp.of_int 4)) with
        | None -> Error "point is not on G2"
        | Some y ->
          let y = if Fp2.sign y = sign then y else Fp2.neg y in
          if Fp2.sign y <> sign then Error "invalid point sign" else Ok (Point (x,y))
  let of_compressed bytes = match of_compressed_unchecked bytes with
    | Ok p when not (is_in_subgroup p) -> Error "point is not in G2 subgroup"
    | answer -> answer
end
