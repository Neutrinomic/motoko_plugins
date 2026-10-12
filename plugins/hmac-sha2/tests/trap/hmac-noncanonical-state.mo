//MOC-FLAG --plugin ../../../../dist/hmac-sha2
import Prim "mo:⛔";
let state = Prim.blobToArray(Prim.hmac_sha512_init("key"));
let corrupt = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(272, func(i) {
  if (i == 271) 1 else state[i]
}));
ignore Prim.hmac_sha512_update(corrupt, "message");
