module R = Reference
module V = Mo_values.Value
let unhex s = String.init (String.length s / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub s (i * 2) 2)))
let ok_bool b = Ok (V.Variant ("ok", V.Bool b))
let err label = Ok (V.Variant ("err", V.Variant (label, V.Tup [])))
let prepared name args = R.evaluate_prepared ~public_key:() ~secret_key:() name [] [] args
let direct name args = R.evaluate name [] [] args
let assertions = ref 0
let check condition message = incr assertions; if not condition then failwith message
let handle = function Ok (V.Variant ("ok", value)) -> value | _ -> failwith "expected prepared handle"
let bytes = function V.Blob bytes -> bytes | _ -> failwith "expected backing Blob"
let lines path fn = let file = open_in path in try while true do fn (input_line file) done with End_of_file -> close_in file
let () =
  let signature_cases = ref 0 and adversarial_cases = ref 0 in
  lines "prepared-vectors.txt" (fun line -> match String.split_on_char '|' line with
  | [seed; public_key; message; signature] ->
      let seed = unhex seed and public_key = unhex public_key in
      let message = unhex message and signature = unhex signature in
      let secret = handle (prepared "prepare_secret_key" [V.Blob seed]) in
      let public = handle (prepared "prepare_public_key" [V.Blob public_key]) in
      let snapshot = bytes secret in
      check (String.length snapshot = 96) "secret payload length";
      check (R.Z.compare (R.from_le (String.sub snapshot 0 32)) R.order < 0) "canonical saved scalar";
      check (String.sub snapshot 64 32 = public_key) "secret/public binding";
      check (prepared "sign_prepared" [secret; V.Blob message] = Ok (V.Blob signature)) "prepared signing oracle";
      check (prepared "verify_prepared" [public; V.Blob message; V.Blob signature] = ok_bool true) "prepared verification oracle";
      check (prepared "verify_prepared" [public; V.Blob (message ^ "x"); V.Blob signature] = ok_bool false) "wrong message";
      let altered = message ^ "x" in
      let altered_signature = R.sign seed altered in
      check (prepared "sign_prepared" [secret; V.Blob altered] = Ok (V.Blob altered_signature)) "reuse with different message";
      check (prepared "verify_prepared" [public; V.Blob altered; V.Blob altered_signature] = ok_bool true) "reuse verification";
      check (prepared "sign_prepared" [secret; V.Blob message] = Ok (V.Blob signature)) "reuse deterministic original";
      check (bytes secret = snapshot && bytes public = public_key) "prepared payload immutability";
      incr signature_cases
  | _ -> failwith "signature vector format");
  lines "adversarial.txt" (fun line -> match String.split_on_char '|' line with
  | [name; public_key; message; signature; expected] ->
      let public_key = unhex public_key and message = unhex message and signature = unhex signature in
      let expected = match expected with "true" -> ok_bool true | "false" -> ok_bool false | label -> err label in
      let actual = match prepared "prepare_public_key" [V.Blob public_key] with
        | Ok (V.Variant ("ok", public)) -> prepared "verify_prepared" [public; V.Blob message; V.Blob signature]
        | result -> result
      in
      check (actual = expected) (name ^ " prepared oracle");
      check (actual = direct "verify" [V.Blob public_key; V.Blob message; V.Blob signature]) (name ^ " direct parity");
      incr adversarial_cases
  | _ -> failwith "adversarial vector format");
  List.iter (fun length ->
    check (prepared "prepare_secret_key" [V.Blob (String.make length '\000')] = err "invalidSecretKey") "invalid seed length")
    [0; 1; 31; 33; 63; 64; 65];
  (* Both all-zero and all-ones seeds are valid Ed25519 seeds, not scalar encodings. *)
  List.iter (fun byte ->
    let seed = String.make 32 byte in
    let secret = handle (prepared "prepare_secret_key" [V.Blob seed]) in
    check (prepared "sign_prepared" [secret; V.Blob "seed boundary"] = Ok (V.Blob (R.sign seed "seed boundary"))) "valid seed boundary")
    ['\000'; '\255'];
  Printf.printf "{\"signatureCases\":%d,\"adversarialCases\":%d,\"assertions\":%d}\n"
    !signature_cases !adversarial_cases !assertions
