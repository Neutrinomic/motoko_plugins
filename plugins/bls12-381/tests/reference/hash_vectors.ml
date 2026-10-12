(* RFC 9380 regression cases, transcribed from vectors/ JSON files.
   Source: cfrg/draft-irtf-cfrg-hash-to-curve at
   664b13592116cecc9e52fb192dcde0ade36f904e. *)

let fail message = failwith message
let hex bytes = String.concat "" (List.init (String.length bytes) (fun i -> Printf.sprintf "%02x" (Char.code bytes.[i])))
let () =
  let point = Bls_hash.hash_g1 ~dst:"QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_" "" in
  let expected = Bls_group.G1.Point ((Z.of_string "0x052926add2207b76ca4fa57a8734416c8dc95e24501772c814278700eed6d1e4e8cf62d9c09db0fac349612b759e79a1"), (Z.of_string "0x08ba738453bfed09cb546dbb0783dbb3a5f1f566ed67bb6be0e8c67e2e81a4cc68ee29813bb7994998f3eae0c9c6a265")) in
  if not (Bls_group.G1.equal point expected) then fail "G1 RFC9380 vector 0";
  if not (Bls_group.G1.is_in_subgroup point) then fail "G1 subgroup 0";
  let point = Bls_hash.hash_g1 ~dst:"QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_" "abc" in
  let expected = Bls_group.G1.Point ((Z.of_string "0x03567bc5ef9c690c2ab2ecdf6a96ef1c139cc0b2f284dca0a9a7943388a49a3aee664ba5379a7655d3c68900be2f6903"), (Z.of_string "0x0b9c15f3fe6e5cf4211f346271d7b01c8f3b28be689c8429c85b67af215533311f0b8dfaaa154fa6b88176c229f2885d")) in
  if not (Bls_group.G1.equal point expected) then fail "G1 RFC9380 vector 1";
  if not (Bls_group.G1.is_in_subgroup point) then fail "G1 subgroup 1";
  let point = Bls_hash.hash_g1 ~dst:"QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_" "abcdef0123456789" in
  let expected = Bls_group.G1.Point ((Z.of_string "0x11e0b079dea29a68f0383ee94fed1b940995272407e3bb916bbf268c263ddd57a6a27200a784cbc248e84f357ce82d98"), (Z.of_string "0x03a87ae2caf14e8ee52e51fa2ed8eefe80f02457004ba4d486d6aa1f517c0889501dc7413753f9599b099ebcbbd2d709")) in
  if not (Bls_group.G1.equal point expected) then fail "G1 RFC9380 vector 2";
  if not (Bls_group.G1.is_in_subgroup point) then fail "G1 subgroup 2";
  let point = Bls_hash.hash_g1 ~dst:"QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_" "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" in
  let expected = Bls_group.G1.Point ((Z.of_string "0x15f68eaa693b95ccb85215dc65fa81038d69629f70aeee0d0f677cf22285e7bf58d7cb86eefe8f2e9bc3f8cb84fac488"), (Z.of_string "0x1807a1d50c29f430b8cafc4f8638dfeeadf51211e1602a5f184443076715f91bb90a48ba1e370edce6ae1062f5e6dd38")) in
  if not (Bls_group.G1.equal point expected) then fail "G1 RFC9380 vector 3";
  if not (Bls_group.G1.is_in_subgroup point) then fail "G1 subgroup 3";
  let point = Bls_hash.hash_g1 ~dst:"QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_" "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" in
  let expected = Bls_group.G1.Point ((Z.of_string "0x082aabae8b7dedb0e78aeb619ad3bfd9277a2f77ba7fad20ef6aabdc6c31d19ba5a6d12283553294c1825c4b3ca2dcfe"), (Z.of_string "0x05b84ae5a942248eea39e1d91030458c40153f3b654ab7872d779ad1e942856a20c438e8d99bc8abfbf74729ce1f7ac8")) in
  if not (Bls_group.G1.equal point expected) then fail "G1 RFC9380 vector 4";
  if not (Bls_group.G1.is_in_subgroup point) then fail "G1 subgroup 4";
  let point = Bls_hash.hash_g2 ~dst:"QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_" "" in
  let expected = Bls_group.G2.Point (((Z.of_string "0x0141ebfbdca40eb85b87142e130ab689c673cf60f1a3e98d69335266f30d9b8d4ac44c1038e9dcdd5393faf5c41fb78a"), (Z.of_string "0x05cb8437535e20ecffaef7752baddf98034139c38452458baeefab379ba13dff5bf5dd71b72418717047f5b0f37da03d")), ((Z.of_string "0x0503921d7f6a12805e72940b963c0cf3471c7b2a524950ca195d11062ee75ec076daf2d4bc358c4b190c0c98064fdd92"), (Z.of_string "0x12424ac32561493f3fe3c260708a12b7c620e7be00099a974e259ddc7d1f6395c3c811cdd19f1e8dbf3e9ecfdcbab8d6"))) in
  if not (Bls_group.G2.equal point expected) then fail "G2 RFC9380 vector 0";
  if not (Bls_group.G2.is_in_subgroup point) then fail "G2 subgroup 0";
  let point = Bls_hash.hash_g2 ~dst:"QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_" "abc" in
  let expected = Bls_group.G2.Point (((Z.of_string "0x02c2d18e033b960562aae3cab37a27ce00d80ccd5ba4b7fe0e7a210245129dbec7780ccc7954725f4168aff2787776e6"), (Z.of_string "0x139cddbccdc5e91b9623efd38c49f81a6f83f175e80b06fc374de9eb4b41dfe4ca3a230ed250fbe3a2acf73a41177fd8")), ((Z.of_string "0x1787327b68159716a37440985269cf584bcb1e621d3a7202be6ea05c4cfe244aeb197642555a0645fb87bf7466b2ba48"), (Z.of_string "0x00aa65dae3c8d732d10ecd2c50f8a1baf3001578f71c694e03866e9f3d49ac1e1ce70dd94a733534f106d4cec0eddd16"))) in
  if not (Bls_group.G2.equal point expected) then fail "G2 RFC9380 vector 1";
  if not (Bls_group.G2.is_in_subgroup point) then fail "G2 subgroup 1";
  let point = Bls_hash.hash_g2 ~dst:"QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_" "abcdef0123456789" in
  let expected = Bls_group.G2.Point (((Z.of_string "0x121982811d2491fde9ba7ed31ef9ca474f0e1501297f68c298e9f4c0028add35aea8bb83d53c08cfc007c1e005723cd0"), (Z.of_string "0x190d119345b94fbd15497bcba94ecf7db2cbfd1e1fe7da034d26cbba169fb3968288b3fafb265f9ebd380512a71c3f2c")), ((Z.of_string "0x05571a0f8d3c08d094576981f4a3b8eda0a8e771fcdcc8ecceaf1356a6acf17574518acb506e435b639353c2e14827c8"), (Z.of_string "0x0bb5e7572275c567462d91807de765611490205a941a5a6af3b1691bfe596c31225d3aabdf15faff860cb4ef17c7c3be"))) in
  if not (Bls_group.G2.equal point expected) then fail "G2 RFC9380 vector 2";
  if not (Bls_group.G2.is_in_subgroup point) then fail "G2 subgroup 2";
  let point = Bls_hash.hash_g2 ~dst:"QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_" "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" in
  let expected = Bls_group.G2.Point (((Z.of_string "0x19a84dd7248a1066f737cc34502ee5555bd3c19f2ecdb3c7d9e24dc65d4e25e50d83f0f77105e955d78f4762d33c17da"), (Z.of_string "0x0934aba516a52d8ae479939a91998299c76d39cc0c035cd18813bec433f587e2d7a4fef038260eef0cef4d02aae3eb91")), ((Z.of_string "0x14f81cd421617428bc3b9fe25afbb751d934a00493524bc4e065635b0555084dd54679df1536101b2c979c0152d09192"), (Z.of_string "0x09bcccfa036b4847c9950780733633f13619994394c23ff0b32fa6b795844f4a0673e20282d07bc69641cee04f5e5662"))) in
  if not (Bls_group.G2.equal point expected) then fail "G2 RFC9380 vector 3";
  if not (Bls_group.G2.is_in_subgroup point) then fail "G2 subgroup 3";
  let point = Bls_hash.hash_g2 ~dst:"QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_" "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" in
  let expected = Bls_group.G2.Point (((Z.of_string "0x01a6ba2f9a11fa5598b2d8ace0fbe0a0eacb65deceb476fbbcb64fd24557c2f4b18ecfc5663e54ae16a84f5ab7f62534"), (Z.of_string "0x11fca2ff525572795a801eed17eb12785887c7b63fb77a42be46ce4a34131d71f7a73e95fee3f812aea3de78b4d01569")), ((Z.of_string "0x0b6798718c8aed24bc19cb27f866f1c9effcdbf92397ad6448b5c9db90d2b9da6cbabf48adc1adf59a1a28344e79d57e"), (Z.of_string "0x03a47f8e6d1763ba0cad63d6114c0accbef65707825a511b251a660a9b3994249ae4e63fac38b23da0c398689ee2ab52"))) in
  if not (Bls_group.G2.equal point expected) then fail "G2 RFC9380 vector 4";
  if not (Bls_group.G2.is_in_subgroup point) then fail "G2 subgroup 4";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:32 "") <> "68a985b87eb6b46952128911f2a4412bbc302a9d759667f87f7a21d803f07235" then fail "XMD 38 vector 0";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:32 "abc") <> "d8ccab23b5985ccea865c6c97b6e5b8350e794e603b4b97902f53a8a0d605615" then fail "XMD 38 vector 1";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:32 "abcdef0123456789") <> "eff31487c770a893cfb36f912fbfcbff40d5661771ca4b2cb4eafe524333f5c1" then fail "XMD 38 vector 2";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:32 "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq") <> "b23a1d2b4d97b2ef7785562a7e8bac7eed54ed6e97e29aa51bfe3f12ddad1ff9" then fail "XMD 38 vector 3";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:32 "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") <> "4623227bcc01293b8c130bf771da8c298dede7383243dc0993d2d94823958c4c" then fail "XMD 38 vector 4";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:128 "") <> "af84c27ccfd45d41914fdff5df25293e221afc53d8ad2ac06d5e3e29485dadbee0d121587713a3e0dd4d5e69e93eb7cd4f5df4cd103e188cf60cb02edc3edf18eda8576c412b18ffb658e3dd6ec849469b979d444cf7b26911a08e63cf31f9dcc541708d3491184472c2c29bb749d4286b004ceb5ee6b9a7fa5b646c993f0ced" then fail "XMD 38 vector 5";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:128 "abc") <> "abba86a6129e366fc877aab32fc4ffc70120d8996c88aee2fe4b32d6c7b6437a647e6c3163d40b76a73cf6a5674ef1d890f95b664ee0afa5359a5c4e07985635bbecbac65d747d3d2da7ec2b8221b17b0ca9dc8a1ac1c07ea6a1e60583e2cb00058e77b7b72a298425cd1b941ad4ec65e8afc50303a22c0f99b0509b4c895f40" then fail "XMD 38 vector 6";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:128 "abcdef0123456789") <> "ef904a29bffc4cf9ee82832451c946ac3c8f8058ae97d8d629831a74c6572bd9ebd0df635cd1f208e2038e760c4994984ce73f0d55ea9f22af83ba4734569d4bc95e18350f740c07eef653cbb9f87910d833751825f0ebefa1abe5420bb52be14cf489b37fe1a72f7de2d10be453b2c9d9eb20c7e3f6edc5a60629178d9478df" then fail "XMD 38 vector 7";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:128 "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq") <> "80be107d0884f0d881bb460322f0443d38bd222db8bd0b0a5312a6fedb49c1bbd88fd75d8b9a09486c60123dfa1d73c1cc3169761b17476d3c6b7cbbd727acd0e2c942f4dd96ae3da5de368d26b32286e32de7e5a8cb2949f866a0b80c58116b29fa7fabb3ea7d520ee603e0c25bcaf0b9a5e92ec6a1fe4e0391d1cdbce8c68a" then fail "XMD 38 vector 8";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128" ~length:128 "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") <> "546aff5444b5b79aa6148bd81728704c32decb73a3ba76e9e75885cad9def1d06d6792f8a7d12794e90efed817d96920d728896a4510864370c207f99bd4a608ea121700ef01ed879745ee3e4ceef777eda6d9e5e38b90c86ea6fb0b36504ba4a45d22e86f6db5dd43d98a294bebb9125d5b794e9d2a81181066eb954966a487" then fail "XMD 38 vector 9";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:32 "") <> "e8dc0c8b686b7ef2074086fbdd2f30e3f8bfbd3bdf177f73f04b97ce618a3ed3" then fail "XMD 256 vector 0";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:32 "abc") <> "52dbf4f36cf560fca57dedec2ad924ee9c266341d8f3d6afe5171733b16bbb12" then fail "XMD 256 vector 1";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:32 "abcdef0123456789") <> "35387dcf22618f3728e6c686490f8b431f76550b0b2c61cbc1ce7001536f4521" then fail "XMD 256 vector 2";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:32 "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq") <> "01b637612bb18e840028be900a833a74414140dde0c4754c198532c3a0ba42bc" then fail "XMD 256 vector 3";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:32 "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") <> "20cce7033cabc5460743180be6fa8aac5a103f56d481cf369a8accc0c374431b" then fail "XMD 256 vector 4";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:128 "") <> "14604d85432c68b757e485c8894db3117992fc57e0e136f71ad987f789a0abc287c47876978e2388a02af86b1e8d1342e5ce4f7aaa07a87321e691f6fba7e0072eecc1218aebb89fb14a0662322d5edbd873f0eb35260145cd4e64f748c5dfe60567e126604bcab1a3ee2dc0778102ae8a5cfd1429ebc0fa6bf1a53c36f55dfc" then fail "XMD 256 vector 5";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:128 "abc") <> "1a30a5e36fbdb87077552b9d18b9f0aee16e80181d5b951d0471d55b66684914aef87dbb3626eaabf5ded8cd0686567e503853e5c84c259ba0efc37f71c839da2129fe81afdaec7fbdc0ccd4c794727a17c0d20ff0ea55e1389d6982d1241cb8d165762dbc39fb0cee4474d2cbbd468a835ae5b2f20e4f959f56ab24cd6fe267" then fail "XMD 256 vector 6";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:128 "abcdef0123456789") <> "d2ecef3635d2397f34a9f86438d772db19ffe9924e28a1caf6f1c8f15603d4028f40891044e5c7e39ebb9b31339979ff33a4249206f67d4a1e7c765410bcd249ad78d407e303675918f20f26ce6d7027ed3774512ef5b00d816e51bfcc96c3539601fa48ef1c07e494bdc37054ba96ecb9dbd666417e3de289d4f424f502a982" then fail "XMD 256 vector 7";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:128 "q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq") <> "ed6e8c036df90111410431431a232d41a32c86e296c05d426e5f44e75b9a50d335b2412bc6c91e0a6dc131de09c43110d9180d0a70f0d6289cb4e43b05f7ee5e9b3f42a1fad0f31bac6a625b3b5c50e3a83316783b649e5ecc9d3b1d9471cb5024b7ccf40d41d1751a04ca0356548bc6e703fca02ab521b505e8e45600508d32" then fail "XMD 256 vector 8";
  if hex (Bls_hash.expand_message_xmd ~dst:"QUUX-V01-CS02-with-expander-SHA256-128-long-DST-1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111" ~length:128 "a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") <> "78b53f2413f3c688f07732c10e5ced29a17c6a16f717179ffbe38d92d6c9ec296502eb9889af83a1928cd162e845b0d3c5424e83280fed3d10cffb2f8431f14e7a23f4c68819d40617589e4c41169d0b56e0e3535be1fd71fbb08bb70c5b5ffed953d6c14bf7618b35fc1f4c4b30538236b4b08c9fbf90462447a8ada60be495" then fail "XMD 256 vector 9";
  let invalid result = match result with Error _ -> () | Ok _ -> fail "Noncanonical field accepted" in
  invalid (Bls_hash.map_g1 (Bls_field.be_of_z 48 Bls_field.p));
  invalid (Bls_hash.map_g2 (Bls_field.be_of_z 48 Bls_field.p ^ String.make 48 '\000'));
  invalid (Bls_hash.map_g2 (String.make 48 '\000' ^ Bls_field.be_of_z 48 Bls_field.p));
  invalid (Bls_hash.map_g1 "");
  invalid (Bls_hash.map_g2 "");
  assert (Bls_hash.expand_message_xmd ~dst:"" ~length:0 "" = "");
  List.iter (fun length ->
      match Bls_hash.expand_message_xmd ~dst:"" ~length "" with
      | _ -> fail "Invalid XMD length accepted"
      | exception Invalid_argument _ -> ()) [-1; 8161; max_int];
  List.iter (fun u ->
      match Bls_hash.map_g1 (Bls_field.be_of_z 48 u) with
      | Error message -> fail message
      | Ok point ->
        assert (Bls_group.G1.is_on_curve point);
        assert (Bls_group.G1.is_in_subgroup point))
    [Z.zero; Z.one; Z.pred Bls_field.p];
  List.iter (fun (c0, c1) ->
      match Bls_hash.map_g2 (Bls_field.be_of_z 48 c0 ^ Bls_field.be_of_z 48 c1) with
      | Error message -> fail message
      | Ok point ->
        assert (Bls_group.G2.is_on_curve point);
        assert (Bls_group.G2.is_in_subgroup point))
    [(Z.zero, Z.zero); (Z.one, Z.zero); (Z.zero, Z.one);
     (Z.one, Z.one); (Z.pred Bls_field.p, Z.pred Bls_field.p)];
  (* Boundary expectations computed independently with Python hashlib SHA-256. *)
  List.iter (fun (dst_length, output_length, expected_digest) ->
      let dst = String.make dst_length 'd' in
      let expanded = Bls_hash.expand_message_xmd ~dst ~length:output_length "\000\255abc" in
      if hex (Bls_sha256.digest expanded) <> expected_digest then fail "XMD boundary") [
    (0, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (0, 1, "62c66a7a5dd70c3146618063c344e531e6d4b59e379808443ce962b3abd63c5a");
    (0, 31, "4f4c6a5d6587aa8cedc9a256af03f5bedcb1d64157e4b21f1441873a9b20dec9");
    (0, 33, "fb21fd262d72f28c98697f517d3ec7dd2f223df6b4a2d460ccdf4c819a1b5aad");
    (0, 8160, "b0ee4079e8d2d512d4377ead20382d00823965270b61e1f87a81c82dc2e6188a");
    (1, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (1, 1, "684888c0ebb17f374298b65ee2807526c066094c701bcc7ebbe1c1095f494fc1");
    (1, 31, "d10aa6992c4c82b63e29890397025f54b5de0bb81c840161a8f6fae766ce1fef");
    (1, 33, "cb6991f25b47a1513504eb2bf7696ad78a7b946e241889b24b4ce45473386e73");
    (1, 8160, "62df3b2d7e987919e08b71160ff87a6d9e53496e0fd1fc617349f77bba93b450");
    (255, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (255, 1, "ffe679bb831c95b67dc17819c63c5090d221aac6f4c7bf530f594ab43d21fa1e");
    (255, 31, "f7a09f3dc212f4df8392788075ca011fa40d1de34b100cd39bcf41efd5e25413");
    (255, 33, "9d6302ca3e339d56048bcfd0717dc3c11b828ec90870499d7667047d1be73bd3");
    (255, 8160, "d79dd708ecc59d7edcc488996b5e66dc8d0008c9dc38a2fbbf05a660b864bcd8");
    (256, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (256, 1, "457e4854863e7efaa03266ad781822ecce69df31a511786118c10771a87e69f2");
    (256, 31, "7a0aa1bb57b45b7576e67d0add1a07370af60ad1ca47863cf52a956f95428c57");
    (256, 33, "2ca8b2563b3febaf85c1498d2882cb3dec2498ff88b8bd170fecfe04625a54ec");
    (256, 8160, "c00c833daaadf727c2b0f859a5c74823e5f9b5ba2779b127e8eda84d83c54105");
    (4096, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (4096, 1, "cd0aa9856147b6c5b4ff2b7dfee5da20aa38253099ef1b4a64aced233c9afe29");
    (4096, 31, "764264c4afb10f3221092996a8763d04a5667e2bb59b1e4c589ffbedf3ba8234");
    (4096, 33, "bc0b7e8f3a93d0a1871483348ab49b006daf3d116bafd1908a120b9c8932e4dd");
    (4096, 8160, "8e7fa794a53832c8701120d04c2719fbec2f49ce0c6787c4603d1aecd790e2ec");
  ];
  let zero_map = match Bls_hash.map_g1 (String.make 48 '\000') with Ok p -> p | Error m -> fail m in
  List.iter (fun input ->
      let u = Z.of_string input in
      assert (Bls_field.Fp.equal (Bls_field.Fp.mul (Z.of_int 11) (Bls_field.Fp.square u)) (Bls_field.Fp.neg Z.one));
      match Bls_hash.map_g1 (Bls_field.be_of_z 48 u) with
      | Error message -> fail message
      | Ok point ->
        let expected = if Z.testbit u 0 then Bls_group.G1.neg zero_map else zero_map in
        if not (Bls_group.G1.equal point expected) then fail "Nonzero exceptional SWU map")
    ["0x01f7462c8b6cbf74db38f4a9a3d71bda12f01df4948d09ff046edbdd403fc31088b69520ee5c57fb7cc51062bde821b8";
     "0x1809cbbdae1327256fe2b30c9f7490fd51872d905ef808c062c1f6c3b671331395f56addc2f7a8043d39ef9d421788f3"];
  print_endline "RFC9380: all 10 G1/G2 vectors and all 20 XMD vectors passed; noncanonical and short maps rejected"
