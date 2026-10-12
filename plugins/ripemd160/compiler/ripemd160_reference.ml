(* Portable RIPEMD-160 semantics for the Motoko interpreters.
   Algorithm and independent test vectors:
   https://homes.esat.kuleuven.be/~bosselae/ripemd160.html

   The canonical 104-byte streaming state is shared with the Wasm runtime:
     0..3    "R160"
     4..7    zero (reserved)
     8..15   total input bytes, little endian (at most 2^61 - 1)
    16..35   five chaining words, little endian
    36..39   zero (reserved)
    40..103  pending bytes, followed by zeroes to the end of the buffer
   The pending byte count is total mod 64. A state with fewer than 64 input
   bytes must retain the initial chaining words. States are data, not secrets
   or authenticated proofs that a particular prefix was hashed. *)

let initial = [|
  0x67452301l; 0xefcdab89l; 0x98badcfel; 0x10325476l; 0xc3d2e1f0l;
|]

let left_words = [|
   0;  1;  2;  3;  4;  5;  6;  7;  8;  9; 10; 11; 12; 13; 14; 15;
   7;  4; 13;  1; 10;  6; 15;  3; 12;  0;  9;  5;  2; 14; 11;  8;
   3; 10; 14;  4;  9; 15;  8;  1;  2;  7;  0;  6; 13; 11;  5; 12;
   1;  9; 11; 10;  0;  8; 12;  4; 13;  3;  7; 15; 14;  5;  6;  2;
   4;  0;  5;  9;  7; 12;  2; 10; 14;  1;  3;  8; 11;  6; 15; 13;
|]

let right_words = [|
   5; 14;  7;  0;  9;  2; 11;  4; 13;  6; 15;  8;  1; 10;  3; 12;
   6; 11;  3;  7;  0; 13;  5; 10; 14; 15;  8; 12;  4;  9;  1;  2;
  15;  5;  1;  3;  7; 14;  6;  9; 11;  8; 12;  2; 10;  0;  4; 13;
   8;  6;  4;  1;  3; 11; 15;  0;  5; 12;  2; 13;  9;  7; 10; 14;
  12; 15; 10;  4;  1;  5;  8;  7;  6;  2; 13; 14;  0;  3;  9; 11;
|]

let left_shifts = [|
  11; 14; 15; 12;  5;  8;  7;  9; 11; 13; 14; 15;  6;  7;  9;  8;
   7;  6;  8; 13; 11;  9;  7; 15;  7; 12; 15;  9; 11;  7; 13; 12;
  11; 13;  6;  7; 14;  9; 13; 15; 14;  8; 13;  6;  5; 12;  7;  5;
  11; 12; 14; 15; 14; 15;  9;  8;  9; 14;  5;  6;  8;  6;  5; 12;
   9; 15;  5; 11;  6;  8; 13; 12;  5; 12; 13; 14; 11;  8;  5;  6;
|]

let right_shifts = [|
   8;  9;  9; 11; 13; 15; 15;  5;  7;  7;  8; 11; 14; 14; 12;  6;
   9; 13; 15;  7; 12;  8;  9; 11;  7;  7; 12;  7;  6; 15; 13; 11;
   9;  7; 15; 11;  8;  6;  6; 14; 12; 13;  5; 14; 13; 13;  7;  5;
  15;  5;  8; 11; 14; 14;  6; 14;  6;  9; 12;  9; 12;  5; 15;  8;
   8;  5; 12;  9; 12;  5; 14;  6;  8; 13;  6;  5; 15; 13; 11; 11;
|]

let left_constants = [|
  0x00000000l; 0x5a827999l; 0x6ed9eba1l; 0x8f1bbcdcl; 0xa953fd4el;
|]

let right_constants = [|
  0x50a28be6l; 0x5c4dd124l; 0x6d703ef3l; 0x7a6d76e9l; 0x00000000l;
|]

let ( +! ) = Int32.add
let ( ^! ) = Int32.logxor
let ( &! ) = Int32.logand
let ( |! ) = Int32.logor
let not32 = Int32.lognot
let rol value amount =
  Int32.shift_left value amount |! Int32.shift_right_logical value (32 - amount)

let nonlinear round x y z =
  match round with
  | 0 -> x ^! y ^! z
  | 1 -> (x &! y) |! (not32 x &! z)
  | 2 -> (x |! not32 y) ^! z
  | 3 -> (x &! z) |! (y &! not32 z)
  | _ -> x ^! (y |! not32 z)

let compress state bytes offset =
  let words = Array.init 16 (fun i -> String.get_int32_le bytes (offset + 4 * i)) in
  let a = ref state.(0) and b = ref state.(1) and c = ref state.(2) in
  let d = ref state.(3) and e = ref state.(4) in
  let aa = ref !a and bb = ref !b and cc = ref !c in
  let dd = ref !d and ee = ref !e in
  for j = 0 to 79 do
    let round = j / 16 in
    let next = rol
      (!a +! nonlinear round !b !c !d +! words.(left_words.(j)) +! left_constants.(round))
      left_shifts.(j) +! !e in
    a := !e; e := !d; d := rol !c 10; c := !b; b := next;
    let next = rol
      (!aa +! nonlinear (4 - round) !bb !cc !dd +! words.(right_words.(j)) +! right_constants.(round))
      right_shifts.(j) +! !ee in
    aa := !ee; ee := !dd; dd := rol !cc 10; cc := !bb; bb := next
  done;
  let next0 = state.(1) +! !c +! !dd in
  state.(1) <- state.(2) +! !d +! !ee;
  state.(2) <- state.(3) +! !e +! !aa;
  state.(3) <- state.(4) +! !a +! !bb;
  state.(4) <- state.(0) +! !b +! !cc;
  state.(0) <- next0

let max_length = 0x1fffffffffffffffL
let invalid_state = "RIPEMD160: invalid state"
let message_too_long = "RIPEMD160: message too long"

let zeroes bytes start count =
  let valid = ref true in
  for i = start to start + count - 1 do
    if bytes.[i] <> '\x00' then valid := false
  done;
  !valid

let decode state =
  if String.length state <> 104 || String.sub state 0 4 <> "R160" ||
     not (zeroes state 4 4 && zeroes state 36 4)
  then Error invalid_state
  else
    let total = String.get_int64_le state 8 in
    if Int64.compare total 0L < 0 || Int64.compare total max_length > 0 then
      Error invalid_state
    else
      let used = Int64.to_int (Int64.logand total 63L) in
      let words = Array.init 5 (fun i -> String.get_int32_le state (16 + 4 * i)) in
      if not (zeroes state (40 + used) (64 - used)) ||
         (Int64.compare total 64L < 0 && words <> initial)
      then Error invalid_state
      else Ok (total, used, words)

let encode total words pending offset count =
  let result = Bytes.make 104 '\x00' in
  Bytes.blit_string "R160" 0 result 0 4;
  Bytes.set_int64_le result 8 total;
  Array.iteri (fun i word -> Bytes.set_int32_le result (16 + 4 * i) word) words;
  Bytes.blit_string pending offset result 40 count;
  Bytes.unsafe_to_string result

let init () = encode 0L initial "" 0 0

let update state input =
  match decode state with
  | Error _ as error -> error
  | Ok (total, used, words) ->
      let length = String.length input in
      let added = Int64.of_int length in
      if Int64.compare added (Int64.sub max_length total) > 0 then
        Error message_too_long
      else
        let total = Int64.add total added in
        if length < 64 - used then (
          let result = Bytes.of_string state in
          Bytes.set_int64_le result 8 total;
          Bytes.blit_string input 0 result (40 + used) length;
          Ok (Bytes.unsafe_to_string result)
        ) else (
          let offset = ref 0 in
          if used > 0 then (
            let buffer = Bytes.create 64 in
            Bytes.blit_string state 40 buffer 0 used;
            Bytes.blit_string input 0 buffer used (64 - used);
            compress words (Bytes.unsafe_to_string buffer) 0;
            offset := 64 - used
          );
          while length - !offset >= 64 do
            compress words input !offset;
            offset := !offset + 64
          done;
          Ok (encode total words input !offset (length - !offset))
        )

let finalize state =
  match decode state with
  | Error _ as error -> error
  | Ok (total, used, words) ->
      let padded = if used < 56 then 64 else 128 in
      let tail = Bytes.make padded '\x00' in
      Bytes.blit_string state 40 tail 0 used;
      Bytes.set tail used '\x80';
      Bytes.set_int64_le tail (padded - 8) (Int64.shift_left total 3);
      let tail = Bytes.unsafe_to_string tail in
      compress words tail 0;
      if padded = 128 then compress words tail 64;
      let result = Bytes.create 20 in
      Array.iteri (fun i word -> Bytes.set_int32_le result (4 * i) word) words;
      Ok (Bytes.unsafe_to_string result)

let digest input =
  match update (init ()) input with
  | Error message -> invalid_arg message
  | Ok state ->
      match finalize state with
      | Ok output -> output
      | Error message -> invalid_arg message
