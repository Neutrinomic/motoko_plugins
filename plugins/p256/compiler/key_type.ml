module C = Mo_values.Compute_plugin
let public_key = C.Prepared.create ~owner:"p256" ~name:"P256PreparedPublicKey"
let public_key_type = C.Prepared.typ public_key
let payload_size = Prepared_layout.payload_size
