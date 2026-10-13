(* Portable executable specification. No native code, subprocess, or retained state. *)
module V = Mo_values.Value
module G1 = Bls_group.G1
module G2 = Bls_group.G2
exception Invalid of string
let fail label = raise (Invalid label)
let length expected bytes = if String.length bytes <> expected then fail "invalidLength"
let parsed label = function Ok x -> x | Error _ -> fail label
let g1 bytes = length 48 bytes; parsed "invalidPoint" (G1.of_compressed bytes)
let g2 bytes = length 96 bytes; parsed "invalidPoint" (G2.of_compressed bytes)
let scalar bytes = length 32 bytes; parsed "invalidScalar" (Bls_group.scalar_of_bytes bytes)
let count width bytes =
  if String.length bytes mod width <> 0 then fail "invalidLength";
  let n = String.length bytes / width in
  if n > 128 then fail "tooManyItems";
  n
let chunks width parse bytes =
  let n = count width bytes in
  List.init n (fun i -> parse (String.sub bytes (i*width) width))
let nonzero1 p = if G1.is_infinity p then fail "identity"; p
let nonzero2 p = if G2.is_infinity p then fail "identity"; p
let dst_ic = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"
let dst_eth = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
let dst_pop = "BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
let as_blob = function V.Blob b -> b | _ -> fail "invalidArgument"
let as_blobs = function
  | V.Array a -> Array.to_list (Array.map as_blob a)
  | _ -> fail "invalidArgument"

(* A portable mathematical specification of the fused profiles. Successful
   proof checks may be reused only for an exact key/proof pair in this call. *)
let checked_keys keys proofs =
  let rec loop seen keys proofs = match keys, proofs with
    | [], [] -> []
    | key :: keys, proof :: proofs ->
      let decoded = match List.find_opt (fun (k, p, _) -> k = key && p = proof) seen with
        | Some (_, _, decoded) -> decoded
        | None ->
          let decoded = g1 key in
          let proof_point = g2 proof in
          let decoded = nonzero1 decoded in
          let proof_point = nonzero2 proof_point in
          if not (Bls_pairing.pairing_check [
            decoded, Bls_hash.hash_g2 ~dst:dst_pop key;
            G1.neg G1.generator, proof_point]) then fail "invalidProof";
          decoded in
      let rest = loop ((key, proof, decoded) :: seen) keys proofs in
      decoded :: rest
    | _ -> fail "invalidLength" in
  loop [] keys proofs

let aggregate opcode arguments =
  let keys, proofs, messages, signature = match opcode, arguments with
    | 19, [keys; messages; signature] ->
      as_blobs keys, [], as_blobs messages, as_blob signature
    | 20, [keys; proofs; messages; signature] ->
      as_blobs keys, as_blobs proofs, as_blobs messages, as_blob signature
    | 21, [keys; proofs; message; signature] ->
      as_blobs keys, as_blobs proofs, [as_blob message], as_blob signature
    | _ -> fail "invalidArgument" in
  let n = List.length keys in
  if (opcode <> 21 && n <> List.length messages) ||
     (opcode <> 19 && n <> List.length proofs) then fail "invalidLength";
  if n = 0 then fail "emptyBatch";
  if n > (if opcode = 21 then 128 else 127) then fail "tooManyItems";
  let check terms = V.Bool (Bls_pairing.pairing_check terms) in
  match opcode with
  | 19 ->
    let rec distinct seen = function
      | [] -> ()
      | message :: rest ->
        if List.mem message seen then fail "duplicateMessage";
        distinct (message :: seen) rest in
    distinct [] messages;
    let signature = nonzero1 (g1 signature) in
    let terms = List.map2 (fun key message ->
      let key = nonzero2 (g2 key) in
      Bls_hash.hash_g1 ~dst:dst_ic message, key) keys messages in
    check ((G1.neg signature, G2.generator) :: terms)
  | 20 ->
    let signature = nonzero2 (g2 signature) in
    let keys = checked_keys keys proofs in
    let terms = List.map2 (fun key message ->
      key, Bls_hash.hash_g2 ~dst:dst_eth message) keys messages in
    check ((G1.neg G1.generator, signature) :: terms)
  | 21 ->
    let keys = checked_keys keys proofs in
    let key = List.fold_left G1.add G1.infinity keys in
    (* Preserve verifyEthereum's order: signature decoding precedes the
       aggregate-key identity check; that check precedes signature identity. *)
    let signature = g2 signature in
    let key = nonzero1 key in
    let signature = nonzero2 signature in
    check [key, Bls_hash.hash_g2 ~dst:dst_eth (List.hd messages);
      G1.neg G1.generator, signature]
  | _ -> fail "invalidArgument"

let blob_operation opcode arguments =
    let args = List.map as_blob arguments in
    match opcode,args with
    | 1,[a] -> V.Blob (G1.to_compressed (g1 a))
    | 2,[a] -> V.Blob (G2.to_compressed (g2 a))
    | 3,[a;b] -> let a=g1 a in let b=g1 b in V.Blob (G1.to_compressed (G1.add a b))
    | 4,[a;b] -> let a=g2 a in let b=g2 b in V.Blob (G2.to_compressed (G2.add a b))
    | 5,[a;s] -> let a=g1 a in let s=scalar s in V.Blob (G1.to_compressed (G1.mul a s))
    | 6,[a;s] -> let a=g2 a in let s=scalar s in V.Blob (G2.to_compressed (G2.mul a s))
    | 7,[points;scalars] ->
      let n=count 48 points in let ns=count 32 scalars in
      if n<>ns then fail "invalidLength";
      let pairs=List.init n (fun i -> let p=g1 (String.sub points (i*48) 48) in
        let s=scalar (String.sub scalars (i*32) 32) in p,s) in
      V.Blob (G1.to_compressed (G1.msm pairs))
    | 8,[points;scalars] ->
      let n=count 96 points in let ns=count 32 scalars in
      if n<>ns then fail "invalidLength";
      let pairs=List.init n (fun i -> let p=g2 (String.sub points (i*96) 96) in
        let s=scalar (String.sub scalars (i*32) 32) in p,s) in
      V.Blob (G2.to_compressed (G2.msm pairs))
    | 9,[field] -> length 48 field;
      V.Blob (G1.to_compressed (parsed "invalidField" (Bls_hash.map_g1 field)))
    | 10,[field] -> length 96 field;
      V.Blob (G2.to_compressed (parsed "invalidField" (Bls_hash.map_g2 field)))
    | 11,[msg;dst] -> if dst="" then fail "invalidArgument"; V.Blob (G1.to_compressed (Bls_hash.hash_g1 ~dst msg))
    | 12,[msg;dst] -> if dst="" then fail "invalidArgument"; V.Blob (G2.to_compressed (Bls_hash.hash_g2 ~dst msg))
    | 13,[pairs] ->
      let n=count 144 pairs in
      let parsed=List.init n (fun i ->
        let p=g1 (String.sub pairs (i*144) 48) in
        let q=g2 (String.sub pairs (i*144+48) 96) in p,q) in
      V.Bool (Bls_pairing.pairing_check parsed)
    | 14,[pk;msg;sig_] ->
      let pk=g2 pk in let sig_=g1 sig_ in
      let pk=nonzero2 pk in let sig_=nonzero1 sig_ in
      V.Bool (Bls_pairing.pairing_check [sig_,G2.generator;
        G1.neg (Bls_hash.hash_g1 ~dst:dst_ic msg),pk])
    | 15,[pk;msg;sig_] ->
      let pk=g1 pk in let sig_=g2 sig_ in
      let pk=nonzero1 pk in let sig_=nonzero2 sig_ in
      V.Bool (Bls_pairing.pairing_check [pk,Bls_hash.hash_g2 ~dst:dst_eth msg;
        G1.neg G1.generator,sig_])
    | 16,[pk;proof] ->
      let key=g1 pk in let proof=g2 proof in
      let key=nonzero1 key in let proof=nonzero2 proof in
      V.Bool (Bls_pairing.pairing_check [key,Bls_hash.hash_g2 ~dst:dst_pop pk;
        G1.neg G1.generator,proof])
    | 17,[points] -> V.Blob (G1.to_compressed (List.fold_left G1.add G1.infinity (chunks 48 g1 points)))
    | 18,[points] -> V.Blob (G2.to_compressed (List.fold_left G2.add G2.infinity (chunks 96 g2 points)))
    | _ -> fail "invalidArgument"

let evaluate opcode _type_arguments _types arguments =
  try
    let value = if opcode >= 19 && opcode <= 21 then aggregate opcode arguments
      else blob_operation opcode arguments in
    Ok (V.Variant ("ok",value))
  with Invalid label -> Ok (V.Variant ("err",V.Variant (label,V.Tup [])))
