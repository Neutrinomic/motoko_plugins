//MOC-FLAG --plugin ../../../dist/candidx --plugin ../../../dist/sha256
import Prim "mo:⛔";
func expectOk(result : { #ok : Blob; #err : Text }) : Blob {
  switch result {
    case (#ok bytes) bytes;
    case (#err message) Prim.trap(message);
  }
};

let first = { amount = 255 : Nat; omitted = null : ?Text };
let second = { amount = 255 : Nat };
assert Prim.sha256(expectOk(Prim.to_candid_canonical(first))) ==
  Prim.sha256(expectOk(Prim.to_candid_canonical(second)));
assert Prim.sha256(expectOk(Prim.to_candid_canonical(1 : Nat))) !=
  Prim.sha256(expectOk(Prim.to_candid_canonical(2 : Nat)));
