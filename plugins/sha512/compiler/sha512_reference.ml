(* Portable SHA-512/SHA-384 semantics for both Motoko interpreters.
   Algorithm and constants: FIPS 180-4, sections 4.2.3, 5.3.4, 5.3.5, 6.4, 6.5.
   https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf

   State format (all words big endian):
     0..3   "S512"
     4      digest size in bytes: 64 or 48
     5..7   zero
     8..71  eight chaining words
     72..87 total byte count (u128, less than 2^125)
     88..215 pending bytes; unused bytes must be zero
   The pending byte count is the total byte count modulo 128. *)

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

let initial384 = [|
  0xcbbb9d5dc1059ed8L; 0x629a292a367cd507L; 0x9159015a3070dd17L; 0x152fecd8f70e5939L;
  0x67332667ffc00b31L; 0x8eb44a8768581511L; 0xdb0c2e0d64f98fa7L; 0x47b5481dbefa4fa4L;
|]

let ( +! ) = Int64.add
let ( ^! ) = Int64.logxor
let ( &! ) = Int64.logand
let shr = Int64.shift_right_logical
let ror x n = Int64.logor (shr x n) (Int64.shift_left x (64 - n))
let sigma0 x = ror x 1 ^! ror x 8 ^! shr x 7
let sigma1 x = ror x 19 ^! ror x 61 ^! shr x 6

let initial sha384 = Array.copy (if sha384 then initial384 else initial512)

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

let compress state input offset =
  compress_with_words state (Array.make 80 0L) input offset

let serialize output_size state high low =
  let result = Bytes.make 216 '\x00' in
  Bytes.blit_string "S512" 0 result 0 4;
  Bytes.set result 4 (Char.chr output_size);
  Array.iteri (fun i word -> Bytes.set_int64_be result (8 + 8 * i) word) state;
  Bytes.set_int64_be result 72 high;
  Bytes.set_int64_be result 80 low;
  result

let init sha384 =
  Bytes.unsafe_to_string
    (serialize (if sha384 then 48 else 64)
      (if sha384 then initial384 else initial512) 0L 0L)

let decode input =
  if String.length input <> 216 || String.sub input 0 4 <> "S512" ||
     (input.[4] <> '\x40' && input.[4] <> '\x30') ||
     input.[5] <> '\x00' || input.[6] <> '\x00' || input.[7] <> '\x00' ||
     Char.code input.[72] land 0xe0 <> 0
  then None
  else
    let count = Char.code input.[87] land 127 in
    let canonical = ref true in
    for i = 88 + count to 215 do
      if input.[i] <> '\x00' then canonical := false
    done;
    if not !canonical then None
    else
      let output_size = Char.code input.[4] in
      let state = Array.init 8 (fun i -> String.get_int64_be input (8 + 8 * i)) in
      let high = String.get_int64_be input 72 in
      let low = String.get_int64_be input 80 in
      (* Before the first complete block, the chaining words are still the IV.
         This also rejects switching the mode of an uncompressed state. *)
      if high = 0L && Int64.unsigned_compare low 128L < 0 &&
         state <> (if output_size = 48 then initial384 else initial512)
      then None
      else Some (output_size, state, high, low, count)

let update serialized input =
  match decode serialized with
  | None -> None
  | Some (output_size, state, high, low, count) ->
    let length = String.length input in
    let next_low = low +! Int64.of_int length in
    let carry = if Int64.unsigned_compare next_low low < 0 then 1L else 0L in
    let next_high = high +! carry in
    if Int64.compare next_high 0x1fffffffffffffffL > 0 then None
    else begin
      let words = Array.make 80 0L in
      let offset = ref 0 in
      let pending = Bytes.make 128 '\x00' in
      let pending_count = ref count in
      if count > 0 then begin
        Bytes.blit_string serialized 88 pending 0 count;
        let take = min (128 - count) length in
        Bytes.blit_string input 0 pending count take;
        offset := take;
        pending_count := count + take;
        if !pending_count = 128 then begin
          compress_with_words state words (Bytes.unsafe_to_string pending) 0;
          Bytes.fill pending 0 128 '\x00';
          pending_count := 0
        end
      end;
      while length - !offset >= 128 do
        compress_with_words state words input !offset;
        offset := !offset + 128
      done;
      let remaining = length - !offset in
      if remaining > 0 then begin
        Bytes.blit_string input !offset pending !pending_count remaining;
        pending_count := !pending_count + remaining
      end;
      let result = serialize output_size state next_high next_low in
      Bytes.blit pending 0 result 88 !pending_count;
      Some (Bytes.unsafe_to_string result)
    end

let sum serialized =
  match decode serialized with
  | None -> None
  | Some (output_size, state, high, low, count) ->
    let padded = if count < 112 then 128 else 256 in
    let tail = Bytes.make padded '\x00' in
    Bytes.blit_string serialized 88 tail 0 count;
    Bytes.set tail count '\x80';
    Bytes.set_int64_be tail (padded - 16)
      (Int64.logor (Int64.shift_left high 3) (shr low 61));
    Bytes.set_int64_be tail (padded - 8) (Int64.shift_left low 3);
    let words = Array.make 80 0L in
    let tail = Bytes.unsafe_to_string tail in
    compress_with_words state words tail 0;
    if padded = 256 then compress_with_words state words tail 128;
    let result = Bytes.create output_size in
    for i = 0 to output_size / 8 - 1 do
      Bytes.set_int64_be result (8 * i) state.(i)
    done;
    Some (Bytes.unsafe_to_string result)

let digest_with sha384 input =
  match update (init sha384) input with
  | None -> assert false (* A single OCaml string cannot exceed 2^125 bytes. *)
  | Some state ->
    match sum state with Some result -> result | None -> assert false

let digest = digest_with false
let digest384 = digest_with true
