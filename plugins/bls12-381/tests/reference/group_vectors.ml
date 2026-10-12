(* Portable field/group reference tests. The fixed generator multiples below
   were independently checked with py_ecc 8.0.0, optimized_bls12_381.multiply
   and bls.point_compression, on 2026-10-12. *)
open Bls_field
open Bls_group
let hex s = String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))
let unhex s = String.init (String.length s / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub s (2*i) 2)))
let check b = if not b then failwith "check failed"
let get = function Ok x -> x | Error e -> failwith e
let error = function Ok _ -> false | Error _ -> true
let () =
 (* Adapter semantics used by field reduction and exponentiation. *)
 check (Z.equal (Z.div (Z.of_int (-7)) (Z.of_int 3)) (Z.of_int (-2)));
 check (Z.equal (Z.erem (Z.of_int (-7)) (Z.of_int 3)) (Z.of_int 2));
 check (Z.equal (Z.shift_right (Z.of_int (-7)) 1) (Z.of_int (-4)));
 check (Z.equal (Z.extract Z.minus_one 9 8) (Z.of_int 255));
 check (Z.equal (Z.invert (Z.of_int 3) (Z.of_int 11)) (Z.of_int 4));
 check (Z.equal (Z.powm (Z.of_int 3) Z.minus_one (Z.of_int 11)) (Z.of_int 4));
 check (Z.equal (Z.powm (Z.of_int 3) Z.zero Z.one) Z.zero);
 check (G1.is_in_subgroup G1.generator);
 check (G2.is_in_subgroup G2.generator);
 check (G1.is_infinity (G1.add G1.generator (G1.neg G1.generator)));
 check (G2.is_infinity (G2.add G2.generator (G2.neg G2.generator)));
 check (G1.equal (G1.mul G1.generator (Z.of_int 3)) (G1.add G1.generator (G1.add G1.generator G1.generator)));
 check (G2.equal (G2.mul G2.generator (Z.of_int 3)) (G2.add G2.generator (G2.add G2.generator G2.generator)));
 check (G1.is_infinity (G1.msm [G1.generator,Z.one; G1.generator,Z.minus_one]));
 check (G2.is_infinity (G2.msm [G2.generator,Z.one; G2.generator,Z.minus_one]));
 check (G1.equal G1.generator (get (G1.of_compressed (G1.to_compressed G1.generator))));
 check (G2.equal G2.generator (get (G2.of_compressed (G2.to_compressed G2.generator))));
 check (G1.is_infinity (get (G1.of_compressed (G1.to_compressed G1.infinity))));
 check (G2.is_infinity (get (G2.of_compressed (G2.to_compressed G2.infinity))));
 let mutate first bytes = String.make 1 (Char.chr first) ^ String.sub bytes 1 (String.length bytes - 1) in
 let inf1 = G1.to_compressed G1.infinity in
 let inf2 = G2.to_compressed G2.infinity in
 check (error (G1.of_compressed (mutate 0xe0 inf1)));
 check (error (G2.of_compressed (mutate 0xe0 inf2)));
 check (error (G1.of_compressed (mutate 0x40 inf1)));
 check (error (G2.of_compressed (mutate 0x40 inf2)));
 check (error (G1.of_compressed (mutate 0xc1 inf1)));
 check (error (G2.of_compressed (mutate 0xc1 inf2)));
 check (error (G1.of_compressed ""));
 check (error (G2.of_compressed ""));
 let p_bytes = be_of_z 48 p in
 check (error (G1.of_compressed (mutate (Char.code p_bytes.[0] lor 0x80) p_bytes)));
 check (error (G2.of_compressed (mutate (Char.code p_bytes.[0] lor 0x80) (p_bytes ^ String.make 48 '\000'))));
 check (error (G2.of_compressed ((mutate 0x80 (String.make 48 '\000')) ^ p_bytes)));
 check (error (scalar_of_bytes (be_of_z 32 r)));
 check (error (scalar_of_bytes (String.make 31 '\000')));
 check (Z.equal Z.zero (get (scalar_of_bytes (String.make 32 '\000'))));
 check (Z.equal (Z.pred r) (get (scalar_of_bytes (be_of_z 32 (Z.pred r)))));
 let torsion1 = G1.Point (Fp.zero,Fp.of_int 2) in
 check (G1.is_on_curve torsion1 && not (G1.is_in_subgroup torsion1));
 check (error (G1.of_compressed (G1.to_compressed torsion1)));
 check (G1.equal torsion1 (get (G1.of_compressed_unchecked (G1.to_compressed torsion1))));
 for i = 0 to 256 do
  let a = Fp2.of_z (Z.pow (Z.of_int (i+1)) 12) in
  let a = Fp2.add a (Fp.zero,Fp.of_int i) in
  match Fp2.sqrt (Fp2.square a) with Some b -> check (Fp2.equal (Fp2.square b) (Fp2.square a)) | None -> failwith "square has no square root"
 done;
 (* Fixed outputs exercise limb order, carry propagation and sign bits. *)
 List.iter (fun (scalar,expected_g1,expected_g2) ->
   let n = Z.of_string scalar in
   let actual_g1 = G1.mul G1.generator n in
   let actual_g2 = G2.mul G2.generator n in
   check (hex (G1.to_compressed actual_g1) = expected_g1);
   check (hex (G2.to_compressed actual_g2) = expected_g2);
   check (G1.equal actual_g1 (get (G1.of_compressed (unhex expected_g1))));
   check (G2.equal actual_g2 (get (G2.of_compressed (unhex expected_g2))))
 ) [
  "1",
  "97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb",
  "93e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8";
  "2",
  "a572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e",
  "aa4edef9c1ed7f729f520e47730a124fd70662a904ba1074728114d1031e1572c6c886f6b57ec72a6178288c47c335771638533957d540a9d2370f17cc7ed5863bc0b995b8825e0ee1ea1e1e4d00dbae81f14b0bf3611b78c952aacab827a053";
  "3",
  "89ece308f9d1f0131765212deca99697b112d61f9be9a5f1f3780a51335b3ff981747a0b2ca2179b96d2c0c9024e5224",
  "89380275bbc8e5dcea7dc4dd7e0550ff2ac480905396eda55062650f8d251c96eb480673937cc6d9d6a44aaa56ca66dc122915c824a0857e2ee414a3dccb23ae691ae54329781315a0c75df1c04d6d7a50a030fc866f09d516020ef82324afae";
  "65537",
  "88cab01b6d06a323e18f50141a694e7e71ab18ffdfab536a45ccf0b49a634ee82d00750e9f4c15d806c33a8950664d7f",
  "948a606f6a01429e4f7cc71d89b077128075d8101b7092d5fba8eb9189a57f34e9c4b442961357b1278f0464ea33087606c67e6c183435e5aec742d2d786f6435f61b143f64b2bc1f69678ee434eb4feed7952b0f15777c5d72cddc3976fb090";
  "314159265358979323846264338327950288419716939937510",
  "96ba72dacb9e9f4fbb1c96d458bf0b8a793609d72623c8137c120e54f6f6328cb112dec5a510c0d4a4481fbe7504c03c",
  "b27e14679f5e1a5a7fdf5350d8e97df71e5f9a31412147a87f4443f1be912c8dc800451986d553c0eaffe084c3ea89a813d4d64dddea03bf87d4b6a9f3ed7131c1196f639afad93311499c1d59f03a21b0068aedb481e7857081e2a667dc4be1";
 ];
 (* A non-subgroup point on G2 must never pass a public decoder. *)
 let rec find_torsion i =
   if i > 100 then failwith "no G2 torsion fixture found";
   let x = Fp.of_int i, Fp.one in
   match Fp2.sqrt (Fp2.add (Fp2.mul (Fp2.square x) x) (Fp.of_int 4,Fp.of_int 4)) with
   | None -> find_torsion (i+1)
   | Some y -> let p = G2.Point (x,y) in
     if G2.is_in_subgroup p then find_torsion (i+1) else p
 in
 let torsion2 = find_torsion 0 in
 check (G2.is_on_curve torsion2);
 check (error (G2.of_compressed (G2.to_compressed torsion2)));
 check (G2.equal torsion2 (get (G2.of_compressed_unchecked (G2.to_compressed torsion2))));
 (* Square roots must cover zero and values whose roots are imaginary. *)
 List.iter (fun value -> match Fp2.sqrt value with
    | Some root -> check (Fp2.equal (Fp2.square root) value)
    | None -> failwith "missing Fp2 square root")
   [Fp2.zero; Fp2.one; (Fp.neg Fp.one,Fp.zero); (Fp.zero,Fp.of_int 2)];
 for i = 1 to 128 do
   let a = Fp2.of_int i in
   let z = Fp2.add a (Fp.zero,Fp.of_int (i+1)) in
   check (Fp2.equal (Fp2.mul z (Fp2.inv z)) Fp2.one)
 done;
 print_endline "BLS field/group vectors passed"
