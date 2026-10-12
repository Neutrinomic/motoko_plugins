(* Independent portable interpreter implementation of BIP173/BIP350. *)

let alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
let generators =
  [| 0x3b6a57b2; 0x26508e6d; 0x1ea119fa; 0x3d4233dd; 0x2a1462b3 |]
let bech32m_constant = 0x2bc830a3
let max_conversion_bytes = 16 * 1024 * 1024

exception Invalid of int
let fail code = raise (Invalid code)
let protect f = try Ok (f ()) with Invalid code -> Error code

(* The checksum is always below 2^30, including on a 32-bit OCaml host. *)
let polymod_step checksum value =
  let high = checksum lsr 25 in
  let next = ref (((checksum land 0x1ffffff) lsl 5) lxor value) in
  for i = 0 to 4 do
    if high land (1 lsl i) <> 0 then
      next := !next lxor generators.(i)
  done;
  !next

let hrp_checksum hrp =
  let checksum = ref 1 in
  String.iter (fun c -> checksum := polymod_step !checksum (Char.code c lsr 5)) hrp;
  checksum := polymod_step !checksum 0;
  String.iter (fun c -> checksum := polymod_step !checksum (Char.code c land 31)) hrp;
  !checksum

let check_printable error text =
  String.iter (fun c ->
    let value = Char.code c in
    if value < 33 || value > 126 then fail error
  ) text

let check_case text =
  let lower = ref false and upper = ref false in
  String.iter (fun c ->
    if c >= 'a' && c <= 'z' then lower := true;
    if c >= 'A' && c <= 'Z' then upper := true
  ) text;
  if !lower && !upper then fail 3

let encode hrp payload bech32m = protect (fun () ->
  let hrp_len = String.length hrp in
  let data_len = String.length payload in
  if hrp_len > 83 then fail 1;
  if hrp_len = 0 then fail 2;
  check_printable 2 hrp;
  (* Subtraction avoids overflow for very large payloads. *)
  if data_len > 83 - hrp_len then fail 1;
  check_case hrp;
  String.iter (fun c -> if Char.code c > 31 then fail 6) payload;
  let hrp = String.lowercase_ascii hrp in
  let checksum = ref (hrp_checksum hrp) in
  let out = Bytes.create (hrp_len + data_len + 7) in
  Bytes.blit_string hrp 0 out 0 hrp_len;
  Bytes.set out hrp_len '1';
  String.iteri (fun i c ->
    let value = Char.code c in
    checksum := polymod_step !checksum value;
    Bytes.set out (hrp_len + 1 + i) alphabet.[value]
  ) payload;
  for _ = 0 to 5 do checksum := polymod_step !checksum 0 done;
  checksum := !checksum lxor (if bech32m then bech32m_constant else 1);
  for i = 0 to 5 do
    let value = (!checksum lsr (5 * (5 - i))) land 31 in
    Bytes.set out (hrp_len + data_len + 1 + i) alphabet.[value]
  done;
  Bytes.to_string out
)

let alphabet_values =
  let values = Array.make 128 (-1) in
  String.iteri (fun i c -> values.(Char.code c) <- i) alphabet;
  values

let decode encoded = protect (fun () ->
  let len = String.length encoded in
  if len < 8 || len > 90 then fail 1;
  check_printable 4 encoded;
  check_case encoded;
  let separator = try String.rindex encoded '1' with Not_found -> fail 2 in
  if separator = 0 then fail 2;
  if len - separator - 1 < 6 then fail 1;
  let encoded = String.lowercase_ascii encoded in
  let hrp = String.sub encoded 0 separator in
  let data_len = len - separator - 7 in
  let payload = Bytes.create data_len in
  let checksum = ref (hrp_checksum hrp) in
  for i = separator + 1 to len - 1 do
    let value = alphabet_values.(Char.code encoded.[i]) in
    if value < 0 then fail 4;
    checksum := polymod_step !checksum value;
    let payload_index = i - separator - 1 in
    if payload_index < data_len then Bytes.set payload payload_index (Char.chr value)
  done;
  let bech32m =
    if !checksum = 1 then false
    else if !checksum = bech32m_constant then true
    else fail 5
  in
  hrp, Bytes.to_string payload, bech32m
)

let convert_bits input from_bits to_bits pad = protect (fun () ->
  if from_bits < 1 || from_bits > 8 || to_bits < 1 || to_bits > 8 then fail 8;
  let input_len = String.length input in
  if input_len > max_conversion_bytes then fail 1;
  let total_bits = input_len * from_bits in
  let output_len = (total_bits + (if pad then to_bits - 1 else 0)) / to_bits in
  if output_len > max_conversion_bytes then fail 1;
  let input_mask = (1 lsl from_bits) - 1 in
  let output_mask = (1 lsl to_bits) - 1 in
  (* At most from_bits + to_bits - 1 relevant bits survive each input. *)
  let accumulator_mask = (1 lsl (from_bits + to_bits - 1)) - 1 in
  let accumulator = ref 0 and bits = ref 0 and position = ref 0 in
  let output = Bytes.create output_len in
  String.iter (fun c ->
    let value = Char.code c in
    if value > input_mask then fail 6;
    accumulator := ((!accumulator lsl from_bits) lor value) land accumulator_mask;
    bits := !bits + from_bits;
    while !bits >= to_bits do
      bits := !bits - to_bits;
      Bytes.set output !position (Char.chr ((!accumulator lsr !bits) land output_mask));
      incr position
    done
  ) input;
  if pad then begin
    if !bits > 0 then
      Bytes.set output !position (Char.chr ((!accumulator lsl (to_bits - !bits)) land output_mask))
  end else if !bits >= from_bits ||
    ((!accumulator lsl (to_bits - !bits)) land output_mask) <> 0 then fail 7;
  Bytes.to_string output
)
