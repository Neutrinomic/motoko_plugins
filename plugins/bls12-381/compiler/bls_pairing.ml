(* The projective Ate Miller-loop formulas and twist below are adapted from
   Ethereum py_ecc's optimized_bls12_381/{optimized_curve,optimized_pairing}.py:
   https://github.com/ethereum/py_ecc (MIT).

   Copyright (c) 2015-2025 The Ethereum Foundation

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. *)

module Fp = Bls_field.Fp
module Fp2 = Bls_field.Fp2

(* A polynomial basis makes the reference independent of the tower arithmetic
   used by the Wasm implementation: w^12 - 2*w^6 + 2 = 0. Coefficients are
   canonical field elements; intermediate convolution sums are reduced once. *)
module Fp12 = struct
  let zero = Array.make 12 Z.zero
  let one = Array.init 12 (fun i -> if i = 0 then Z.one else Z.zero)
  let of_fp x = Array.init 12 (fun i -> if i = 0 then x else Z.zero)
  let equal = Array.for_all2 Z.equal
  let is_zero a = Array.for_all (Z.equal Z.zero) a
  let add = Array.map2 Fp.add
  let sub = Array.map2 Fp.sub
  let scale k = Array.map (fun x -> Fp.mul (Z.of_int k) x)

  let reduce product =
    for k = Array.length product - 1 downto 12 do
      let twice = Z.shift_left product.(k) 1 in
      product.(k - 6) <- Z.add product.(k - 6) twice;
      product.(k - 12) <- Z.sub product.(k - 12) twice
    done;
    Array.init 12 (fun i -> Fp.of_z product.(i))

  let mul a b =
    let c = Array.make 23 Z.zero in
    for i = 0 to 11 do
      if not (Z.equal a.(i) Z.zero) then
        for j = 0 to 11 do
          if not (Z.equal b.(j) Z.zero) then
            c.(i + j) <- Z.add c.(i + j) (Z.mul a.(i) b.(j))
        done
    done;
    reduce c

  let square a =
    let c = Array.make 23 Z.zero in
    for i = 0 to 11 do
      c.(2 * i) <- Z.add c.(2 * i) (Z.mul a.(i) a.(i));
      for j = i + 1 to 11 do
        c.(i + j) <- Z.add c.(i + j) (Z.shift_left (Z.mul a.(i) a.(j)) 1)
      done
    done;
    reduce c

  let pow a n =
    let result = ref one in
    for i = Z.numbits n - 1 downto 0 do
      result := square !result;
      if Z.testbit n i then result := mul !result a
    done;
    !result

  (* Polynomial Euclid avoids an additional 4,572-bit field exponentiation for
     the single denominator inverse shared by a complete pairing product. *)
  let trim a =
    let n = ref (Array.length a) in
    while !n > 0 && Z.equal a.(!n - 1) Z.zero do decr n done;
    Array.sub a 0 !n

  let poly_sub a b =
    trim (Array.init (max (Array.length a) (Array.length b)) (fun i ->
      Fp.sub
        (if i < Array.length a then a.(i) else Z.zero)
        (if i < Array.length b then b.(i) else Z.zero)))

  let poly_mul a b =
    if Array.length a = 0 || Array.length b = 0 then [||]
    else begin
      let c = Array.make (Array.length a + Array.length b - 1) Z.zero in
      Array.iteri (fun i x -> Array.iteri (fun j y ->
        c.(i + j) <- Z.add c.(i + j) (Z.mul x y)) b) a;
      trim (Array.map Fp.of_z c)
    end

  let poly_divrem a b =
    let na = Array.length a and nb = Array.length b in
    if nb = 0 then invalid_arg "BLS12-381 polynomial division by zero";
    if na < nb then [||], a
    else begin
      let remainder = Array.copy a in
      let quotient = Array.make (na - nb + 1) Z.zero in
      let inverse = Fp.inv b.(nb - 1) in
      for k = na - nb downto 0 do
        let coefficient = Fp.mul remainder.(k + nb - 1) inverse in
        quotient.(k) <- coefficient;
        for j = 0 to nb - 1 do
          remainder.(k + j) <- Fp.sub remainder.(k + j) (Fp.mul coefficient b.(j))
        done
      done;
      trim quotient, trim remainder
    end

  let inv a =
    if is_zero a then invalid_arg "BLS12-381 field division by zero";
    let modulus = Array.init 13 (function
      | 0 -> Z.of_int 2 | 6 -> Fp.neg (Z.of_int 2) | 12 -> Z.one | _ -> Z.zero)
    in
    let rec euclid r0 r1 s0 s1 =
      if Array.length r1 = 0 then begin
        if Array.length r0 <> 1 then invalid_arg "BLS12-381 noninvertible field element";
        let factor = Fp.inv r0.(0) in
        let result = Array.make (max 12 (Array.length s0)) Z.zero in
        Array.iteri (fun i x -> result.(i) <- Fp.mul x factor) s0;
        reduce result
      end else
        let quotient, remainder = poly_divrem r0 r1 in
        euclid r1 remainder s1 (poly_sub s0 (poly_mul quotient s1))
    in
    euclid modulus (trim a) [||] [| Z.one |]
end

(* Homogeneous projective coordinates (x/z,y/z), intentionally distinct from
   the Jacobian representation commonly used by optimized libraries. *)
let double2 (x, y, z) =
  if Fp2.is_zero z || Fp2.is_zero y then Fp2.one, Fp2.one, Fp2.zero
  else
    let scale n a = Fp2.mul (Fp2.of_int n) a in
    let w = scale 3 (Fp2.square x) in
    let s = Fp2.mul y z in
    let b = Fp2.mul (Fp2.mul x y) s in
    let h = Fp2.sub (Fp2.square w) (scale 8 b) in
    let ss = Fp2.square s in
    scale 2 (Fp2.mul h s),
    Fp2.sub (Fp2.mul w (Fp2.sub (scale 4 b) h)) (scale 8 (Fp2.mul (Fp2.square y) ss)),
    scale 8 (Fp2.mul s ss)

let add2 ((x1, y1, z1) as p1) ((x2, y2, z2) as p2) =
  if Fp2.is_zero z1 then p2 else if Fp2.is_zero z2 then p1
  else
    let u1 = Fp2.mul y2 z1 and u2 = Fp2.mul y1 z2 in
    let v1 = Fp2.mul x2 z1 and v2 = Fp2.mul x1 z2 in
    if Fp2.equal v1 v2 then
      if Fp2.equal u1 u2 then double2 p1 else Fp2.one, Fp2.one, Fp2.zero
    else
      let u = Fp2.sub u1 u2 and v = Fp2.sub v1 v2 in
      let vv = Fp2.square v in
      let vvv = Fp2.mul v vv and vv2 = Fp2.mul vv v2 in
      let w = Fp2.mul z1 z2 in
      let a = Fp2.sub (Fp2.sub (Fp2.mul (Fp2.square u) w) vvv)
          (Fp2.add vv2 vv2) in
      Fp2.mul v a,
      Fp2.sub (Fp2.mul u (Fp2.sub vv2 a)) (Fp2.mul vvv u2),
      Fp2.mul vvv w

let twist ((x0, x1), (y0, y1), (z0, z1)) =
  let x = Array.copy Fp12.zero and y = Array.copy Fp12.zero
  and z = Array.copy Fp12.zero in
  x.(1) <- Fp.sub x0 x1; x.(7) <- x1;
  y.(0) <- Fp.sub y0 y1; y.(6) <- y1;
  z.(3) <- Fp.sub z0 z1; z.(9) <- z1;
  x, y, z

let line (x1, y1, z1) (x2, y2, z2) (xt, yt, zt) =
  let open Fp12 in
  let numerator = sub (mul y2 z1) (mul y1 z2) in
  let denominator = sub (mul x2 z1) (mul x1 z2) in
  let evaluate n d =
    sub (mul n (sub (mul xt z1) (mul x1 zt)))
      (mul d (sub (mul yt z1) (mul y1 zt))),
    mul (mul d zt) z1
  in
  if not (is_zero denominator) then evaluate numerator denominator
  else if is_zero numerator then evaluate (scale 3 (square x1)) (scale 2 (mul y1 z1))
  else sub (mul xt z1) (mul x1 zt), mul z1 zt

let ate_loop = Z.of_string "15132376222941642752"
let scalar_order = Z.of_string
  "52435875175126190479447740508185965837690552500527637822603658699938581184513"
let final_exponent = Z.div (Z.pred (Z.pow Bls_field.p 12)) scalar_order

let miller (x, y) (qx, qy) =
  let p = Fp12.of_fp x, Fp12.of_fp y, Fp12.one in
  let q = qx, qy, Fp2.one in
  let tq = twist q in
  let r = ref q and tr = ref tq in
  let numerator = ref Fp12.one and denominator = ref Fp12.one in
  for i = 62 downto 0 do
    let n, d = line !tr !tr p in
    numerator := Fp12.mul (Fp12.square !numerator) n;
    denominator := Fp12.mul (Fp12.square !denominator) d;
    r := double2 !r;
    tr := twist !r;
    if Z.testbit ate_loop i then begin
      let n, d = line !tr tq p in
      numerator := Fp12.mul !numerator n;
      denominator := Fp12.mul !denominator d;
      r := add2 !r q;
      tr := twist !r
    end
  done;
  !numerator, !denominator

let pairing_check pairs =
  let numerator, denominator = List.fold_left (fun (ns, ds) -> function
    | Bls_group.G1.Infinity, _ | _, Bls_group.G2.Infinity -> ns, ds
    | Bls_group.G1.Point (x, y), Bls_group.G2.Point (qx, qy) ->
      let n, d = miller (x, y) (qx, qy) in
      Fp12.mul ns n, Fp12.mul ds d) (Fp12.one, Fp12.one) pairs
  in
  (* In particular, empty and cancelling products avoid final exponentiation. *)
  Fp12.equal numerator denominator ||
  Fp12.equal (Fp12.pow (Fp12.mul numerator (Fp12.inv denominator)) final_exponent) Fp12.one
