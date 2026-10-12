//MOC-FLAG --plugin ../../../../dist/hmac-sha2
import Prim "mo:⛔";
let state = Prim.blobToArray(Prim.hmac_sha256_init("key"));
let last = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(136, func(i) {
  if (i == 64) 31 else if (i > 64 and i < 72) 255 else state[i]
}));
ignore Prim.hmac_sha256_update(last, "x");
