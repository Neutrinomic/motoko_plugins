//MOC-FLAG --plugin ../../../dist/sha256 --plugin ../../../dist/candidx
import Prim "mo:⛔";

let digest = Prim.sha256("abc");
assert Prim.to_candid_canonical(digest) ==
  Prim.to_candid_canonical(Prim.blobToArray(digest));
