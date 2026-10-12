(* Field definitions from the BLS12-381 curve specification. All operations
   normalize residues, including negative integers. This reference code is
   deliberately independent of the optimized Wasm implementation. *)
let p = Z.of_string "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
let r = Z.of_string "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"

let z_of_be bytes =
  String.fold_left (fun n c -> Z.(add (shift_left n 8) (of_int (Char.code c)))) Z.zero bytes

let be_of_z size n =
  if Z.sign n < 0 || Z.numbits n > size * 8 then
    invalid_arg "BLS12-381 integer encoding out of range";
  String.init size (fun i -> Char.chr (Z.to_int (Z.extract n (8 * (size - i - 1)) 8)))

module type FIELD = sig
  type t
  val zero : t
  val one : t
  val of_z : Z.t -> t
  val of_int : int -> t
  val equal : t -> t -> bool
  val is_zero : t -> bool
  val add : t -> t -> t
  val sub : t -> t -> t
  val neg : t -> t
  val mul : t -> t -> t
  val square : t -> t
  val inv : t -> t
  val div : t -> t -> t
  val pow : t -> Z.t -> t
  val sqrt : t -> t option
  val sign : t -> bool
  val sgn0 : t -> bool
end

module Fp = struct
  type t = Z.t
  let modulus = p
  let zero = Z.zero
  let one = Z.one
  let of_z x = Z.erem x p
  let of_int x = of_z (Z.of_int x)
  let equal = Z.equal
  let is_zero x = equal x zero
  let add a b = of_z Z.(a + b)
  let sub a b = of_z Z.(a - b)
  let neg a = of_z (Z.neg a)
  let mul a b = of_z Z.(a * b)
  let square a = mul a a
  let inv a = if is_zero a then invalid_arg "BLS12-381 inverse of zero" else Z.invert a p
  let div a b = mul a (inv b)
  let pow a n = Z.powm a n p
  let sqrt_exponent = Z.(div (succ p) (of_int 4))
  let sqrt a =
    let candidate = pow a sqrt_exponent in
    if equal (square candidate) a then Some candidate else None
  let sign a = Z.compare (Z.shift_left a 1) p > 0
  let sgn0 a = Z.testbit a 0
  let of_bytes bytes =
    if String.length bytes <> 48 then Error "invalid field length"
    else let n = z_of_be bytes in
      if Z.compare n p >= 0 then Error "noncanonical field element" else Ok n
  let to_bytes = be_of_z 48
end

module Fp2 = struct
  (* Fp[i] / (i^2 + 1), real component first. *)
  type t = Fp.t * Fp.t
  let zero = Fp.zero, Fp.zero
  let one = Fp.one, Fp.zero
  let of_z n = Fp.of_z n, Fp.zero
  let of_int n = of_z (Z.of_int n)
  let equal (a,b) (c,d) = Fp.equal a c && Fp.equal b d
  let is_zero n = equal n zero
  let add (a,b) (c,d) = Fp.add a c, Fp.add b d
  let sub (a,b) (c,d) = Fp.sub a c, Fp.sub b d
  let neg (a,b) = Fp.neg a, Fp.neg b
  let mul (a,b) (c,d) =
    Fp.sub (Fp.mul a c) (Fp.mul b d), Fp.add (Fp.mul a d) (Fp.mul b c)
  let square (a,b) = Fp.mul (Fp.add a b) (Fp.sub a b), Fp.mul (Fp.of_int 2) (Fp.mul a b)
  let inv (a,b) =
    let scale = Fp.inv (Fp.add (Fp.square a) (Fp.square b)) in
    Fp.mul a scale, Fp.neg (Fp.mul b scale)
  let div a b = mul a (inv b)
  let pow value n =
    let value, n = if Z.sign n < 0 then inv value, Z.neg n else value, n in
    let rec loop acc value n =
      if Z.equal n Z.zero then acc
      else loop (if Z.testbit n 0 then mul acc value else acc)
          (square value) (Z.shift_right n 1)
    in loop one value n
  let half = Fp.inv (Fp.of_int 2)
  let sqrt ((a,b) as value) =
    if Fp.is_zero b then
      (match Fp.sqrt a with
       | Some x -> Some (x,Fp.zero)
       | None -> Option.map (fun y -> Fp.zero,y) (Fp.sqrt (Fp.neg a)))
    else
      match Fp.sqrt (Fp.add (Fp.square a) (Fp.square b)) with
      | None -> None
      | Some norm ->
        let candidate sign = Fp.sqrt (Fp.mul (Fp.add a sign) half) in
        let root = match candidate norm with
          | Some x when not (Fp.is_zero x) -> Some x
          | _ -> candidate (Fp.neg norm)
        in
        (match root with
         | None -> None
         | Some x when Fp.is_zero x -> None
         | Some x ->
           let answer = x, Fp.div b (Fp.add x x) in
           if equal (square answer) value then Some answer else None)
  let sign (a,b) = if Fp.is_zero b then Fp.sign a else Fp.sign b
  let sgn0 (a,b) = Fp.sgn0 a || (Fp.is_zero a && Fp.sgn0 b)
  let of_bytes bytes =
    if String.length bytes <> 96 then Error "invalid extension-field length"
    else match Fp.of_bytes (String.sub bytes 0 48), Fp.of_bytes (String.sub bytes 48 48) with
      | Ok a, Ok b -> Ok (a,b)
      | Error e, _ | _, Error e -> Error e
  let to_bytes (a,b) = Fp.to_bytes a ^ Fp.to_bytes b
end
