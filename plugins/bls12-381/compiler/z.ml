(* This module is packed inside the BLS plugin. Num's C primitives are already
   exported by moc; unlike an external Zarith dependency it therefore needs no
   new native library at plugin loading time. Only public Big_int operations
   are used. The API covers the arithmetic used by these reference algorithms. *)
type t = Big_int.big_int
let zero = Big_int.zero_big_int
let one = Big_int.unit_big_int
let minus_one = Big_int.minus_big_int one
let of_int = Big_int.big_int_of_int
let to_int = Big_int.int_of_big_int
let of_string = Big_int.big_int_of_string
let to_string = Big_int.string_of_big_int
let add = Big_int.add_big_int
let sub = Big_int.sub_big_int
let mul = Big_int.mult_big_int
let neg = Big_int.minus_big_int
let succ = Big_int.succ_big_int
let pred = Big_int.pred_big_int
let sign = Big_int.sign_big_int
let compare = Big_int.compare_big_int
let equal = Big_int.eq_big_int
let erem = Big_int.mod_big_int
(* Zarith's div truncates toward zero, whereas Num's div_big_int implements
   Euclidean division. Preserve the former even for negative inputs. *)
let div a b =
  let quotient = Big_int.div_big_int (Big_int.abs_big_int a) (Big_int.abs_big_int b) in
  if sign a * sign b < 0 then neg quotient else quotient
let pow = Big_int.power_big_int_positive_int
let shift_left = Big_int.shift_left_big_int
let shift_right = Big_int.shift_right_big_int
let extract = Big_int.extract_big_int
let testbit n offset = not (equal (extract n offset 1) zero)
let numbits = Big_int.num_bits_big_int

let invert value modulus =
  if sign modulus <= 0 then invalid_arg "BLS integer inverse requires positive modulus";
  let rec loop r next_r coefficient next_coefficient =
    if equal next_r zero then
      if equal r one then erem coefficient modulus else raise Division_by_zero
    else
      let quotient, remainder = Big_int.quomod_big_int r next_r in
      loop next_r remainder next_coefficient (sub coefficient (mul quotient next_coefficient))
  in
  loop modulus (erem value modulus) zero one

let powm base exponent modulus =
  if sign modulus <= 0 then invalid_arg "BLS integer power requires positive modulus";
  let base, exponent = if sign exponent < 0 then invert base modulus, neg exponent else base, exponent in
  let base = erem base modulus in
  let total = ref (erem one modulus) in
  for bit = numbits exponent - 1 downto 0 do
    total := erem (Big_int.square_big_int !total) modulus;
    if testbit exponent bit then total := erem (mul !total base) modulus
  done;
  !total

let ( + ) = add
let ( - ) = sub
let ( * ) = mul
