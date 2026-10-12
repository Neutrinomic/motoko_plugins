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
let evaluate opcode _type_arguments _types arguments =
  try
    let args = List.map (function V.Blob b -> b | _ -> fail "invalidArgument") arguments in
    let value = match opcode,args with
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
    | _ -> fail "invalidArgument" in
    Ok (V.Variant ("ok",value))
  with Invalid label -> Ok (V.Variant ("err",V.Variant (label,V.Tup [])))
