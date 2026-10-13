module C = Mo_values.Compute_plugin

let public_key = C.Prepared.create ~owner:"ml-dsa" ~name:"MLDSAPreparedPublicKey"
let secret_key = C.Prepared.create ~owner:"ml-dsa" ~name:"MLDSAPreparedSecretKey"
