module T = Mo_types.Type
let error_labels = ["invalidLength"; "invalidHrp"; "mixedCase"; "invalidCharacter"; "invalidChecksum"; "invalidData"; "invalidPadding"; "invalidBitWidth"]
let error_type = T.sum (List.map (fun label -> label, T.unit) error_labels)
let encoding = T.sum ["bech32", T.unit; "bech32m", T.unit]
let decoded = T.obj T.Object ["hrp", T.text; "data", T.blob; "encoding", encoding]
let result payload = T.sum ["ok", payload; "err", error_type]
