module R = Reference
module V = Mo_values.Value
let unhex s = String.init (String.length s / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub s (i * 2) 2)))
let ok_bool b = Ok (V.Variant ("ok", V.Bool b))
let err e = Ok (V.Variant ("err", V.Variant(e,V.Tup[])))
let invoke name arguments = R.evaluate name [] [] arguments
let assertions = ref 0
let check cond message = incr assertions; if not cond then failwith message
let lines path fn = let chan = open_in path in try while true do fn (input_line chan) done with End_of_file -> close_in chan
let () =
  let tested = ref 0 in
  lines "vectors.txt" (fun line -> match String.split_on_char '|' line with
  | [seed; key; message; signature] ->
      let seed=unhex seed and key=unhex key and message=unhex message and signature=unhex signature in
      check (R.public_key seed = key) "public key vector";
      check (R.sign seed message = signature) "signature vector";
      check (invoke "validate_public_key" [V.Blob key] = ok_bool true) "public key validation";
      check (invoke "verify" [V.Blob key; V.Blob message; V.Blob signature] = ok_bool true) "valid signature";
      check (invoke "verify" [V.Blob key; V.Blob (message ^ "x"); V.Blob signature] = ok_bool false) "wrong message";
      let rs = String.sub signature 0 32 ^ R.to_le 32 R.order in
      check (invoke "verify" [V.Blob key; V.Blob message; V.Blob rs] = err "invalidSignature") "scalar = L";
      List.iter (fun invalid ->
        check (invoke "verify" [V.Blob invalid; V.Blob message; V.Blob signature] = err "invalidPublicKey") "invalid public key";
        if String.length invalid = 32 then
          check (invoke "verify" [V.Blob key; V.Blob message; V.Blob (invalid ^ String.sub signature 32 32)] = err "invalidSignature") "invalid R")
        [""; String.make 31 '\000'; String.make 33 '\000'; String.make 32 '\000';
         "\001" ^ String.make 31 '\000'; R.to_le 32 R.prime;
         R.to_le 32 (R.Z.add (R.Z.shl R.Z.one 255) R.Z.one);
         R.to_le 32 (R.Z.sub R.prime R.Z.one)];
      incr tested
  | _ -> failwith "vector format");
  let sha_cases = ref 0 and sha_splits = ref 0 in
  lines "sha.txt" (fun line -> match String.split_on_char '|' line with
  | [input; digest] ->
      incr sha_cases;
      let input=unhex input and digest=unhex digest in
      check (R.Sha512.digest [input] = digest) "SHA512 whole";
      for split=0 to String.length input do
        incr sha_splits;
        check (R.Sha512.digest [String.sub input 0 split; ""; String.sub input split (String.length input-split)] = digest) "SHA512 split"
      done
  | _ -> failwith "hash format");
  check (invoke "sign" [V.Blob ""; V.Blob ""] = err "invalidSecretKey") "bad seed";
  check (invoke "public_key" [V.Blob ""] = err "invalidSecretKey") "bad seed key";
  (* Construct signatures over A = B + (0, -1), a mixed-order point.
     Dalek's strict equation permits mixed-order points; it excludes small order.
     An odd challenge leaves a nonzero torsion term when R is prime order. *)
  let torsion = R.affine R.Z.zero (R.Z.sub R.prime R.Z.one) in
  let mixed = R.encode (R.point_add R.base torsion) in
  let exercise r parity expected =
    let rec find n =
      let message = string_of_int n in
      let challenge = R.hash_scalar [r; mixed; message] in
      if R.Z.odd challenge = parity then message, challenge else find (n + 1)
    in
    let message, challenge = find 0 in
    let signature = r ^ R.to_le 32 (R.Z.rem (R.Z.add R.Z.one challenge) R.order) in
    check (invoke "verify" [V.Blob mixed; V.Blob message; V.Blob signature] = ok_bool expected)
      "mixed-order equation"
  in
  exercise (R.encode R.base) false true;
  exercise (R.encode R.base) true false;
  exercise mixed true true;
  (* Independent reviewer fixtures: first satisfies strict verification with
     mixed-order A/R; second satisfies only the cofactored equation. *)
  let key = unhex "359dbf604a3b3bedc20d5408b9d4770fbe52c922979b3178d02ab8d41c9c3a4e" in
  let message = unhex "6d697865642d6f72646572207265666572656e636520706172697479" in
  List.iter (fun (signature, expected) ->
    check (invoke "verify" [V.Blob key; V.Blob message; V.Blob (unhex signature)] = ok_bool expected)
      "independent mixed-order fixture")
    ["245c079551b9a0f1a9aec79baef0c668a9e05d3617a15de23dd6dcf60c329fdde1d266e37963bab71e9adb44d4af54d9533a1d3b39ab3061d8c3457187fac10f", true;
     "959999999999999999999999999999999999999999999999999999999999999949b250a17fa374e3cd3d5c80933d3cce17291d406f64b685f4328fabb8b50704", false];
  Printf.printf "{\"signatureCases\":%d,\"shaCases\":%d,\"shaSplitChecks\":%d,\"mixedOrderCases\":5,\"assertions\":%d}\n"
    !tested !sha_cases !sha_splits !assertions
