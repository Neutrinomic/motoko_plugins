(* Portable SHAKE128/SHAKE256 reference semantics, FIPS 202 sections 3 and 6.2.
   Lanes are indexed x + 5*y; bytes within lanes use little endian order. *)

let constants = [|
  0x0000000000000001L; 0x0000000000008082L; 0x800000000000808aL;
  0x8000000080008000L; 0x000000000000808bL; 0x0000000080000001L;
  0x8000000080008081L; 0x8000000000008009L; 0x000000000000008aL;
  0x0000000000000088L; 0x0000000080008009L; 0x000000008000000aL;
  0x000000008000808bL; 0x800000000000008bL; 0x8000000000008089L;
  0x8000000000008003L; 0x8000000000008002L; 0x8000000000000080L;
  0x000000000000800aL; 0x800000008000000aL; 0x8000000080008081L;
  0x8000000000008080L; 0x0000000080000001L; 0x8000000080008008L;
|]

let rotations = [|
   0;  1; 62; 28; 27;
  36; 44;  6; 55; 20;
   3; 10; 43; 25; 39;
  41; 45; 15; 21;  8;
  18;  2; 61; 56; 14;
|]

let ( ^! ) = Int64.logxor
let rotate x n =
  if n = 0 then x
  else Int64.logor (Int64.shift_left x n) (Int64.shift_right_logical x (64 - n))

type t = {
  lanes : int64 array;
  columns : int64 array;
  mixed : int64 array;
  rate : int;
  mutable offset : int;
}

let permute context =
  let a = context.lanes and c = context.columns and b = context.mixed in
  for round = 0 to 23 do
    (* Theta. *)
    for x = 0 to 4 do
      c.(x) <- a.(x) ^! a.(x + 5) ^! a.(x + 10) ^! a.(x + 15) ^! a.(x + 20)
    done;
    for x = 0 to 4 do
      let d = c.((x + 4) mod 5) ^! rotate c.((x + 1) mod 5) 1 in
      for y = 0 to 4 do
        a.(x + 5 * y) <- a.(x + 5 * y) ^! d
      done
    done;
    (* Rho and pi. *)
    for y = 0 to 4 do
      for x = 0 to 4 do
        let i = x + 5 * y in
        b.(y + 5 * ((2 * x + 3 * y) mod 5)) <- rotate a.(i) rotations.(i)
      done
    done;
    (* Chi. *)
    for y = 0 to 4 do
      for x = 0 to 4 do
        a.(x + 5 * y) <- b.(x + 5 * y) ^!
          Int64.logand (Int64.lognot b.((x + 1) mod 5 + 5 * y))
            b.((x + 2) mod 5 + 5 * y)
      done
    done;
    (* Iota. *)
    a.(0) <- a.(0) ^! constants.(round)
  done

let xor_byte context offset byte =
  let i = offset / 8 in
  context.lanes.(i) <- context.lanes.(i) ^!
    Int64.shift_left (Int64.of_int byte) ((offset mod 8) * 8)

let create rate input =
  let context = {
    lanes = Array.make 25 0L;
    columns = Array.make 5 0L;
    mixed = Array.make 25 0L;
    rate;
    offset = 0;
  } in
  let offset = ref 0 in
  while String.length input - !offset >= rate do
    for i = 0 to rate / 8 - 1 do
      context.lanes.(i) <- context.lanes.(i) ^!
        String.get_int64_le input (!offset + 8 * i)
    done;
    permute context;
    offset := !offset + rate
  done;
  let remaining = String.length input - !offset in
  for i = 0 to remaining - 1 do
    xor_byte context i (Char.code input.[!offset + i])
  done;
  (* SHAKE domain suffix 1111 followed by pad10*1. The first five bits
     combine to 0x1f, including when both padding ends share one byte. *)
  xor_byte context remaining 0x1f;
  xor_byte context (rate - 1) 0x80;
  permute context;
  context

let create128 input = create 168 input
let create256 input = create 136 input

let squeeze context length =
  if length < 0 then invalid_arg "Mldsa_shake.squeeze: negative length";
  let result = Bytes.create length in
  for i = 0 to length - 1 do
    if context.offset = context.rate then begin
      permute context;
      context.offset <- 0
    end;
    let lane = context.lanes.(context.offset / 8) in
    let byte = Int64.logand 0xffL
      (Int64.shift_right_logical lane ((context.offset mod 8) * 8)) in
    Bytes.set result i (Char.chr (Int64.to_int byte));
    context.offset <- context.offset + 1
  done;
  Bytes.unsafe_to_string result

let digest128 input length = squeeze (create128 input) length
let digest256 input length = squeeze (create256 input) length
