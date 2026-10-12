open Mo_types

let max_bytes = 4096
let max_text_bytes = 5653
let error_type = Type.sum [
  "tooLarge", Type.unit;
  "invalidCharacter", Type.Prim Type.Nat64;
]
let result_type = Type.sum ["ok", Type.blob; "err", error_type]
